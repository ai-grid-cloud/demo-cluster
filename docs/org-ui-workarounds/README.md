# Org UI workarounds on site-a

This directory holds two workarounds that make the Org UI (the MaaS Portal) work for tenant
users on the ingress cluster `site-a` (`ocp.bclkw.sandbox2619.opentlc.com`). Both were applied
to the cluster by hand. The manifests here are exported from the live cluster, with
cluster-assigned fields removed, so you can review, reapply, or remove them.

Nothing in the product creates these objects yet. Treat them as temporary until the product
covers each gap.

| ID | Directory | What it fixes |
| --- | --- | --- |
| X6 | [`x6-portal-on-maas-gateway/`](x6-portal-on-maas-gateway/) | Serves the Org UI at `/maas-portal` on the MaaS gateway, behind an OIDC auth proxy. |
| X15 | [`x15-portal-oidc-egress/`](x15-portal-oidc-egress/) | Lets the portal pods reach the OIDC issuer on port 443. |

## X6: Serve the Org UI on the MaaS gateway

### Why it exists

The operator deploys the MaaS Portal (Service `redhat-ods-applications/maas-portal`, port
`8443`), but doesn't put it on the MaaS gateway. Tenants bring their own identity provider
through OIDC, and the only path for that is the MaaS gateway. So the Org UI has to be served at
`/maas-portal` on the MaaS gateway, behind its own kube-auth-proxy that signs users in to
Keycloak with OIDC, with its own HTTPRoutes and AuthPolicies.

These manifests follow the public pattern in
[`lphiri/maas-portal-integration-poc` `deploy/maas-portal`](https://github.com/lphiri/maas-portal-integration-poc/tree/main/deploy/maas-portal).
Every object carries the label `app.kubernetes.io/part-of=maas-consumer-deploy`.

### What the objects do

All objects are in namespace `openshift-ingress`, except the ReferenceGrant.

- **Hostname:** both HTTPRoutes serve `maas.apps.ocp.bclkw.sandbox2619.opentlc.com`. They
  attach to Gateway `maas-default-gateway`, listener `http`.
- **OIDC issuer:** `https://keycloak-maas-db.apps.ocp.hf299.sandbox3324.opentlc.com/realms/saas`,
  the Keycloak realm `saas` on the hub.

| File | Kind and name | What it does |
| --- | --- | --- |
| `configmap-maas-consumer-deploy-parameters.yaml` | ConfigMap `maas-consumer-deploy-parameters` | The parameters the bundle was rendered from. None of the other objects reads it. Several values are upstream examples, not what site-a uses. |
| `configmap-maas-consumer-oidc-ca.yaml` | ConfigMap `maas-consumer-oidc-ca` | The CA chain for the issuer's TLS certificate: the public ZeroSSL intermediate and Sectigo root. The auth proxy reads it as `--provider-ca-file`. |
| `serviceaccount-maas-consumer-auth-proxy.yaml` | ServiceAccount `maas-consumer-auth-proxy` | Identity for the auth proxy pods. |
| `deployment-maas-consumer-auth-proxy.yaml` | Deployment `maas-consumer-auth-proxy` | One replica of `odh-kube-auth-proxy`. It signs users in to the issuer, sets cookie `_maas_consumer_proxy` for the portal host (24-hour lifetime, refreshed every 4 minutes), and answers `/oauth2/auth` with the access token and `X-Auth-Request-*` headers. Its callback is `https://maas.apps.ocp.bclkw.sandbox2619.opentlc.com/oauth2/callback`. It listens on `4180` (HTTP) and `9000` (metrics). |
| `service-maas-consumer-auth-proxy.yaml` | Service `maas-consumer-auth-proxy` | Exposes ports `4180` and `9000` of the auth proxy. |
| `networkpolicy-maas-consumer-auth-proxy-ingress.yaml` | NetworkPolicy `maas-consumer-auth-proxy-ingress` | Admits traffic to the auth proxy on `4180` only from Authorino (`kuadrant-system`) and the `maas-default-gateway` pods. |
| `httproute-maas-consumer-oauth2.yaml` | HTTPRoute `maas-consumer-oauth2` | Sends `/oauth2` to the auth proxy on port `4180`, for sign-in and the callback. |
| `httproute-maas-consumer-ui.yaml` | HTTPRoute `maas-consumer-ui` | Redirects `/maas-portal` to `/maas-portal/` (302). Sends `/maas-portal/*` to Service `redhat-ods-applications/maas-portal` on port `8443`, with the prefix rewritten to `/`. Strips client-supplied identity headers (`x-maas-*`, `x-auth-request-*`, `x-forwarded-*`), and sets `Cache-Control: no-store` on responses. |
| `referencegrant-maas-consumer-portal-from-gateway-routes.yaml` | ReferenceGrant `maas-consumer-portal-from-gateway-routes` (namespace `redhat-ods-applications`) | Lets HTTPRoutes in `openshift-ingress` reference Service `maas-portal`. |
| `authpolicy-maas-consumer-oauth2-anonymous.yaml` | AuthPolicy `maas-consumer-oauth2-anonymous` | Allows anonymous access to the `/oauth2` route, so users can reach the sign-in page. |
| `authpolicy-maas-consumer-ui-oidc.yaml` | AuthPolicy `maas-consumer-ui-oidc` | Protects the portal route. It accepts either a bearer JWT from the issuer whose `azp` is `tenant-demo`, or a browser session cookie, which it checks by calling the auth proxy's `/oauth2/auth`. It then sets `Authorization`, `x-forwarded-access-token`, `x-maas-username`, `x-maas-group`, `x-maas-orgid` and `x-maas-roles` for the portal, and drops the proxy's own cookie. Without a session it redirects to `/oauth2/start`. |
| `tokenratelimitpolicy-maas-consumer-oauth2-non-inference.yaml` | TokenRateLimitPolicy `maas-consumer-oauth2-non-inference` | Overrides the gateway's token rate limit default on the `/oauth2` route with a limit that never applies (`when: "false"`). |
| `tokenratelimitpolicy-maas-consumer-ui-non-inference.yaml` | TokenRateLimitPolicy `maas-consumer-ui-non-inference` | The same, for the portal route. |
| `envoyfilter-maas-consumer-payload-processing-bypass.yaml` | EnvoyFilter `maas-consumer-payload-processing-bypass` | Turns off the inference payload processor (`ext_proc` filters `ipp` and `ipp-pre`) on both portal route rules and on the `/oauth2` route rule. |
| `secret-maas-consumer-auth-proxy-creds.yaml.example` | Secret `maas-consumer-auth-proxy-creds` (placeholder) | The auth proxy's client ID, client secret, and cookie secret. The values are `REPLACE_ME`. The `.example` suffix keeps `oc apply -f <directory>` from reading it. |

### Before you apply

- Register `https://<portal host>/oauth2/callback` as a redirect URI on the OIDC client in
  Keycloak.
- To use these manifests on another cluster, change the portal hostname, the issuer URL, the
  redirect URL, the cookie domain, and the CA chain to match that cluster.

### Apply

1. Copy `secret-maas-consumer-auth-proxy-creds.yaml.example` to a file outside this
   repository, replace each `REPLACE_ME`, and create the Secret:

   ```sh
   oc apply -f /path/outside/repo/secret-maas-consumer-auth-proxy-creds.yaml
   ```

1. Apply the other objects:

   ```sh
   oc apply -f docs/org-ui-workarounds/x6-portal-on-maas-gateway/
   ```

1. Open `https://maas.apps.ocp.bclkw.sandbox2619.opentlc.com/maas-portal/`. You're redirected
   to Keycloak to sign in, and then back to the portal.

### Remove

```sh
oc delete -f docs/org-ui-workarounds/x6-portal-on-maas-gateway/
oc delete secret maas-consumer-auth-proxy-creds -n openshift-ingress
```

## X15: Allow the portal to reach the OIDC issuer

### Why it exists

The operator's NetworkPolicy `redhat-ods-applications/maas-portal` selects the portal pods
(`deployment: maas-portal`) and allows egress only to DNS, the Kubernetes API on `6443`, and the
`maas-ui` and `gen-ai-ui` pods. It blocks egress on `443`, so the portal (core-bff) can't reach
the OIDC issuer to fetch its discovery document or JWKS.

### What the object does

NetworkPolicy `redhat-ods-applications/maas-portal-oidc-egress` selects the same pods and allows
egress on TCP `443` to any destination. NetworkPolicies are additive, so the operator's policy
stays in force for everything else. The policy's `app.kubernetes.io/part-of` label is the one it
had on the cluster.

### Apply

```sh
oc apply -f docs/org-ui-workarounds/x15-portal-oidc-egress/networkpolicy.yaml
```

### Remove

```sh
oc delete -f docs/org-ui-workarounds/x15-portal-oidc-egress/networkpolicy.yaml
```
