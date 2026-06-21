#!/bin/bash
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║              OpenCode Container              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "[*] OpenCode version: $(opencode --version 2>&1 | head -1)" >&2

# ===============================================
# Determine target UID/GID
# ===============================================

TARGET_UID=1000
TARGET_GID=1000

# Override UID/GID from environment variables if set.
[ -n "${PUID:-}" ] && TARGET_UID="${PUID}"
[ -n "${PGID:-}" ] && TARGET_GID="${PGID}"

# Auto-detect UID/GID from /workspace ownership if it mounts from host and PUID/
# PGID are not set.
if [ -d "/workspace" ] && [ -z "${PUID:-}" ] && [ -z "${PGID:-}" ]; then
    root_dev="$(stat -c '%D' /)"
    workspace_dev="$(stat -c '%D' /workspace)"
    if [ "$root_dev" != "$workspace_dev" ]; then
        TARGET_UID=$(stat -c '%u' /workspace 2>/dev/null || echo 1000)
        TARGET_GID=$(stat -c '%g' /workspace 2>/dev/null || echo 1000)
    fi
fi

# Validate UID/GID values
if ! [[ "$TARGET_UID" =~ ^[0-9]+$ ]] ||
    ! [[ "$TARGET_GID" =~ ^[0-9]+$ ]] ||
    [ "$TARGET_UID" -lt 0 ] ||
    [ "$TARGET_GID" -lt 0 ]; then
    echo "[X] Invalid UID:GID: ${TARGET_UID}:${TARGET_GID}" >&2
    exit 1
fi

if [ "$TARGET_UID" -eq 0 ] || [ "$TARGET_GID" -eq 0 ]; then
    echo "[X] Refusing to run as root." >&2
    echo "    For safety reasons, please set PUID/PGID to non-zero values." >&2
    exit 1
fi

echo "[*] Running as UID:GID: ${TARGET_UID}:${TARGET_GID}" >&2

# ===============================================
# Adjust opencode user's UID/GID
# ===============================================

CURRENT_UID=$(id -u opencode)
CURRENT_GID=$(getent group opencode | cut -d: -f3)

if [ "${CURRENT_UID}" != "${TARGET_UID}" ]; then
    echo "[*] Adjusting opencode user UID: ${CURRENT_UID} -> ${TARGET_UID}" >&2
    usermod -u "${TARGET_UID}" opencode
fi
if [ "${CURRENT_GID}" != "${TARGET_GID}" ]; then
    echo "[*] Adjusting opencode group GID: ${CURRENT_GID} -> ${TARGET_GID}" >&2
    groupmod -g "${TARGET_GID}" opencode
    usermod -g "${TARGET_GID}" opencode
fi

# ===============================================
# Fix ownership of home directory and workspace
# ===============================================
echo "[*] Fixing ownership of home directory and workspace" >&2
chown -R "${TARGET_UID}:${TARGET_GID}" /home/opencode 2>/dev/null || true
chown "${TARGET_UID}:${TARGET_GID}" /workspace 2>/dev/null || true

# Create symlink to workspace in home directory
ln -sf /workspace "/home/opencode/workspace" 2>/dev/null || true

# ===============================================
# Execute command as opencode user
# ===============================================
echo "[*] Executing command: $*" >&2
exec gosu opencode "$@"
