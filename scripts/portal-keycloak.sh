#!/usr/bin/env bash
# Keycloak's side of the MaaS Portal sign-in on site-a
# (deployment/clusters/site-a/maas-portal/, temporary), in realm ai-grid on demo1's hub:
#  1. client maas-cli (public) takes the browser flow with PKCE and site-a's portal callback
#     https://<site-a MaaS host>/oauth2/callback, and the portal origin as a post-logout redirect;
#     existing redirect URIs are kept (the CLI uses the client too);
#  2. client ai-grid-broker in realms org1-idp and org2-idp accepts the broker's logout response,
#     so /oauth2/sign_out completes for a brokered user;
#  3. test user org1-admin: org1, group /org1/group1, organization role "admins" (MaaS treats a user
#     as an organization admin only with that role in https://redhat.com/maas/orgs). Its password is
#     generated once and kept in hub Secret keycloak/ai-grid-test-users, key org1-admin.
#
# Through Keycloak's admin API, run by hand, safe to rerun; not Argo CD, because the console's git
# writer can push to this repository (deployment/README.md). Secrets (the admin login, the test
# password) reach curl and oc through pipes or the environment, never argv, and are never printed.
#   HOST_KUBECONFIG=<hub kubeconfig> SITE_A_KUBECONFIG=<site-a kubeconfig> bash scripts/portal-keycloak.sh
set -euo pipefail
: "${HOST_KUBECONFIG:?set HOST_KUBECONFIG to the kubeconfig of the hub}"
: "${SITE_A_KUBECONFIG:?set SITE_A_KUBECONFIG to the kubeconfig of site-a}"
ns=${KEYCLOAK_NS:-keycloak} realm=ai-grid cid=maas-cli
log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
kc() { oc --kubeconfig "$HOST_KUBECONFIG" "$@"; }
kc whoami >/dev/null || die "can't reach the hub with $HOST_KUBECONFIG"

# The Keycloak that serves the tenants' issuer (hub ConfigMap rhoai-tenant-oidc), not an assumed one.
issuer=$(kc get configmap rhoai-tenant-oidc -n redhat-ai-grid -o jsonpath='{.data.issuerUrl}')
[[ $issuer == https://*/realms/$realm ]] || die "unexpected issuer '$issuer'"
kchost=${issuer#https://}; kchost=${kchost%%/*}
[[ $(kc get route maas-keycloak -n "$ns" -o jsonpath='{.spec.host}') == "$kchost" ]] \
  || die "Route $ns/maas-keycloak doesn't serve the issuer host; set KEYCLOAK_NS"

# site-a's MaaS host: the gateway's https listener.
mhost=$(oc --kubeconfig "$SITE_A_KUBECONFIG" get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.spec.listeners[?(@.name=="https")].hostname}')
[[ -n $mhost ]] || die "site-a's maas-default-gateway has no https hostname"
callback="https://$mhost/oauth2/callback" origin="https://$mhost"

au=$(kc get secret maas-keycloak-initial-admin -n "$ns" -o jsonpath='{.data.username}' | base64 -d)
ap=$(kc get secret maas-keycloak-initial-admin -n "$ns" -o jsonpath='{.data.password}' | base64 -d)
tok=$(printf %s "$ap" | curl -fsS -d grant_type=password -d client_id=admin-cli --data-urlencode "username=$au" \
  --data-urlencode password@- "https://$kchost/realms/master/protocol/openid-connect/token" | jq -r .access_token); unset ap
[[ -n $tok && $tok != null ]] || die "Keycloak admin login failed"
api() { curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$tok") -H 'Content-Type: application/json' "$@"; }
admin="https://$kchost/admin/realms"
base="$admin/$realm"

# 1. maas-cli. Post-logout redirect URIs are one attribute, separated by "##".
id=$(api "$base/clients?clientId=$cid" | jq -re '.[0].id') || die "client $cid missing in realm $realm"
api "$base/clients/$id" | jq --arg cb "$callback" --arg o "$origin" '
  if .publicClient != true then error("client is not public") else . end
  | .standardFlowEnabled = true
  | .redirectUris = ((.redirectUris // []) + [$cb] | unique)
  | .attributes["pkce.code.challenge.method"] = "S256"
  | .attributes["post.logout.redirect.uris"] =
      ((.attributes["post.logout.redirect.uris"] // "" | split("##") | map(select(. != ""))) + [$o + "/*"] | unique | join("##"))' \
  | api -X PUT "$base/clients/$id" --data-binary @- >/dev/null
log "client $cid: PKCE, callback $callback"

# 2. The broker's logout response, in each provider realm that exists.
for org in org1 org2; do
  idp=$org-idp
  api "$admin/$idp" >/dev/null 2>&1 || { log "realm $idp not found, skipped"; continue; }
  bid=$(api "$admin/$idp/clients?clientId=ai-grid-broker" | jq -r '.[0].id // empty')
  [[ -n $bid ]] || { log "client ai-grid-broker not found in $idp, skipped"; continue; }
  api "$admin/$idp/clients/$bid" | jq --arg u "https://$kchost/realms/$realm/broker/$idp/endpoint/logout_response" '
    .attributes["post.logout.redirect.uris"] =
      ((.attributes["post.logout.redirect.uris"] // "" | split("##") | map(select(. != ""))) + [$u] | unique | join("##"))' \
    | api -X PUT "$admin/$idp/clients/$bid" --data-binary @- >/dev/null
  log "realm $idp: broker logout response allowed"
done

# 3. org1-admin, the way demo-tenants.sh adds alice, with role "admins".
u=org1-admin org=org1
oid=$(api "$base/organizations?search=$org&exact=true" | jq -re '.[0].id') || die "organization $org not found"
kc get secret ai-grid-test-users -n "$ns" >/dev/null 2>&1 || kc create secret generic ai-grid-test-users -n "$ns" >/dev/null
uid=$(api "$base/users?username=$u&exact=true" | jq -r '.[0].id // empty')
pw=$(kc get secret ai-grid-test-users -n "$ns" -o jsonpath="{.data.$u}" 2>/dev/null | base64 -d)
pw=${pw:-$(openssl rand -base64 18)}
attrs=$(jq -nc --arg org "$org" --arg oid "$oid" \
  '{maas_orgs: [([{organization_id: $oid, organization_name: $org, roles: ["admins"]}] | tojson)]}')
body=$(PW=$pw jq -n --arg u "$u" --arg org "$org" --argjson attrs "$attrs" '{username: $u, enabled: true,
  emailVerified: true, email: ($u + "@users.example.net"), firstName: $u, lastName: $org, attributes: $attrs,
  credentials: [{type: "password", value: env.PW, temporary: false}]}')
if [[ -z $uid ]]; then
  printf %s "$body" | api -X POST "$base/users" --data-binary @- >/dev/null
  uid=$(api "$base/users?username=$u&exact=true" | jq -re '.[0].id') || die "user $u not created"
else
  printf %s "$body" | api -X PUT "$base/users/$uid" --data-binary @- >/dev/null
fi
unset body
B64=$(printf '%s' "$pw" | base64 | tr -d '\n') jq -n --arg k "$u" '{data: {($k): env.B64}}' \
  | kc patch secret ai-grid-test-users -n "$ns" --type merge --patch-file /dev/stdin >/dev/null; unset pw
api -X POST "$base/organizations/$oid/members" -d "\"$uid\"" >/dev/null 2>&1 || true   # 409 when already a member
gid=$(api "$base/group-by-path/$org/group1" | jq -re .id) || die "group /$org/group1 not found"
api -X PUT "$base/users/$uid/groups/$gid" >/dev/null
unset tok
log "user $u: $org admin, group /$org/group1 (password in Secret $ns/ai-grid-test-users, key $u)"
