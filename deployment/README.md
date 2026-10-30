# Deployment values for demo1

The values `ai-grid-cloud/ai-grid-tenant-demo` (branch `cloud-provider`) reads for
our demo clusters: hub `local-cluster` (demo1, unlabelled: no OpenShift AI),
spokes `site-a` (`ai-grid/role=ingress`) and `site-b` (`inference`). The layout
is the template's `deployment/README.md`. Bootstrap with:

```sh
DEPLOYMENT_REPO_URL=https://github.com/ai-grid-cloud/demo-cluster.git \
DEPLOYMENT_PATH=deployment \
CATALOG_REPO_URL=https://github.com/ai-grid-cloud/demo-cluster.git \
CATALOG_REVISION=main \
CATALOG_IN_DEPLOYMENT_REPO=yes \
./bootstrap.sh
```

`catalog/` sits next to this directory: the provider console's git writer
commits models and subscriptions there.

## Accepted risk: this repository is cluster-admin

Argo CD applies these values with cluster-admin rights: the template's root
ApplicationSet turns any `apps/*.yaml` here into an Application in project
`default`. The console's git-writer token can push to this repository, so
whoever holds it is cluster-admin on the hub and every spoke. The values also
name the clusters' real hostnames, publicly.

Chris accepted both for these demo clusters only (decision D4, 2026-10-27):
they're throwaway clusters we can rebuild. It replaces the 2026-10-23 rule
"nothing privileged in a repo the git-writer token can write" for them alone.
Any other deployment, including ai-grid-1's, keeps its catalog in a separate
repository, and `bootstrap.sh` refuses the same repository without
`CATALOG_IN_DEPLOYMENT_REPO=yes`.

## Open

- site-a's grid consumer reaches only site-b, since no model is placed on
  site-a. Placing one there needs site-a combined, a provider gateway file and
  a local backend.
