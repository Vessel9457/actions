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
cp actions/templates/dependabot-auto-merge.yml .github/workflows/dependabot-auto-merge.yml

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
python3 -c "import yaml, pathlib; [yaml.safe_load(open(f)) for f in ['.github/workflows/ci.yml', '.github/workflows/release.yml', '.github/workflows/dependabot-auto-merge.yml', '.github/dependabot.yml']]; print('yaml valid')"
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
git add .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/dependabot-auto-merge.yml .github/dependabot.yml frontend/package.json
git commit -m "ci: add dependabot→PR→CI→release flow from actions template

- dependabot 14d cooldown grouped PR (gomod + npm) on schedule weekly Mon 02:00, assignees Delnegend, auto-merge patch/minor via dependabot-auto-merge.yml
- CI gates merge (rebase only, allow_auto_merge)
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

- Templates: `templates/ci.yml:1`, `templates/dependabot.yml:1`, `templates/release.yml:1`, `templates/dependabot-auto-merge.yml:1`

## Detailed Flow

Detailed behavior of the four workflows and branch protection — canonical spec (previously `docs/FLOW.md:1`, now merged here for single source).

### Overview

```
Dependabot (weekly Mon 02:00, 14d, grouped, assignees: Delnegend)
  │
  ▼
dependabot.yml ──grouped──► PR dependabot/* (label: dependencies, assignees: Delnegend)
                                  │
                                  ▼
                               ci.yml (4 checks, full matrix)
                                 │
                     ┌───────────┴───────────┐
                     │                       │
                  all green               any red or major
                  patch/minor              │
                     │                       ▼
                     ▼                Assigned to you
              Auto-merge                (human fix)
              rebase (dependabot-auto-merge.yml)
                     │
                     ▼
               release.yml
              (patch bump)
                     │
                     ▼
               GitHub Release
               + artifacts
```

### dependabot.yml

**Schedule:** `weekly` `day: monday` `time: "02:00"` (Mon 02:00 UTC), `cooldown: 14d` grouped `all-dependencies` → 1 PR per ecosystem (`gomod` + `npm` frontend), `assignees: [Delnegend]` (always).

**Config** (`dependabot.yml:1` `version: 2`):
- `labels: [dependencies]`, `assignees: [Delnegend]`, `commit-message: prefix: "chore(deps)"`, `groups: all-dependencies: patterns: ["*"]` (single PR per ecosystem, 2 PRs/week, `open-pull-requests-limit: 1`)
- `ignore: typescript >=7.0.0` (TS6 hold, `vuejs/language-tools#6124`, `frontend/package.json:overrides` stays as stdlib safety net)
- `cooldown: default-days: 14` for Go+Bun

**Repo-level:** No `frontend/bunfig.toml` (pure YAGNI, deleted) — Dependabot `cooldown` is single source.

**Flow:** Dependabot creates/updates `PR dependabot/*` (grouped, 14d, always `Delnegend`) → `ci.yml` full-matrix single gate → `dependabot-auto-merge.yml` auto-merge patch/minor or assign on major/red → `release.yml` auto patch on `label: dependencies`.

### dependabot-auto-merge.yml

**Trigger:** `pull_request: branches: [main]` (`actor == dependabot[bot]` + `label: dependencies`) + `workflow_dispatch: pr-number` (manual test).

**Jobs:**
- `automerge`: `dependabot/fetch-metadata@v2` `update-type` → `if: != major` → `gh pr merge --auto --rebase` (patch/minor auto, major held for human).
- `manual-test`: `workflow_dispatch` → `gh pr list --author dependabot[bot]` → `gh pr merge --auto --rebase` (for testing `gh workflow run dependabot-auto-merge.yml`).

Permissions `contents: write`, `pull-requests: write`, `allow_auto_merge: true` (rebase only). Fully autonomous `weekly: PR → CI → merge+release : assign`.

### ci.yml

**Trigger:** `pull_request: branches [main]`, `push: branches [main]`, `workflow_dispatch`.

**Jobs:**

| Job | Runs On | Steps |
|-----|---------|-------|
| `Check (just check)` | `ubuntu-latest` | `setup-go`, `setup-bun`, `apt libgtk-3-dev`, `just check` |
| `Build (linux/amd64)` | `ubuntu-latest` | `setup-go`, `setup-bun`, `apt`, `go install wails`, `wails build -tags webkit2_41` |
| `Build (darwin/universal)` | `macos-latest` | same, `wails build -platform darwin/universal` |
| `Build (windows/amd64)` | `windows-latest` | `choco install nsis`, `wails build -nsis` |

Weekly cadence makes full matrix acceptable (vs daily where single `ubuntu` check would be cheaper). Check names are `Check (just check)` and `Build (linux/amd64)` etc. — these strings are the `required_status_checks.contexts` in branch protection.

### release.yml

**Trigger:** `workflow_dispatch` (manual `release_version` + `create_release`) OR `pull_request: types [closed], branches [main]`.

**Prepare job** only runs if `workflow_dispatch` OR (`pull_request.merged == true` AND `label dependencies`). Computes `version`:
- Manual: use `inputs.release_version`.
- Auto: `git describe --tags --abbrev=0` → `vMAJOR.MINOR.PATCH` → `PATCH+1` (or `0.1.0` if no tags).

**Build job** needs `prepare`, matrix same as `ci.yml`, plus `Compress binaries` (`7z`/`tar.xz`) and `Upload artifact`.

**Release job** needs `prepare+build` and `create_release==true`, generates notes from `git log` since last tag (grouped `feat`/`fix`/… + `Other`) and creates `softprops/action-gh-release` with `vVERSION`.

### Branch Protection

Set on `main`:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Check (just check)", "Build (linux/amd64)", "Build (darwin/universal)", "Build (windows/amd64)"]
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "allow_auto_merge": true
}
```

And repo settings:

```json
{"allow_rebase_merge": true, "allow_squash_merge": false, "allow_merge_commit": false, "allow_auto_merge": true}
```

Effect: PR cannot be merged unless all 4 checks pass and branch is up-to-date; only `Rebase and merge` button is enabled.

### Customization

- Change `BINARY_NAME` in `release.yml:22` and `ci.yml` artifact names.
- Change `cooldown` in `dependabot.yml` (`default-days: 14`) to adjust min-age.
- Replace `just check` with your own `check` recipe or inline `go vet`/`oxlint`.
- For non-Wails projects, remove `libgtk`/`webkit` and `wails` steps, keep `go build`/`bun run build`.

### History

Extracted from a production Wails project after fixing TS7 breakage (vue-tsc requires TS6 until 7.1, side-by-side `typescript: npm:@typescript/typescript6@6.0.2` + `@typescript/native: npm:typescript@7.0.2`, `overrides` hold).
