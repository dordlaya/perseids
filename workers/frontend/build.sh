#!/usr/bin/env bash
# build.sh — Build the Flutter web frontend for Cloudflare Workers deployment.
#
# Called by the Cloudflare Workers CI/CD pipeline before `wrangler deploy`.
# Also usable locally to test a production build:
#
#   BACKEND_URL=https://your-backend.onrender.com bash workers/frontend/build.sh
#
# Required env vars:
#   BACKEND_URL   Full origin of the Go backend, e.g. https://perseid.onrender.com
#                 Set this in the Cloudflare Workers dashboard → Settings → Variables.
#
# Optional env vars:
#   FLUTTER_HOME  Path to Flutter SDK (default: ~/.flutter)
#   REBUILD       Set to "true" to force a rebuild even if build/web already exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FRONTEND_DIR="$REPO_ROOT/frontend"

FLUTTER_HOME="${FLUTTER_HOME:-$HOME/.flutter}"
FLUTTER="$FLUTTER_HOME/bin/flutter"

# ── Validate ──────────────────────────────────────────────────────────────────
if [ -z "${BACKEND_URL:-}" ]; then
  echo "ERROR: BACKEND_URL is not set."
  echo "  Set it in the Cloudflare dashboard → Workers → perseids → Settings → Variables"
  echo "  Example: BACKEND_URL=https://your-backend.onrender.com"
  exit 1
fi

# Strip trailing slash so --dart-define value is clean.
BACKEND_URL="${BACKEND_URL%/}"

# ── Install Flutter if missing ────────────────────────────────────────────────
if [ ! -x "$FLUTTER" ]; then
  echo "==> Flutter not found at $FLUTTER_HOME. Installing..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  "$FLUTTER" config --no-analytics
  "$FLUTTER" precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
  echo "==> Flutter installed."
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

# ── Build ─────────────────────────────────────────────────────────────────────
FORCE_REBUILD="${REBUILD:-false}"
if [ "$FORCE_REBUILD" = "true" ] || [ ! -f "$FRONTEND_DIR/build/web/index.html" ]; then
  echo "==> Building Flutter web (BACKEND_URL=$BACKEND_URL)..."
  cd "$FRONTEND_DIR"
  "$FLUTTER" pub get
  "$FLUTTER" build web --release \
    --dart-define=BACKEND_URL="$BACKEND_URL"
  echo "==> Flutter web build complete → $FRONTEND_DIR/build/web"
else
  echo "==> Flutter web already built. Set REBUILD=true to force a rebuild."
fi

