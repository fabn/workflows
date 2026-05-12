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
   - `docker-build.yml` — builds and pushes to `ghcr.io/<owner>/<repo>`. Tagging logic in `docker/metadata-action` step emits four tag types (tag-ref, branch+sha, sha for PRs, `latest` on default branch). Always injects build args `APP_REVISION`, `APP_DIST`, `BRANCH`, `SHA`, `DD_GIT_*`, plus `DD_API_KEY` if the calling repo provides it via `secrets: inherit`. Outputs `image`, `base`, `tag` for downstream jobs (typically `deploy-set-image.yml`).
   - `deploy-restart.yml` / `deploy-set-image.yml` — both `kubectl` on DO Kubernetes, both follow the same pattern: install `doctl` via the local composite action, perform the operation, wait on rollout. They differ only in the kubectl verb.
   - `newrelic.yml`, `rollbar.yml` — deployment markers. `rollbar.yml` supports a 2-phase flow (call with `status: started`, capture `deploy_id` output, call again with that id and a terminal status).

2. **Composite action** `actions/doctl/action.yml` — installs `doctl` and runs `doctl kubernetes cluster kubeconfig save` so subsequent `kubectl` steps in the same job are authenticated. The two deploy workflows depend on this.

### Internal cross-reference (important)

`deploy-restart.yml` and `deploy-set-image.yml` both reference the composite action as `uses: fabn/workflows/actions/doctl@main` — **pinned to `@main`, not to the same ref the caller used**. The `v1` / `v1.0.0` tags already exist and point at this `@main` reference, so a consumer pinning `@v1` still picks up `actions/doctl@main` at runtime. When editing the composite action, treat `main` as the published surface for consumers of every workflow tag — there is no per-tag isolation. If you want a future release to be self-contained, change those `@main` references to the matching tag (and remember to update them again on the next release).

### Versioning contract

Consumers are documented to pin to the major tag (`@v1`); `v1` and `v1.0.0` are already published. When making changes, preserve backwards compatibility on the consumer surface (input names, secret names, output names, default values). Inputs are usually optional with sensible defaults — keep them that way. Cutting a new major requires moving the `v1` tag (or introducing `v2`).

## User preferences for this repo

- No conventional commit prefixes (`feat:`, `fix:`, etc.) in commit messages or PR titles — plain English.
- When creating branches from `origin/main`, use `--no-track` and push with explicit remote ref.
