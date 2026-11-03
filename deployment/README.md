# Deployment values for the demo clusters

This directory is the deployment repository for `demo1` (hub) and its sites `site-a` (ingress) and `site-b`
(inference). It follows the layout of the template's `examples/deployment/`
([ai-grid-cluster-gitops](https://github.com/ai-grid-cloud/ai-grid-cluster-gitops)). The template is read unchanged;
everything specific to these clusters is here.

Bootstrap the hub from the template with:

```sh
BOOTSTRAP_PROFILE=dedicated-hub \
DEPLOYMENT_REPO_URL=https://github.com/ai-grid-cloud/demo-cluster.git \
DEPLOYMENT_REVISION=main \
DEPLOYMENT_PATH=deployment \
RHOAI_QUAY_PULL_SECRET=... \
./bootstrap.sh
```

| Path | What it does here |
|---|---|
| `apps/catalog.yaml`, `catalog/` | Delivers this repository's `../catalog/` (models, subscriptions) through the template's catalog ApplicationSets, with the catalog URL replaced. |
| `apps/console.yaml` | The provider console on the dedicated hub; its git writer commits to this repository's `catalog/`. |
| `apps/gpu.yaml`, `gpu/` | NFD and the NVIDIA GPU operator on inference sites (`site-b` has one `g6.xlarge`). |
| `apps/keycloak-settings.yaml`, `keycloak-settings/` | Keycloak imports realms without replacing them, so organizations the console creates survive a restart. |
| `cluster-admins.yaml` | Nobody gets cluster-admin from git. Only read where cluster-config runs (not on the dedicated hub). |

Anyone who can push here controls what the hub deploys, including the console's git writer token. That is
accepted for these throwaway demo clusters only.
