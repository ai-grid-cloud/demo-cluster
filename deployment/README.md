# Deployment values for demo1

The values `ai-grid-cloud/ai-grid-tenant` (branch `cloud-provider`) reads for
our clusters: hub `local-cluster` (demo1, no OpenShift AI), spokes `site-a`
(combined) and `site-b` (inference). The layout is the template's
`deployment/README.md`; bootstrap with:

```sh
DEPLOYMENT_REPO_URL=https://github.com/ai-grid-cloud/demo-deployment.git \
DEPLOYMENT_PATH=deployment \
CATALOG_REPO_URL=https://github.com/ai-grid-cloud/demo-cluster.git \
./bootstrap.sh
```

This directory moves to `ai-grid-cloud/demo-deployment`, a private repository
the provider console's git-writer token can't write (decision D4, accepted
2026-10-27; Chris creates the repository). `catalog/` stays here in
`demo-cluster`: the console's git writer commits models and subscriptions
there.

## Not finished: placeholders

This repository is public, so it carries no real hostnames. Three values are
placeholders until that's decided:

- `grid-enrollment.yaml`: the hub's enrollment Route host.
- `clusters/site-a/rhoai.yaml`: site-b's router hostname, and the local
  provider's name, which embeds a hash of the model's UID and is known only
  after the model exists.
- No Keycloak yet: its overlay (realm, hostnames) comes with the identity port.

## Don't use this directory from this repository

Argo CD applies these values with cluster-admin rights: the template's root
ApplicationSet turns any `apps/*.yaml` here into an Application in project
`default`, and applies `hub/` to the hub. The git writer's token can push to
this repository, so anyone holding it would be cluster-admin on the hub and
every spoke. Chris accepted a narrower risk on 2026-10-26 (realm and broker
config here); this is broader, and it breaks the 2026-10-23 rule "nothing
privileged in a repo the git-writer token can write".

So this directory is a draft of the layout only. Before any cluster reads it,
it moves to a repository the token can't write (decision D4 in the
convergence plan). `cluster-admins.yaml` grants no one, either way.
