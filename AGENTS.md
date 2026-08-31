# AGENTS.md — Instructions for AI Agents

This template implements the **Dependabot → PR with CI Gate → Rebase & Merge → Auto Release** flow. Apply it to a new repository in the following order. All paths are relative to the target repo root unless noted as `actions/` (this template repo).

## 0. Prerequisites

- Target repo has `main` as default branch (rename `next` → `main` if needed: `git push origin next:main --force && gh api PATCH default_branch=main && git branch -D next && git push --delete origin next`).
- `gh` CLI authenticated (`gh auth status`), `git` configured.
- Stack detection: check for `go.mod`, `frontend/package.json`, `justfile`, `wails.json`.

## 1. Copy Templates

```bash
# From actions/ template repo
cp actions/templates/ci.yml .github/workflows/ci.yml
cp actions/templates/release.yml .github/workflows/release.yml
cp actions/templates/dependabot.yml .github/dependabot.yml

# Ensure dirs exist
mkdir -p .github/workflows
```

## 2. Customize Placeholders

Search for `TODO` or `BINARY_NAME` in the copied files:

| Placeholder | Replace With | Example |
|-------------|-------------|---------|
| `BINARY_NAME` | Repo name / `wails.json:name` | `your-app` |
| `cooldown` in `dependabot.yml` | Desired min-age (default `14` = 14d) | Keep or adjust |
| `libgtk-3-dev libwebkit2gtk-4.1-dev` | Your system deps | Keep for Wails, remove for pure Go |
| `just check` | Your `justfile` check recipe | `just check` or `go vet ./...` |

Also:
- In `frontend/package.json`, ensure side-by-side TS is set if using Vue:
  ```json
  "typescript": "npm:@typescript/typescript6@6.0.2",
  "@typescript/native": "npm:typescript@7.0.2",
  "overrides": { "typescript": "npm:@typescript/typescript6@6.0.2" }
  ```
- In `dependabot.yml`, verify `schedule` (`weekly` `day: monday` `time: "02:00"`), `cooldown: 14`, and `ignore: typescript >=7.0.0` for TS hold.

## 3. Validate YAML

```bash
python3 -c "import yaml, pathlib; [yaml.safe_load(open(f)) for f in ['.github/workflows/ci.yml', '.github/workflows/release.yml', '.github/dependabot.yml']]; print('yaml valid')"
python3 -m json.tool frontend/package.json > /dev/null && echo "json valid"
```

## 4. Setup Branch Protection

```bash
# Requires admin on repo
./scripts/setup-branch-protection.sh Delnegend/<repo>
# This sets:
# - required_status_checks: strict, 4 contexts [Check (just check), Build (linux/amd64), Build (darwin/universal), Build (windows/amd64)]
# - required_linear_history: true
# - allow_rebase_merge: true, allow_squash_merge: false, allow_merge_commit: false
```

Manual alternative via `gh api`:
```bash
gh api repos/Delnegend/<repo>/branches/main/protection -X PUT --input <(cat <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["Check (just check)", "Build (linux/amd64)", "Build (darwin/universal)", "Build (windows/amd64)"]},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
)
gh api repos/Delnegend/<repo> -X PATCH -f allow_rebase_merge=true -f allow_squash_merge=false -f allow_merge_commit=false
```

## 5. Commit & Push

```bash
git add .github/workflows/ci.yml .github/workflows/release.yml .github/dependabot.yml frontend/package.json
git commit -m "ci: add dependabot→PR→CI→release flow from actions template

- dependabot 14d cooldown grouped PR (gomod + npm) on schedule weekly Mon 02:00
- CI gates merge (rebase only)
- TS6 hold for vue-tsc until TS7.1"
git push
```

## 6. Verify

- Open a test PR: `gh pr create --title "test: ci" --body "verify"` → check 4 checks appear → merge button blocked until green.
- Force a breaking change (e.g., set `typescript: 7.0.2` without alias) → PR should go red, merge blocked.
- Merge a green PR → Release should trigger patch bump.

## 7. Notes for AI

- Dependabot replaces `weekly-update.yml`/`renovate.json` — no custom updater, `ci.yml` full-matrix is single gate. Dependabot `cooldown: 14` + `schedule: weekly` + `groups: all-dependencies` gives 1 PR per ecosystem (2 PRs/week, pure YAGNI).
- No repo-level `frontend/bunfig.toml` (deleted for pure YAGNI) — Dependabot `cooldown` is single source; `frontend/package.json:overrides` `typescript` stays as stdlib safety net.
- Weekly cadence = full matrix is acceptable (not daily).
- Keep TS hold until `vuejs/language-tools#6124` closed and TS 7.1 API stable (`dependabot.yml: ignore: typescript >=7.0.0` + `frontend/package.json: overrides`).
- Document all `BINARY_NAME` replacements; don't hardcode example names.

## References

- Flow docs: `docs/FLOW.md`
- Templates: `templates/ci.yml:1`, `templates/dependabot.yml:1`, `templates/release.yml:1`
