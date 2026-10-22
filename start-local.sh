#!/usr/bin/env bash
# start-local.sh — Build and run the Perseids backend + Flutter web frontend locally.
#
# Usage:
#   ./start-local.sh              # start with defaults
#   ADMIN_TOKEN=secret ./start-local.sh   # enable /api/reset
#
# The server will listen on http://127.0.0.1:5173
# Flutter will be installed to ~/.flutter if not already present.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/.flutter}"
FLUTTER="$FLUTTER_HOME/bin/flutter"
WEB_BUILD_DIR="$FRONTEND_DIR/build/web"

# ── Config (override via env vars) ──────────────────────────────────────────
export PORT="${PORT:-5173}"
export BIND="${BIND:-127.0.0.1}"
export STORE_BACKEND="${STORE_BACKEND:-json}"
export DATA_DIR="${DATA_DIR:-$BACKEND_DIR/data}"
export STATIC_DIR="${STATIC_DIR:-$WEB_BUILD_DIR}"
export HEARTBEAT_TIMEOUT="${HEARTBEAT_TIMEOUT:-60m}"
# export ADMIN_TOKEN="your-secret-token"   # uncomment to enable /api/reset
# export VALKEY_URL="redis://localhost:6379"  # only needed if STORE_BACKEND=valkey

# ── Step 1: Install Flutter if missing ──────────────────────────────────────
if [ ! -x "$FLUTTER" ]; then
  echo "==> Flutter not found. Installing to $FLUTTER_HOME..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  "$FLUTTER" config --no-analytics
  "$FLUTTER" precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
  echo "==> Flutter installed."
else
  echo "==> Flutter found at $FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

# ── Step 2: Build Flutter web if not already built ──────────────────────────
FORCE_REBUILD="${REBUILD:-false}"
if [ "$FORCE_REBUILD" = "true" ] || [ ! -f "$WEB_BUILD_DIR/index.html" ]; then
  echo "==> Building Flutter web frontend..."
  cd "$FRONTEND_DIR"
  "$FLUTTER" pub get
  "$FLUTTER" build web --release
  echo "==> Flutter web build complete."
else
  echo "==> Flutter web already built (run with REBUILD=true or delete $WEB_BUILD_DIR to force rebuild)."
fi

# ── Step 3: Build Go backend ─────────────────────────────────────────────────
echo "==> Building backend..."
cd "$BACKEND_DIR"
go build -o server .

# ── Step 4: Start the server ─────────────────────────────────────────────────
echo ""
echo "==> Starting Perseids"
echo "    URL:           http://${BIND}:${PORT}"
echo "    Store backend: ${STORE_BACKEND}"
echo "    Data dir:      ${DATA_DIR}"
echo "    Static dir:    ${STATIC_DIR}"
if [ -n "${ADMIN_TOKEN:-}" ]; then
  echo "    Admin reset:   (enabled) POST /api/reset with Bearer \$ADMIN_TOKEN"
else
  echo "    Admin reset:   (disabled — set ADMIN_TOKEN env var to enable)"
fi
echo ""

exec "$BACKEND_DIR/server"
