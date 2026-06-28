# AGENTS.md — opencode-container

Docker packaging for **OpenCode** and **OpenChamber** via a single multi-stage `Dockerfile` at root (shared `base` → `opencode`, `openchamber`).

## Layout

| Path | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build; base → opencode, openchamber stages |
| `entrypoint.sh` | Single entrypoint for both opencode and openchamber, driven by `APP` env var |
| `.github/workflows/build.yml` | Push-to-master CI: distinguishes Renovate (build affected image on version bump) vs non-Renovate (granular stage detection: entrypoint/base → both, single stage → single image, rev builds). `workflow_dispatch` supports per-image boolean inputs |
| `.github/workflows/update-checksums.yml` | Renovate PR CI: recompute SHA-256, sync OPENCODE_VERSION to latest, auto-commit |
| `.github/release.yml` | GitHub Release notes template — auto-generates sections by PR label (breaking, enhancement, bug, dependency, etc.) |
| `.github/scripts/update-checksums.sh` | Fetches npm tarballs, computes SHA-256, updates Dockerfile ARGs |
| `renovate.json` | Two standalone regex `customManagers` for version bump PRs |
| `.dockerignore` | Excludes .git, .github, docs, AGENTS.md, README.md, LICENSE, renovate.json, .cspell.json |
| `docs/` | Contains `README.zh-CN.md` (Chinese localization) |

`README.md` contains user-facing deployment docs + compose examples. `docs/README.zh-CN.md` is the Chinese localization. `AGENTS.md` is for agent-level build/CI guidance.

## Build commands

```bash
# opencode
docker build --target opencode -t opencode:latest .

# openchamber
docker build --target openchamber -t openchamber:latest .

# Cross-platform (base image digest is an OCI index for amd64 + arm64)
docker buildx build --platform linux/amd64,linux/arm64 --target opencode -t opencode:latest .
docker buildx build --platform linux/amd64,linux/arm64 --target openchamber -t openchamber:latest .
```

Published images: `ghcr.io/jks15satoshi/opencode` and `ghcr.io/jks15satoshi/openchamber` (both amd64 + arm64).

Build args for version pinning:

| Stage | ARG | Scope |
|-------|-----|-------|
| Global | `OPENCODE_VERSION` / `OPENCODE_SHA256` | Defined after `base` stage, inherited by `opencode` and `openchamber` via `ARG` (no `=`) |
| `openchamber` | `OPENCHAMBER_VERSION` / `OPENCHAMBER_SHA256` | Stage-specific |

The global `OPENCODE_VERSION` / `OPENCODE_SHA256` are placed **after** the `base` stage to avoid cache invalidation of the base stage when only the opencode-ai version changes.

**Base stage** (`node:26-trixie-slim` pinned by SHA256): extensive dev tooling (build-essential, cmake, libssl-dev, git, curl, jq, python3, ripgrep, gosu, etc.), npm-global LSPs (bash-language-server, yaml-language-server, dockerfile-language-server-nodejs, prettier), and [mise](https://mise.en.dev) for language runtime management.

Both stages install via npm tarball with `sha256sum` verification, then `npm cache clean --force`. The openchamber stage additionally installs `@openchamber/web`. The base stage removes the default `node` user and creates a unified `opencode` user (UID 1000) shared by both images.

Both stages use a single `entrypoint.sh` at repo root, driven by `APP` env var set in each Dockerfile stage. The entrypoint handles privilege-drop logic, credential staging from `/secrets/`, and runs `mise install` (no-op without user config). The base stage creates `/secrets/ssh/` directory.

### Credential staging

The entrypoint implements a two-phase credential pipeline:

1. **Stage secrets** (before chown): copies files from `/secrets/ssh/` → `~/.ssh/` and `/secrets/git-credentials` → `~/.git-credentials` with correct permissions (`chmod` only, no `chown`).
2. **Fix ownership** (after staging): a single `chown -R "$APP_HOME"` covers all staged files plus pre-existing content.

If `/secrets` directory does not exist, falls back to legacy behavior (direct `~/.ssh/` and `~/.git-credentials` bind mounts, chmod in-place).

**Section order matters**: staging MUST precede the global `chown -R`; reversing would leave staged files owned by root.

## Version management (Renovate)

`renovate.json` uses two standalone regex `customManagers` targeting `Dockerfile`:
- **opencode-ai**: single dep `opencode-ai` → global `ARG OPENCODE_VERSION=`
- **@openchamber/web**: single dep `@openchamber/web` → stage `ARG OPENCHAMBER_VERSION=`

Each creates an independent PR with `platformAutomerge: true`.

### Update flow

1. Renovate opens PR bumping a version ARG → `update-checksums.yml` triggers (only when `github.actor == 'renovate[bot]'`)
2. `update-checksums.sh` fetches the npm tarball for the bumped version, updates its SHA256, then **always** syncs `OPENCODE_VERSION` to npm latest (unconditional, after both package checks)
3. Auto-commits via `stefanzweifel/git-auto-commit-action` → PR auto-merges
4. `build.yml` on push to master: detects Renovate commit → builds only the image whose version ARG changed (regular build). Non-Renovate commit → granular stage detection triggers rev builds for affected images only

### Build types (regular vs rev)

- **Regular builds**: triggered by Renovate version bumps — `{target}/v{ver}` git tag + `{target}:{ver}` Docker tag.
- **Revision builds**: triggered by non-Renovate commits that modify `Dockerfile` stages or `entrypoint.sh` without changing version ARGs (base tag `{target}/v{ver}` already exists):

- Increments the rev counter: `{target}/v{ver}-rev.1`, `-rev.2`, … (highest existing rev + 1, or 1 if none)
- Docker tag format: `{target}:{ver}-rev.{N}` (also pushes `latest`)
- `workflow_dispatch` also follows rev logic when version is unchanged

## CI pipelines

- **`build.yml`**: Runs on push to `master` (and `workflow_dispatch`). The `detect` job: (1) parses version ARGs from Dockerfile with `awk -F= '/^ARG OPENCODE_VERSION=/{print $2}'`, (2) identifies whether the commit is from Renovate (`head_commit.author.username` / `committer.username`), (3) for Renovate: diffs which version ARG changed → regular build of only that image, (4) for non-Renovate: checks `entrypoint.sh` changes, then parses `git diff` hunks against Dockerfile stage boundaries (`FROM base AS opencode` / `FROM base AS openchamber`) to determine which stages were touched → rev build of affected images. `workflow_dispatch` honors per-image boolean inputs (`build_opencode` / `build_openchamber`). Builds with `docker buildx` for `linux/amd64,linux/arm64`, pushes to `ghcr.io`. Creates `opencode/v{ver}` / `openchamber/v{ver}` (or `-rev.{N}`) git tag + GitHub Release. **The `detect` job parses version ARGs and stage boundaries from the Dockerfile — changing the ARG format/position or stage naming will break CI.**
- **`update-checksums.yml`**: Runs on `pull_request` (`opened` / `synchronize`) only when `github.actor == 'renovate[bot]'`. Force-pushes to Renovate PRs re-trigger it. Commits with `stefanzweifel/git-auto-commit-action` (user `opencode-checksum-bot`).

## Runtime security model

Builds as **root**, drops privileges via `gosu` at runtime:

1. **Priority**: `PUID`/`PGID` env vars > auto-detect from `/workspace` mount owner > default `1000:1000`
2. **Auto-detection**: compares device IDs of `/` vs `/workspace` via `stat -c '%D'` — differing devices means a bind mount exists, so it reads the mount owner. Without a bind mount, falls through to defaults.
3. **Root refusal**: exits if UID or GID == 0
4. **Validation**: non-negative integer check; non-numeric values rejected
5. **Permission patching**: after determining the target UID/GID, the entrypoint runs `usermod`/`groupmod` to rebind the container user, stages secrets from `/secrets/` (if present), then runs a single `chown -R` to fix ownership of the home directory (covering staged files, legacy mounts, and pre-existing content). Also fixes `/workspace` and `/mise` ownership, recreates the `workspace` symlink, and runs `mise install` — all before `exec gosu`

## Per-image auth quirks

- **opencode**: Auth via `OPENCODE_SERVER_PASSWORD` (HTTP basic auth; default username `opencode`, override with `OPENCODE_SERVER_USERNAME`).
- **openchamber**: Auth via `OPENCHAMBER_UI_PASSWORD`. By default starts its own internal OpenCode instance; to use an external one set `OPENCODE_SKIP_START=true` + `OPENCODE_HOST=<url>`. `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` disables auth (LAN only).

## Constraints

- No test suite, no typecheck, no linter — only build verification
- The entrypoint refuses to run as root
- `npm cache clean --force` runs after each install in the build stage
- The `Dockerfile` comment `# renovate: datasource=npm depName=...` must precede the version ARG for Renovate regex matching to work
- Global `OPENCODE_VERSION` / `OPENCODE_SHA256` ARGs are placed after the `base` stage to preserve base stage layer cache
- In `entrypoint.sh`, the "Stage secrets" section must execute before "Fix ownership" — swapping them breaks ownership of staged files
- SSH keys should be mounted at `/secrets/ssh/` (not directly to `~/.ssh/`) to avoid read-only filesystem permission failures

