#!/usr/bin/env bash
# Redeploy godmode.orion-jones.com (Cloudflare Pages project "godmode", direct upload): the download page,
# the Mac installer zip (build it first with installer/build.sh), and the worker that serves install.sh
# live from GitHub main.
set -euo pipefail
cd "$(dirname "$0")"
[ -f GPS-Spoofer-Installer.zip ] || { echo "run installer/build.sh first" >&2; exit 1; }
out="$(mktemp -d)"
cp _worker.js index.html GPS-Spoofer-Installer.zip "$out/"
cp ../install.sh "$out/install.sh"  # fallback copy
npx -y wrangler@4 pages deploy "$out" --project-name godmode --branch main --commit-dirty=true
rm -rf "$out"
