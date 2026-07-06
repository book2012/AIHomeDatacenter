#!/bin/bash
set -euo pipefail

PROJECT="/opt/aihomedatacenter"
MESSAGE="${1:-}"

cd "$PROJECT"

echo "AI Home Datacenter Git Sync"
echo "==========================="
echo ""

echo "[1/4] Current branch"
git branch --show-current
echo ""

echo "[2/4] Git status"
git status --short
echo ""

if [ -z "$(git status --short)" ]; then
  echo "Nothing to commit. Working tree clean."
  exit 0
fi

if [ -z "$MESSAGE" ]; then
  MESSAGE="Update AI Home Datacenter $(date +%F_%H-%M)"
fi

echo "[3/4] Commit"
echo "Message: $MESSAGE"

git add .
git commit -m "$MESSAGE"

echo ""
echo "[4/4] Push"
git push origin main

echo ""
echo "Git sync completed."
