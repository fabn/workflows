# fabn/workflows

Reusable GitHub Actions workflows and composite actions I use across my projects:
generic Docker builds for `ghcr.io`, Kubernetes deployments on DigitalOcean via
`doctl`, and deployment markers for New Relic and Rollbar.

Pin to the major tag (`@v1`) in production, or `@main` if you like living
dangerously.

## Reusable workflows

### `docker-build.yml`

Builds and pushes a Docker image to `ghcr.io/<owner>/<repo>` with sensible tags
(branch+sha, tag, `latest` on default branch) and GHA layer caching. Passes
several build args automatically (`APP_REVISION`, `APP_DIST`, `BRANCH`, `SHA`,
`DD_GIT_*`) and `DD_API_KEY` if you set the secret.

| Input | Required | Description |
|---|---|---|
| `image` | no | Override image name (defaults to `ghcr.io/<repo>`). |
| `build_args` | no | Extra build args appended to the defaults. |
| `ref` | no | Ref to check out and build. |

| Output | Description |
|---|---|
| `image` | Fully qualified image name with tag. |
| `base` | Image base name (no tag). |
| `tag` | Computed tag/version. |

Secrets: `DD_API_KEY` is read implicitly via `secrets: inherit`. Omit if you
don't use Datadog.

```yaml
jobs:
  build:
    uses: fabn/workflows/.github/workflows/docker-build.yml@v1
    secrets: inherit
```

### `deploy-restart.yml`

`kubectl rollout restart` on a DigitalOcean Kubernetes deployment, waits for
rollout completion. Concurrency-grouped per `deployment`+`namespace`.

| Input | Required | Description |
|---|---|---|
| `cluster` | yes | DO Kubernetes cluster name. |
| `namespace` | yes | Kubernetes namespace. |
| `deployment` | no | Deployment name. |
| `environment_name` | no | GitHub environment to associate the job with. |
| `environment_url` | no | URL displayed on the environment. |

| Secret | Required | Description |
|---|---|---|
| `token` | yes | DigitalOcean API token. |

```yaml
jobs:
  restart:
    uses: fabn/workflows/.github/workflows/deploy-restart.yml@v1
    with:
      cluster: my-cluster
      namespace: production
      deployment: api
    secrets:
      token: ${{ secrets.DIGITALOCEAN_TOKEN }}
```

### `deploy-set-image.yml`

`kubectl set image` on a DigitalOcean Kubernetes deployment with rollout wait.
Use after `docker-build.yml` to roll a new image into a deployment.

| Input | Required | Description |
|---|---|---|
| `cluster` | yes | DO Kubernetes cluster name. |
| `namespace` | yes | Kubernetes namespace. |
| `deployment` | yes | Deployment name. |
| `pod_name` | no | Container name inside the pod (defaults to `deployment`). |
| `image` | yes | Image (with tag) to set. |
| `environment_name` | no | GitHub environment. |
| `environment_url` | no | URL displayed on the environment. |

| Secret | Required | Description |
|---|---|---|
| `token` | yes | DigitalOcean API token. |

```yaml
jobs:
  deploy:
    uses: fabn/workflows/.github/workflows/deploy-set-image.yml@v1
    with:
      cluster: my-cluster
      namespace: production
      deployment: api
      image: ghcr.io/me/my-app:v1.2.3
    secrets:
      token: ${{ secrets.DIGITALOCEAN_TOKEN }}
```

### `newrelic.yml`

Creates a New Relic deployment marker via `newrelic/deployment-marker-action`.
Reads revision from the tag name (on tag) or the commit SHA.

| Input | Required | Description |
|---|---|---|
| `application_id` | yes | New Relic application ID. |

| Secret | Required | Description |
|---|---|---|
| `api_key` | yes | New Relic API key. |
| `account_id` | yes | New Relic account ID. |

### `rollbar.yml`

Notifies Rollbar of a deployment via `rollbar/github-deploy-action`. Supports
2-phase deploys: call it once with `status: started` (default `succeeded`),
capture `deploy_id`, then again later.

| Input | Required | Default | Description |
|---|---|---|---|
| `environment` | no | `staging` | Rollbar environment name. |
| `status` | no | `succeeded` | Deployment status. |
| `deploy_id` | no | — | Deploy id for 2-phase flow. |

| Secret | Required | Description |
|---|---|---|
| `access_token` | yes | Rollbar access token. |

| Output | Description |
|---|---|
| `deploy_id` | Returned deployment id. |

## Composite actions

### `actions/doctl`

Installs `doctl` and saves kubeconfig for a DigitalOcean Kubernetes cluster as
`live-cluster` (or a custom alias). Use inside your own jobs when you need
authenticated `kubectl` access.

```yaml
- uses: fabn/workflows/actions/doctl@v1
  with:
    cluster: my-cluster
    token: ${{ secrets.DIGITALOCEAN_TOKEN }}
```

## License

MIT — see [LICENSE](./LICENSE).
