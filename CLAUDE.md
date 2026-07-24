# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A library of **reusable GitHub Actions workflows** (`workflow_call`) and one composite action, consumed by other repos via `uses: fabn/workflows/...@v1`. There is no application code to build or test — the `Dockerfile` is a dummy `echo-server` image used only as a build target when exercising `docker-build.yml`.

## Linting / CI

The only CI in this repo is `.github/workflows/actionlint.yml`, which runs `reviewdog/action-actionlint` on push/PR to `main` when any `.github/workflows/**` file changes. To reproduce locally:

```bash
actionlint .github/workflows/*.yml
```

## Architecture

Two consumer-facing surfaces, both intended to be referenced from external repos:

1. **Reusable workflows** in `.github/workflows/` — all use `on: workflow_call` and are designed to be called from other repos' workflows:
   - `docker-build.yml` — builds and pushes to `ghcr.io/<owner>/<repo>`. Tagging logic in `docker/metadata-action` step emits four tag types (tag-ref, branch+sha, sha for PRs, `latest` on default branch). Always injects build args `APP_REVISION`, `APP_DIST`, `BRANCH`, `SHA`, `DD_GIT_*`. Outputs `image`, `base`, `tag` for downstream jobs (typically `deploy-set-image.yml`).
   - `docker-build-multi.yml` — multi-arch variant of `docker-build.yml` (standalone, does not call it). One native build per platform from the `runners` input (default amd64 on `ubuntu-latest` + arm64 on `ubuntu-24.04-arm`, no QEMU), each pushed **by digest only**; digests travel to the `merge` job as artifacts, where `docker buildx imagetools create` assembles the manifest list and applies the same `metadata-action` tag scheme as `docker-build.yml`. Registry is parametric (`registry`, `registry_username`, `registry_password` secret; defaults to ghcr.io + `GITHUB_TOKEN`). Keep the tagging block and the injected build args in sync with `docker-build.yml`. With `push: false` the merge job is skipped (push-by-digest requires a push), so the smoke test only validates the per-platform builds.
   - `eks-terraform-apply.yml` — applies a Terraform root against an **AWS EKS** cluster via GitHub OIDC + an in-cluster kubernetes state backend (assume role → `update-kubeconfig` → ensure state namespace → `init` + `apply`/`plan`; installs SOPS when `SOPS_AGE_KEY` is present). Convention over configuration: resolves role/region/cluster/tf-version from org/repo variables (`DEPLOY_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER`, `TERRAFORM_VERSION`) and the Terraform root / state namespace by convention (`infra/<environment>`, `<repo>-terraform`), so a caller usually passes only `environment` + `image_tag`. **Gotcha:** `secrets: inherit` only passes secrets within the **same organization/enterprise** — this repo is the personal `fabn` account while its consumers are the `fabn-business` org, so `inherit` is a silent no-op there; `SOPS_AGE_KEY` (and any secret) must be mapped **by name** in the caller's `secrets:` block. (This affects `docker-build-multi.yml`'s `DD_API_KEY: secrets: inherit` too — it doesn't reach `fabn-business` builds. Separately: environment-level secrets are never inherited and take precedence over passed secrets.) Belongs to the AWS/EKS world, unrelated to the DO/`doctl` deploy workflows below.
   - `deploy-restart.yml` / `deploy-set-image.yml` — both `kubectl` on DO Kubernetes, both follow the same pattern: install `doctl` via the local composite action, perform the operation, wait on rollout. They differ only in the kubectl verb.
   - `newrelic.yml`, `rollbar.yml` — deployment markers. `rollbar.yml` supports a 2-phase flow (call with `status: started`, capture `deploy_id` output, call again with that id and a terminal status).

2. **Composite action** `actions/doctl/action.yml` — installs `doctl` and runs `doctl kubernetes cluster kubeconfig save` so subsequent `kubectl` steps in the same job are authenticated. The two deploy workflows depend on this.

### Internal cross-reference

`deploy-restart.yml` and `deploy-set-image.yml` reference the composite action as `uses: fabn/workflows/actions/doctl@v1`. The `v1` tag is a **floating major tag** maintained by `.github/workflows/release.yml`: on every published release (e.g. `v1.0.2`), the `release.yml` job force-moves `v1` to that commit. So a consumer pinning `@v1` gets a workflow file whose internal `actions/doctl@v1` reference resolves to the same commit — self-consistent, no manual sync. If you ever introduce `v2`, update the internal refs in the deploy workflows in the same PR that triggers the `v2.0.0` release.

### Versioning contract

Consumers are documented to pin to the major tag (`@v1`); `v1` and `v1.0.0` are already published. When making changes, preserve backwards compatibility on the consumer surface (input names, secret names, output names, default values). Inputs are usually optional with sensible defaults — keep them that way. Cutting a new major requires moving the `v1` tag (or introducing `v2`).

## Documentation convention (target)

Per-workflow docs currently live inline in `README.md`. As the set grows the
intended shape is: a **`docs/` folder with one file per workflow** holding the
full reference (inputs/secrets/outputs, conventions, examples), and the
`README.md` reduced to a **short blurb + a quick example + a link** to each doc.
Not yet migrated — when adding or substantially editing a workflow's docs, prefer
creating its `docs/<workflow>.md` rather than growing the README section.

## User preferences for this repo

- No conventional commit prefixes (`feat:`, `fix:`, etc.) in commit messages or PR titles — plain English.
- When creating branches from `origin/main`, use `--no-track` and push with explicit remote ref.
