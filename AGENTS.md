# AGENTS.md — opencode-container

Docker packaging for **OpenCode** and **OpenChamber** via a single multi-stage `Dockerfile` at root (shared `base` → `opencode`, `openchamber`).

## Layout

| Path | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build; base → opencode, openchamber stages |
| `opencode/entrypoint.sh` | opencode container entrypoint |
| `openchamber/entrypoint.sh` | openchamber container entrypoint |
| `.github/workflows/build.yml` | Push-to-master CI: checks if `opencode/v{ver}` / `openchamber/v{ver}` tag exists (builds only when absent), builds multi-arch images, creates tags + GitHub Releases |
| `.github/workflows/update-checksums.yml` | Renovate PR CI: recompute SHA-256, sync OPENCODE_VERSION to latest, auto-commit |
| `.github/release.yml` | GitHub Release notes template — auto-generates sections by PR label (breaking, enhancement, bug, dependency, etc.) |
| `.github/scripts/update-checksums.sh` | Fetches npm tarballs, computes SHA-256, updates Dockerfile ARGs |
| `renovate.json` | Two standalone regex `customManagers` for version bump PRs |
| `.dockerignore` | Excludes .git, .github, docs, AGENTS.md, README.md, LICENSE, renovate.json, .cspell.json |
| `docs/` | Empty — no generated or manual docs |

`README.md` is empty; `AGENTS.md` is the sole documentation.

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

Build args for version pinning:

| Stage | ARG | Scope |
|-------|-----|-------|
| Global | `OPENCODE_VERSION` / `OPENCODE_SHA256` | Defined after `base` stage, inherited by `opencode` and `openchamber` via `ARG` (no `=`) |
| `openchamber` | `OPENCHAMBER_VERSION` / `OPENCHAMBER_SHA256` | Stage-specific |

The global `OPENCODE_VERSION` / `OPENCODE_SHA256` are placed **after** the `base` stage to avoid cache invalidation of the base stage when only the opencode-ai version changes.

**Base stage** (`node:26-trixie-slim` pinned by SHA256): installs ca-certificates, curl, dnsutils, git, gosu, jq, python3, ripgrep, unzip, wget, zip.

Both stages install via npm tarball with `sha256sum` verification, then `npm cache clean --force`. The openchamber stage additionally installs `@openchamber/web`. Each removes the default `node` user and creates a dedicated user (UID 1000).

Both entrypoint scripts (`opencode/entrypoint.sh`, `openchamber/entrypoint.sh`) share identical privilege-drop logic.

## Version management (Renovate)

`renovate.json` uses two standalone regex `customManagers` targeting `Dockerfile`:
- **opencode-ai**: single dep `opencode-ai` → global `ARG OPENCODE_VERSION=`
- **@openchamber/web**: single dep `@openchamber/web` → stage `ARG OPENCHAMBER_VERSION=`

Each creates an independent PR with `platformAutomerge: true`.

### Update flow

1. Renovate opens PR bumping a version ARG → `update-checksums.yml` triggers (only when `github.actor == 'renovate[bot]'`)
2. `update-checksums.sh` fetches the npm tarball for the bumped version, updates its SHA256, and syncs `OPENCODE_VERSION` to npm latest if `OPENCHAMBER_VERSION` was bumped
3. Auto-commits via `stefanzweifel/git-auto-commit-action` → PR auto-merges
4. `build.yml` on push to master parses version ARGs from Dockerfile, checks `opencode/v{ver}` / `openchamber/v{ver}` tags exist (skips if present), builds missing targets multi-arch, pushes to ghcr.io, creates git tag + GitHub Release

## CI pipelines

- **`build.yml`**: Runs on push to `master` (and `workflow_dispatch`). Builds a target only when its corresponding `opencode/v{ver}` / `openchamber/v{ver}` git tag does not yet exist (no version-diff required). Builds with `docker buildx` for `linux/amd64,linux/arm64`, pushes to `ghcr.io`. Creates `opencode/v{ver}` or `openchamber/v{ver}` tag + GitHub Release with notes auto-generated via `.github/release.yml` plus an `Upstream Release` section linking to upstream project releases.
- **`update-checksums.yml`**: Runs only when `github.actor == 'renovate[bot]'`.

## Runtime security model

Builds as **root**, drops privileges via `gosu` at runtime:

1. **Priority**: `PUID`/`PGID` env vars > auto-detect from `/workspace` mount owner > default `1000:1000`
2. **Root refusal**: exits if UID or GID == 0
3. **Validation**: non-negative integer check; non-numeric values rejected
4. **Permission patching**: after determining the target UID/GID, the entrypoint runs `usermod`/`groupmod` to rebind the container user, then `chown` to fix ownership of the home directory and `/workspace`, and recreates the `workspace` symlink inside the home directory — all before `exec gosu`

## opencode image

- **Default CMD**: `opencode serve --hostname 0.0.0.0 --port 4096 --print-logs`
- **Auth**: `OPENCODE_SERVER_PASSWORD` → HTTP basic auth (username `opencode`, overridable via `OPENCODE_SERVER_USERNAME`)
- **EXPOSE 4096**, **VOLUME** `/home/opencode/.config/opencode` and `/home/opencode/.local/share/opencode`
- **Base**: `node:26-trixie-slim` pinned by SHA256 digest

## openchamber image

- **Default CMD**: `openchamber serve --foreground --port 3000 --host 0.0.0.0`
- **Internal OpenCode**: starts/manages an internal OpenCode server by default; set `OPENCODE_HOST` + `OPENCODE_SKIP_START=true` to connect to external OpenCode
- **Auth**: `OPENCHAMBER_UI_PASSWORD` env var for browser UI
- **EXPOSE 3000**, **VOLUME** `/home/openchamber/.config/openchamber`
- **Base**: same `node:26-trixie-slim` as opencode

## Constraints

- No test suite, no typecheck, no linter — only build verification
- Both entrypoints refuse to run as root
- `npm cache clean --force` runs after each install in the build stage
- The `Dockerfile` comment `# renovate: datasource=npm depName=...` must precede the version ARG for Renovate regex matching to work
- Global `OPENCODE_VERSION` / `OPENCODE_SHA256` ARGs are placed after the `base` stage to preserve base stage layer cache

