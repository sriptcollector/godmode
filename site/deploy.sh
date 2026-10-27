#!/usr/bin/env bash
# Redeploy godmode.orion-jones.com (Cloudflare Pages project "godmode", direct upload).
# Only needed when site/_worker.js changes: the worker already serves install.sh live from GitHub main.
set -euo pipefail
cd "$(dirname "$0")"
out="$(mktemp -d)"
cp _worker.js "$out/"
cp ../install.sh "$out/install.sh"  # fallback copy
npx -y wrangler@4 pages deploy "$out" --project-name godmode --branch main --commit-dirty=true
rm -rf "$out"
