# MaaS Portal sign-in on site-a (temporary)

Tenants open the MaaS Portal (the Org UI) at `https://<site-a's MaaS host>/maas-portal/`
and sign in with the hub's Keycloak, realm `ai-grid`. These files attach the
portal that the DSC deploys (`dashboard.maasPortal: Managed` in `../rhoai.yaml`)
to site-a's MaaS gateway, behind an OIDC sign-in:

- a sign-in proxy (kube-auth-proxy, an oauth2-proxy build) that holds the
  browser session and signs in with the public client `maas-cli` using PKCE;
- `/maas-portal` and `/oauth2` routes on the gateway's `https` listener;
- Authorino rules that accept a bearer token from the issuer for `maas-cli`, or
  a session cookie checked with the proxy, and pass the user's token and the
  `x-maas-*` identity headers to the portal;
- exemptions from the inference payload processors and the gateway's
  default-deny token limit for those two routes.

`../../../apps/maas-portal-site-a.yaml` is the Argo CD Application that applies
this directory to site-a. The proxy's cookie secret is generated on site-a by the
hub Policy `maas-portal-proxy-secret` (`../../../hub/maas-portal-proxy-secret.yaml`).
Keycloak's side (the callback on `maas-cli`, the test user `org1-admin`) is set
by an admin-API script, not by Argo CD.

## Source

Rendered from Lindani Phiri's
[lphiri/maas-portal-integration-poc](https://github.com/lphiri/maas-portal-integration-poc)
`deploy/maas-portal` at `f163e02` (MIT; `third-party/maas-portal-integration-poc.LICENSE`),
one file per bundle file, with `kubectl kustomize` and these `parameters.env` values:

```
workloadNamespace=redhat-ods-applications
gatewayNamespace=openshift-ingress
gatewayName=maas-default-gateway
gatewayListenerName=https
publicHostname=<site-a's MaaS host, the https listener's hostname in ../rhoai.yaml>
cookieDomain=<the same host>
portalServiceName=maas-portal
oidcIssuerUrl=<issuerUrl in ../../../hub/tenant-oidc.yaml>
oidcClientId=maas-cli
authProxySecretName=maas-consumer-auth-proxy-creds
authorinoNamespace=kuadrant-system
portalPathPrefix=/maas-portal
portalRewritePrefix=/
oauthPathPrefix=/oauth2
portalRouteName=maas-consumer-ui
oauthRouteName=maas-consumer-oauth2
authProxyName=maas-consumer-auth-proxy
resourceNamePrefix=maas-consumer-
partOfLabel=maas-consumer-deploy
clusterDnsDomain=cluster.local
authProxyHttpPort=4180
sessionCheckTimeout=2s
organizationClaim=https://redhat.com/maas/orgs
organizationIdPrimaryClaim=organization_id
organizationIdFallbackClaim=tenant_id
usernamePrimaryClaim=preferred_username
usernameFallbackClaim=sub
oidcGroupsClaim=groups
oidcEmailClaim=email
```

Edits beyond the parameters (each file's header says why):
`maas-portal-04-auth-proxy.yaml` signs in with the public client using PKCE and a
placeholder client secret, has no private CA mount (so the `maas-consumer-oidc-ca`
ConfigMap isn't generated), pins the proxy image digest and takes the cookie secret
from the Policy's Secret; `maas-portal-23-backend-tls.yaml` verifies the portal's
certificate against the OpenShift service CA instead of `insecureSkipVerify`. The
parameters ConfigMap isn't applied: nothing reads it at run time.

Taken as is otherwise, including the 4-minute session refresh and the public
`/oauth2/*` path. A temporary route isn't the place to harden.

## Temporary

Remove this directory, `../../../apps/maas-portal-site-a.yaml`, the hub Policy and
`redhat-ods-applications` in `../rhoai.yaml`'s listeners once a nightly that
mounts the portal on the MaaS gateway itself (ai-gateway-controller PR 190,
ODH-ADR-MS-0008) reaches site-a. Check every nightly bump for objects in
`redhat-ai-gateway-infra` and routes on `maas-default-gateway` before syncing:
the two would collide on `/maas-portal` and `/oauth2`.

The Envoy route names in `maas-portal-22-payload-processing-bypass.yaml` are
positional (`<namespace>.<route>.<rule index>`). If the routes change, or a
nightly renames the `ipp-pre` and `ipp` filters, the bypass silently does
nothing.
