#!/usr/bin/env bash
set -euo pipefail

# Setup branch protection for weekly→PR→CI→release flow
# Usage: ./scripts/setup-branch-protection.sh Delnegend/repo [--dry-run]
# Requires: gh cli authenticated with admin on repo

REPO="${1:-}"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <owner/repo> [--dry-run]"
  echo "Example: $0 Delnegend/gallery-preprocessor"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

echo "Setting up branch protection for $REPO (main) — 4 required checks, linear history, rebase only..."

# 1. Branch protection
PROTECTION_JSON=$(cat <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Check (just check)", "Build (linux/amd64)", "Build (darwin/universal)", "Build (windows/amd64)"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "allow_auto_merge": false
}
JSON
)

if $DRY_RUN; then
  echo "[dry-run] Would PUT /repos/$REPO/branches/main/protection with:"
  echo "$PROTECTION_JSON" | python3 -m json.tool
else
  echo "$PROTECTION_JSON" | gh api "repos/$REPO/branches/main/protection" -X PUT --input - > /tmp/protection.out 2>&1
  cat /tmp/protection.out | python3 -m json.tool | head -n 40
  echo "Branch protection set."
fi

# 2. Merge methods
if $DRY_RUN; then
  echo "[dry-run] Would PATCH /repos/$REPO with allow_rebase_merge=true, squash/merge false"
else
  gh api "repos/$REPO" -X PATCH -f allow_rebase_merge=true -f allow_squash_merge=false -f allow_merge_commit=false > /tmp/merge.out 2>&1
  cat /tmp/merge.out | python3 -m json.tool | grep -E "allow_(rebase|squash|merge)" | head -n 10
  echo "Merge methods set to rebase only."
fi

# 3. Verify
if ! $DRY_RUN; then
  echo "Verifying..."
  gh api "repos/$REPO/branches/main/protection" --jq '{required_status_checks, required_linear_history}' 2>&1 | python3 -m json.tool
  gh api "repos/$REPO" --jq '{allow_rebase_merge, allow_squash_merge, allow_merge_commit}' 2>&1 | python3 -m json.tool
fi

echo "Done. PRs to main now require 4 checks and linear history; only Rebase and merge is allowed."
