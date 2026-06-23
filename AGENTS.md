# AGENTS.md — opencode-container

Docker packaging for **OpenCode** and **OpenChamber** via a single multi-stage `Dockerfile` at root (shared `base` → `opencode`, `openchamber`).

## Layout

| Path | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build; base → opencode, openchamber stages |
| `entrypoint.sh` | Single entrypoint for both opencode and openchamber, driven by `APP_USER` env var |
| `.github/workflows/build.yml` | Push-to-master CI: builds when version tag is absent, or when `Dockerfile`/`entrypoint.sh` change without version bump (creating `-rev.{N}` tags). Builds multi-arch images, creates tags + GitHub Releases |
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

**Base stage** (`node:26-trixie-slim` pinned by SHA256): installs ca-certificates, curl, dnsutils, git, gosu, jq, python3, ripgrep, unzip, wget, zip, build-essential, cmake, libssl-dev, openssh-client, pkg-config, procps, less, htop, tree. Also installs npm-based LSPs (bash-language-server, yaml-language-server, vscode-json-languageserver, dockerfile-language-server-nodejs, pyright, prettier) and [mise](https://mise.en.dev) for language runtime management.

Both stages install via npm tarball with `sha256sum` verification, then `npm cache clean --force`. The openchamber stage additionally installs `@openchamber/web`. Each removes the default `node` user and creates a dedicated user (UID 1000).

Both stages use a single `entrypoint.sh` at repo root, driven by `APP_USER` env var set in each Dockerfile stage. The entrypoint handles privilege-drop logic and runs `mise install` (no-op without user config).

## Version management (Renovate)

`renovate.json` uses two standalone regex `customManagers` targeting `Dockerfile`:
- **opencode-ai**: single dep `opencode-ai` → global `ARG OPENCODE_VERSION=`
- **@openchamber/web**: single dep `@openchamber/web` → stage `ARG OPENCHAMBER_VERSION=`

Each creates an independent PR with `platformAutomerge: true`.

### Update flow

1. Renovate opens PR bumping a version ARG → `update-checksums.yml` triggers (only when `github.actor == 'renovate[bot]'`)
2. `update-checksums.sh` fetches the npm tarball for the bumped version, updates its SHA256, and syncs `OPENCODE_VERSION` to npm latest if `OPENCHAMBER_VERSION` was bumped
3. Auto-commits via `stefanzweifel/git-auto-commit-action` → PR auto-merges
4. `build.yml` on push to master parses version ARGs from Dockerfile, checks `opencode/v{ver}` / `openchamber/v{ver}` tags exist (skips if present with no file changes), builds missing targets multi-arch, pushes to ghcr.io, creates git tag + GitHub Release

### Rev builds

When `Dockerfile` or `entrypoint.sh` change but version ARGs stay the same (base tag `{target}/v{ver}` already exists), the `build.yml` detect job creates a **revision build**:

- Increments the rev counter: `{target}/v{ver}-rev.1`, `-rev.2`, … (highest existing rev + 1, or 1 if none)
- Docker tag format: `{target}:{ver}-rev.{N}` (also pushes `latest`)
- `workflow_dispatch` also follows rev logic when version is unchanged

## CI pipelines

- **`build.yml`**: Runs on push to `master` (and `workflow_dispatch`). The `detect` job: (1) parses version ARGs from Dockerfile, (2) checks if `Dockerfile`/`entrypoint.sh` changed via `git diff` against `github.event.before`/`after`, (3) for each target: base tag absent → regular build; base tag present + files changed → rev build (`{target}/v{ver}-rev.{N}`); otherwise skips. Builds with `docker buildx` for `linux/amd64,linux/arm64`, pushes to `ghcr.io`. Creates `opencode/v{ver}` / `openchamber/v{ver}` (or `-rev.{N}`) tag + GitHub Release with notes auto-generated via `.github/release.yml`. **The `detect` job parses version ARGs from the Dockerfile with `sed` — changing the ARG format/position will break CI.**
- **`update-checksums.yml`**: Runs only when `github.actor == 'renovate[bot]'`.

## Runtime security model

Builds as **root**, drops privileges via `gosu` at runtime:

1. **Priority**: `PUID`/`PGID` env vars > auto-detect from `/workspace` mount owner > default `1000:1000`
2. **Root refusal**: exits if UID or GID == 0
3. **Validation**: non-negative integer check; non-numeric values rejected
4. **Permission patching**: after determining the target UID/GID, the entrypoint runs `usermod`/`groupmod` to rebind the container user, then `chown` to fix ownership of the home directory and `/workspace`, recreates the `workspace` symlink inside the home directory, and runs `mise install` (no-op without user config) — all before `exec gosu`

## opencode image

- **Default CMD**: `opencode serve --hostname 0.0.0.0 --port 4096 --print-logs`
- **Auth**: `OPENCODE_SERVER_PASSWORD` → HTTP basic auth (username `opencode`, overridable via `OPENCODE_SERVER_USERNAME`)
- **EXPOSE 4096**, **VOLUME** `/home/opencode/.config/opencode`, `/home/opencode/.local/share/opencode`, and `/mise`
- **Base**: `node:26-trixie-slim` pinned by SHA256 digest

## openchamber image

- **Default CMD**: `openchamber serve --foreground --port 3000 --host 0.0.0.0`
- **Internal OpenCode**: starts/manages an internal OpenCode server by default; set `OPENCODE_HOST` + `OPENCODE_SKIP_START=true` to connect to external OpenCode
- **Auth**: `OPENCHAMBER_UI_PASSWORD` env var for browser UI; `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` disables auth (LAN only)
- **EXPOSE 3000**, **VOLUME** `/home/openchamber/.config/openchamber` and `/mise`
- **Base**: same `node:26-trixie-slim` as opencode

## Constraints

- No test suite, no typecheck, no linter — only build verification
- The entrypoint refuses to run as root
- `npm cache clean --force` runs after each install in the build stage
- The `Dockerfile` comment `# renovate: datasource=npm depName=...` must precede the version ARG for Renovate regex matching to work
- Global `OPENCODE_VERSION` / `OPENCODE_SHA256` ARGs are placed after the `base` stage to preserve base stage layer cache

