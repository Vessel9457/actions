#!/usr/bin/env bash
set -euo pipefail
# Apply actions templates to a target repo
# Usage: ./scripts/apply-templates.sh /path/to/target-repo

TARGET="${1:-}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 /path/to/target-repo"
  exit 1
fi
if [[ ! -d "$TARGET/.git" ]]; then
  echo "Target $TARGET is not a git repo"
  exit 1
fi

echo "Applying templates from $TEMPLATE_DIR to $TARGET"

mkdir -p "$TARGET/.github/workflows"

for f in ci.yml weekly-update.yml release.yml; do
  if [[ -f "$TARGET/.github/workflows/$f" ]]; then
    echo "Skipping $f — already exists (merge manually)"
  else
    cp "$TEMPLATE_DIR/$f" "$TARGET/.github/workflows/$f"
    echo "Copied $f"
  fi
done

echo "Done. Next: customize BINARY_NAME in ci.yml/release.yml and run setup-branch-protection.sh"
