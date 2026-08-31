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

for f in ci.yml release.yml dependabot-auto-merge.yml; do
  if [[ -f "$TARGET/.github/workflows/$f" ]]; then
    echo "Skipping $f — already exists (merge manually)"
  else
    cp "$TEMPLATE_DIR/$f" "$TARGET/.github/workflows/$f"
    echo "Copied $f"
  fi
done

if [[ -f "$TEMPLATE_DIR/dependabot.yml" ]]; then
  if [[ -f "$TARGET/.github/dependabot.yml" ]]; then
    echo "Skipping dependabot.yml — already exists (merge manually)"
  else
    cp "$TEMPLATE_DIR/dependabot.yml" "$TARGET/.github/dependabot.yml"
    echo "Copied dependabot.yml (weekly, 14d cooldown, grouped)"
  fi
fi

echo "Done. Next: customize BINARY_NAME in ci.yml/release.yml and run setup-branch-protection.sh"
