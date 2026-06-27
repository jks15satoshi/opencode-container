#!/bin/bash
set -euo pipefail

APP="${APP:-}"

# Validate APP
if [ "${APP}" != "opencode" ] && [ "${APP}" != "openchamber" ]; then
    echo "[X] APP must be 'opencode' or 'openchamber', got: ${APP:-<empty>}" >&2
    exit 1
fi

SYSTEM_USER="${SYSTEM_USER:-opencode}"

print_header() {
    local user="$1"
    local title

    case "${user}" in
    opencode) title="OpenCode" ;;
    openchamber) title="OpenChamber" ;;
    esac

    local label="${title} Container"
    local pad=$(((44 - ${#label}) / 2))
    local extra=$(((44 - ${#label}) % 2))

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    printf "║ %*s%s%*s ║\n" "$pad" "" "$label" "$((pad + extra))" ""
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "[*] ${title} version: $(${user} --version 2>&1 | head -1)" >&2
}

print_header "${APP}"

# ===============================================
# Determine target UID/GID
# ===============================================

TARGET_UID=1000
TARGET_GID=1000

[ -n "${PUID:-}" ] && TARGET_UID="${PUID}"
[ -n "${PGID:-}" ] && TARGET_GID="${PGID}"

if [ -d "/workspace" ] && [ -z "${PUID:-}" ] && [ -z "${PGID:-}" ]; then
    root_dev="$(stat -c '%D' /)"
    workspace_dev="$(stat -c '%D' /workspace)"
    if [ "$root_dev" != "$workspace_dev" ]; then
        TARGET_UID=$(stat -c '%u' /workspace 2>/dev/null || echo 1000)
        TARGET_GID=$(stat -c '%g' /workspace 2>/dev/null || echo 1000)
    fi
fi

if ! [[ "$TARGET_UID" =~ ^[0-9]+$ ]] ||
    ! [[ "$TARGET_GID" =~ ^[0-9]+$ ]] ||
    [ "$TARGET_UID" -lt 0 ] ||
    [ "$TARGET_GID" -lt 0 ]; then
    echo "[X] Invalid UID:GID: ${TARGET_UID}:${TARGET_GID}" >&2
    exit 1
fi

if [ "$TARGET_UID" -eq 0 ] || [ "$TARGET_GID" -eq 0 ]; then
    echo "[X] Refusing to run as root." >&2
    exit 1
fi

echo "[*] Running as UID:GID: ${TARGET_UID}:${TARGET_GID}" >&2

# ===============================================
# Adjust user UID/GID
# ===============================================

CURRENT_UID=$(id -u "$SYSTEM_USER")
CURRENT_GID=$(getent group "$SYSTEM_USER" | cut -d: -f3)

if [ "${CURRENT_UID}" != "${TARGET_UID}" ]; then
    echo "[*] Adjusting ${SYSTEM_USER} UID: ${CURRENT_UID} -> ${TARGET_UID}" >&2
    usermod -u "${TARGET_UID}" "$SYSTEM_USER"
fi
if [ "${CURRENT_GID}" != "${TARGET_GID}" ]; then
    echo "[*] Adjusting ${SYSTEM_USER} GID: ${CURRENT_GID} -> ${TARGET_GID}" >&2
    groupmod -g "${TARGET_GID}" "$SYSTEM_USER"
    usermod -g "${TARGET_GID}" "$SYSTEM_USER"
fi

# ===============================================
# Fix ownership of home directory and workspace
# ===============================================

APP_HOME="/home/${SYSTEM_USER}"
echo "[*] Fixing ownership of home directory and workspace" >&2
chown -R "${TARGET_UID}:${TARGET_GID}" "$APP_HOME" 2>/dev/null || true
chown "${TARGET_UID}:${TARGET_GID}" /workspace 2>/dev/null || true
chown "${TARGET_UID}:${TARGET_GID}" /mise 2>/dev/null || true

ln -sfn /workspace "${APP_HOME}/workspace" 2>/dev/null || true

# ===============================================
# Install devtools via Mise (if available)
# ===============================================

echo "[*] Checking mise tools..." >&2
gosu "$SYSTEM_USER" mise trust / 2>&1 || true
gosu "$SYSTEM_USER" mise install || echo "[!] mise install encountered errors (check config or network)" >&2

# ===============================================
# Execute command as user
# ===============================================

echo "[*] Executing command: $*" >&2
exec gosu "$SYSTEM_USER" "$@"
