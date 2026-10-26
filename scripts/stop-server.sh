#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

echo "Stopping Our Chat Server Stack..."

if [ -f .server.pid ]; then
    PID="$(cat .server.pid)"
    echo "  -> Stopping NestJS server (PID ${PID})..."
    kill "${PID}" 2>/dev/null || true
    rm -f .server.pid
fi
lsof -ti :3001 | xargs kill -9 2>/dev/null || true

if [ -f .cloudflared.pid ]; then
    PID="$(cat .cloudflared.pid)"
    echo "  -> Stopping Cloudflare Tunnel (PID ${PID})..."
    kill "${PID}" 2>/dev/null || true
    rm -f .cloudflared.pid
fi
pkill -f "cloudflared tunnel.*--metrics 127.0.0.1:2000" 2>/dev/null || true

echo "✓ Our Chat local services stopped."
