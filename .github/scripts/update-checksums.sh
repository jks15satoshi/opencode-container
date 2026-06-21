#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# update-checksums.sh
#
# Updates SHA256 checksums in the multi-stage Dockerfile after
# Renovate bumps the corresponding version ARGs.
#
# Handles the global OPENCODE_VERSION/SHA256 and the
# openchamber stage OPENCHAMBER_VERSION/SHA256.
#
# When OPENCHAMBER_VERSION changes, also syncs the global
# OPENCODE_VERSION to the latest opencode-ai release.
#
# Usage:
#   .github/scripts/update-checksums.sh [path/to/Dockerfile]
#
# Default: Dockerfile
# ============================================================

DOCKERFILE="${1:-Dockerfile}"

if [ ! -f "$DOCKERFILE" ]; then
    echo "Error: $DOCKERFILE not found"
    exit 1
fi

updated=false

# replace_arg_in_dockerfile <var_name> <new_value>
# Replaces ALL ARG lines matching the given name in the Dockerfile.
replace_arg_in_dockerfile() {
    local var_name="$1"
    local new_value="$2"

    if [ -z "$new_value" ]; then
        echo "  ERROR: Refusing to replace ${var_name} with empty value"
        return 1
    fi

    awk -v name="$var_name" -v value="$new_value" '
        $1 == "ARG" && $2 ~ "^" name "=" {
        print "ARG " name "=" value
        next
        }
        { print }
    ' "$DOCKERFILE" >"${DOCKERFILE}.tmp" && mv "${DOCKERFILE}.tmp" "$DOCKERFILE"
}

# --------------------------------------------------
# opencode-ai (global ARG)
# --------------------------------------------------
echo "=== opencode-ai ==="

current_version=$(sed -n 's/^ARG OPENCODE_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
if [ -z "$current_version" ]; then
    echo "  WARNING: OPENCODE_VERSION not found, skipping"
else
    echo "  Version: $current_version"

    tarball_url="https://registry.npmjs.org/opencode-ai/-/opencode-ai-${current_version}.tgz"
    echo "  Fetching: $tarball_url"

    new_sha256=$(curl -fsSL "$tarball_url" 2>/dev/null | sha256sum | awk '{print $1}') || {
        echo "  ERROR: Failed to fetch tarball for opencode-ai v${current_version}"
        exit 1
    }

    if [ -z "$new_sha256" ]; then
        echo "  ERROR: Empty checksum for opencode-ai"
        exit 1
    fi

    echo "  New SHA256: $new_sha256"

    current_sha256=$(sed -n 's/^ARG OPENCODE_SHA256=\(.*\)/\1/p' "$DOCKERFILE")
    if [ "$new_sha256" != "$current_sha256" ]; then
        replace_arg_in_dockerfile "OPENCODE_SHA256" "$new_sha256"
        echo "  ✅ Updated OPENCODE_SHA256"
        updated=true
    else
        echo "  No change (already up-to-date)"
    fi
fi

echo ""

# --------------------------------------------------
# @openchamber/web
# --------------------------------------------------
echo "=== @openchamber/web ==="

current_version=$(sed -n 's/^ARG OPENCHAMBER_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
if [ -z "$current_version" ]; then
    echo "  WARNING: OPENCHAMBER_VERSION not found, skipping"
else
    echo "  Version: $current_version"

    tarball_url="https://registry.npmjs.org/@openchamber/web/-/web-${current_version}.tgz"
    echo "  Fetching: $tarball_url"

    new_sha256=$(curl -fsSL "$tarball_url" 2>/dev/null | sha256sum | awk '{print $1}') || {
        echo "  ERROR: Failed to fetch tarball for @openchamber/web v${current_version}"
        exit 1
    }

    if [ -z "$new_sha256" ]; then
        echo "  ERROR: Empty checksum for @openchamber/web"
        exit 1
    fi

    echo "  New SHA256: $new_sha256"

    current_sha256=$(sed -n 's/^ARG OPENCHAMBER_SHA256=\(.*\)/\1/p' "$DOCKERFILE")
    if [ "$new_sha256" != "$current_sha256" ]; then
        replace_arg_in_dockerfile "OPENCHAMBER_SHA256" "$new_sha256"
        echo "  ✅ Updated OPENCHAMBER_SHA256"
        updated=true
    else
        echo "  No change (already up-to-date)"
    fi
fi

echo ""

# --------------------------------------------------
# Sync OPENCODE_VERSION to npm latest
# --------------------------------------------------
echo "=== sync OPENCODE_VERSION to latest ==="

latest_opencode=$(curl -fsS "https://registry.npmjs.org/opencode-ai/latest" 2>/dev/null | jq -r '.version' 2>/dev/null) || {
    echo "  WARNING: Failed to query latest opencode-ai version, skipping sync"
}
if [ -n "$latest_opencode" ] && [ "$latest_opencode" != "null" ]; then
    current_opencode=$(sed -n 's/^ARG OPENCODE_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
    if [ "$latest_opencode" != "$current_opencode" ]; then
        echo "  Syncing OPENCODE_VERSION: $current_opencode -> $latest_opencode"

        replace_arg_in_dockerfile "OPENCODE_VERSION" "$latest_opencode"

        tarball_url="https://registry.npmjs.org/opencode-ai/-/opencode-ai-${latest_opencode}.tgz"
        echo "  Fetching: $tarball_url"

        new_sha256=$(curl -fsSL "$tarball_url" 2>/dev/null | sha256sum | awk '{print $1}') || {
            echo "  ERROR: Failed to fetch tarball for opencode-ai v${latest_opencode}"
            exit 1
        }

        if [ -z "$new_sha256" ]; then
            echo "  ERROR: Empty checksum for opencode-ai v${latest_opencode}"
            exit 1
        fi

        echo "  New SHA256: $new_sha256"
        replace_arg_in_dockerfile "OPENCODE_SHA256" "$new_sha256"
        echo "  ✅ Synced OPENCODE_VERSION and OPENCODE_SHA256"
        updated=true
    else
        echo "  OPENCODE_VERSION already at latest ($current_opencode)"
    fi
else
    echo "  WARNING: Could not determine latest opencode-ai version, skipping sync"
fi

echo ""

# --------------------------------------------------
# Summary
# --------------------------------------------------
if [ "$updated" = true ]; then
    echo "✅ Checksum(s) updated. Please verify with 'git diff $DOCKERFILE'."
else
    echo "All checksums are up-to-date."
fi
