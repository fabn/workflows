# fabn/workflows

Reusable GitHub Actions workflows and composite actions I use across my projects:
generic Docker builds for `ghcr.io`, Kubernetes deployments on DigitalOcean via
`doctl` and on AWS EKS via Terraform + OIDC, and deployment markers for New
Relic and Rollbar.

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

### `docker-build-multi.yml`

Multi-arch variant of `docker-build.yml`. Builds the image natively on one
runner per platform — no QEMU emulation — pushing each build by digest only,
then merges the digests into a single multi-arch manifest list carrying the
same tags `docker-build.yml` would emit. Defaults to `linux/amd64` on
`ubuntu-latest` plus `linux/arm64` on `ubuntu-24.04-arm` (GitHub's ARM runner,
free for public repositories; private repositories should override `runners`,
see the example below). Same automatic build args as
`docker-build.yml`.

| Input | Required | Description |
|---|---|---|
| `image_name` | no | Base image name without tag (defaults to `<registry>/<owner>/<repo>`). |
| `build_args` | no | Extra build args appended to the defaults. |
| `context` | no | Build context path (defaults to `.`). |
| `dockerfile` | no | Dockerfile path, repo-root relative (defaults to `<context>/Dockerfile`). |
| `push` | no | Set to `false` to build without pushing (skips the merge job). |
| `ref` | no | Ref to check out and build. |
| `registry` | no | Target registry (defaults to `ghcr.io`). |
| `registry_username` | no | Registry login username (defaults to the repository owner). |
| `runners` | no | JSON array of `{platform, runner}` pairs, one native build each. |

| Secret | Required | Description |
|---|---|---|
| `registry_password` | no | Registry login password/token. Defaults to `GITHUB_TOKEN`, which is all `ghcr.io` needs. |
| `DD_API_KEY` | no | Forwarded as a build arg, as in `docker-build.yml`. |

| Output | Description |
|---|---|
| `image` | Fully qualified multi-arch image name with tag. |
| `base` | Image base name (no tag). |
| `tag` | Computed tag/version. |

```yaml
jobs:
  build:
    uses: fabn/workflows/.github/workflows/docker-build-multi.yml@v1
    secrets: inherit
```

**Calling from a private repository.** GitHub's `ubuntu-24.04-arm` runner is
only available (free) on public repositories: on a private one the arm64 job
would sit queued forever waiting for a runner that never picks it up. Pass
`runners` explicitly and point the arm64 entry at a runner your repository
actually has. Each `runner` value goes straight into the job's `runs-on`, so
it can be a single label — e.g. the name of a paid ARM
[larger runner](https://docs.github.com/en/actions/using-github-hosted-runners/using-larger-runners)
configured in your organization settings — or an array of labels for a
self-hosted runner:

```yaml
jobs:
  build:
    uses: fabn/workflows/.github/workflows/docker-build-multi.yml@v1
    with:
      # amd64 on the standard hosted runner, arm64 on a self-hosted runner
      # registered with the "self-hosted", "linux" and "ARM64" labels.
      # For a paid ARM larger runner use its name instead, e.g.
      # {"platform": "linux/arm64", "runner": "my-org-arm64-runner"}
      runners: >-
        [{"platform": "linux/amd64", "runner": "ubuntu-latest"},
         {"platform": "linux/arm64", "runner": ["self-hosted", "linux", "ARM64"]}]
    secrets: inherit
```

To push somewhere other than `ghcr.io`, point `registry` (and usually
`image_name`) at it and pass credentials — any registry that accepts a static
username/password or token login works:

```yaml
jobs:
  build:
    uses: fabn/workflows/.github/workflows/docker-build-multi.yml@v1
    with:
      registry: quay.io
      registry_username: myorg+ci
      image_name: quay.io/myorg/myapp
    secrets:
      registry_password: ${{ secrets.QUAY_TOKEN }}
```

### `eks-terraform-apply.yml`

Applies a Terraform root against an **AWS EKS** cluster using **GitHub OIDC**
(no long-lived AWS credentials) and an in-cluster kubernetes state backend.
Assumes a role, writes a kubeconfig, ensures the state namespace, then
`terraform init` + `apply` (or a read-only `plan`). SOPS is installed when a
`SOPS_AGE_KEY` secret is visible, so a root that decrypts secrets during the
apply works out of the box.

Convention over configuration: a caller usually passes only `environment` and
`image_tag`; everything else resolves from organization/repository variables or
from the repository name. Resolution is **input → variable → convention**:

| Value | Input | Variable | Convention |
|---|---|---|---|
| Deploy role ARN | `aws_role_arn` | `vars.DEPLOY_ROLE_ARN` | — |
| AWS region | `aws_region` | `vars.AWS_REGION` | — |
| EKS cluster | `cluster_name` | `vars.EKS_CLUSTER` | — |
| Terraform version | `terraform_version` | `vars.TERRAFORM_VERSION` | `latest` |
| Terraform root | `working_directory` | — | `infra/<environment>` |
| State namespace | `state_namespace` | — | `<repo>-terraform` |

| Input | Required | Description |
|---|---|---|
| `environment` | yes | Logical env (e.g. `staging`). Drives `infra/<environment>` and serializes applies per repo+env. Not the GitHub Environment. |
| `image_tag` | no | Exposed to Terraform as `TF_VAR_image_tag` (defaults to `latest`). |
| `apply` | no | `false` runs a read-only `terraform plan`. |
| `aws_role_arn`, `aws_region`, `cluster_name`, `terraform_version` | no | Override the variables above. |
| `working_directory`, `state_namespace` | no | Override the conventions above (`-` on `state_namespace` skips creation). |
| `environment_name` | no | GitHub Environment for the deployments tab, environment-scoped vars/secrets, and the OIDC sub claim. |
| `environment_url` | no | URL shown on the GitHub Environment. |

Map `SOPS_AGE_KEY` through explicitly (see the examples), by name — **not**
`secrets: inherit`. `inherit` only passes secrets when the caller and the
reusable are in the **same organization or enterprise**; this repo is consumable
from other accounts, where `inherit` is a silent no-op. The caller workflow must
grant `permissions: { id-token: write, contents: read }`, and the assumed role's
trust policy must permit the caller's OIDC subject (the branch ref, or
`environment:<name>` when `environment_name` is set).

Set these once so callers can stay minimal:

- **Organization variables:** `AWS_REGION`, `EKS_CLUSTER`, `TERRAFORM_VERSION`.
- **Repository variable:** `DEPLOY_ROLE_ARN` (each repo's own OIDC role).
- **Organization (or repository) secret:** `SOPS_AGE_KEY`.

Minimal caller — conventions do the rest (`infra/staging` root,
`<repo>-terraform` state namespace, role/region/cluster/version from variables):

```yaml
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    uses: fabn/workflows/.github/workflows/eks-terraform-apply.yml@v1
    secrets:
      SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
    with:
      environment: staging
      image_tag: ${{ needs.build.outputs.tag }}
```

Overriding when a repo doesn't follow the conventions (a different root path, an
explicit GitHub Environment, a one-off region):

```yaml
jobs:
  deploy:
    uses: fabn/workflows/.github/workflows/eks-terraform-apply.yml@v1
    secrets:
      SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
    with:
      environment: staging
      image_tag: ${{ needs.build.outputs.tag }}
      working_directory: infra/staging-eks
      environment_name: my-app-staging
      environment_url: https://staging.example.com
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
