# Flow — Weekly Update → PR → CI Gate → Release

Detailed behavior of the three workflows and branch protection.

## Overview

```
Weekly (Mon 02:00 UTC)
  │
  ▼
weekly-update.yml ──always──► PR chore/update-deps (label: dependencies)
                                │
                                ▼
                             ci.yml (4 checks, full matrix)
                                │
                    ┌───────────┴───────────┐
                    │                       │
                 all green               any red
                    │                       │
                    ▼                       ▼
             Rebase & Merge            Blocked
                    │               (human fix)
                    ▼
              release.yml
             (patch bump)
                    │
                    ▼
              GitHub Release
              + artifacts
```

## weekly-update.yml

**Trigger:** `schedule: cron '0 2 * * 1'` (Mon 02:00 UTC) + `workflow_dispatch`.

**Env:** `BUN_MIN_RELEASE_AGE=1209600` (14d), `GO_MIN_RELEASE_AGE=1209600` (14d). 2-week min-age prevents bumping to a 3-day-old breaking release (e.g., `typescript@7.0.2` broke `vue-tsc`).

**Repo-level + Action-level dual enforcement:**
- **Bun**: `frontend/bunfig.toml:1` `[install] minimumReleaseAge = 1209600` enforces at repo level for every `bun install`/`bun update`/`bun add` (dev, `ci.yml`, `release.yml`). `weekly-update.yml:1` flag `bun update --latest --minimum-release-age $BUN_MIN_RELEASE_AGE` overrides where needed but now redundant — defense-in-depth so local `bun add` can't bypass 14d CI.
- **Go**: No official repo-level `go.mod` min-age, so only action-level via composite `Delnegend/actions/go-min-age@v1` (hoisted from `weekly-update.yml` bash). Skip Go repo-level.

**Steps:**

1. **Update Go deps** — `uses: Delnegend/actions/go-min-age@v1` with `min-age: 1209600` (composite: `go list -m -u all`, fetch `proxy.golang.org/@v/*.info` `Time`, filter by cutoff, `go get -d` per-module, `go mod tidy`).

2. **Update frontend** — `cd frontend && bun update --latest --minimum-release-age $BUN_MIN_RELEASE_AGE`. Then **verify TS hold**: `grep '"typescript": "npm:@typescript/typescript6'` must pass; if not, `exit 1` (fails updater, but `Draft PR`/`Open PR` use `if: always()` so PR still opens — the hold is enforced via `overrides` anyway).

3. **Check for changes** — `git status --porcelain` → `changed=true`.

   *No local build validation here* — `ci.yml` full-matrix is the single merge gate (removed `Install system dependencies`/`Build frontend`/`Validate Go build`/`Build gate` that previously ran `continue-on-error`).

4. **Draft PR body** — `git diff -- go.mod` + `frontend/package.json` → `## Dependency changes`.

5. **Open PR** — `peter-evans/create-pull-request@v8` with `if: always() && changed`, `branch: chore/update-deps`, `labels: dependencies`, `delete-branch: true`. Always creates/updates PR; CI will gate merge. Note: PRs created with `GITHUB_TOKEN` show `action_required` for `ci.yml` `pull_request` — click **Approve and run** (keep `GITHUB_TOKEN`; PAT `secrets.PAT` would auto-run but not needed for weekly cadence).

**Why `if: always()`?** To satisfy “always PR” — even if updater fails, PR still opens and surfaces via CI, not as silent failed run. `continue-on-error` local gates were removed because `ci.yml` is now the single gate.

## ci.yml

**Trigger:** `pull_request: branches [main]`, `push: branches [main]`, `workflow_dispatch`.

**Jobs:**

| Job | Runs On | Steps |
|-----|---------|-------|
| `Check (just check)` | `ubuntu-latest` | `setup-go`, `setup-bun`, `apt libgtk-3-dev`, `just check` |
| `Build (linux/amd64)` | `ubuntu-latest` | `setup-go`, `setup-bun`, `apt`, `go install wails`, `wails build -tags webkit2_41` |
| `Build (darwin/universal)` | `macos-latest` | same, `wails build -platform darwin/universal` |
| `Build (windows/amd64)` | `windows-latest` | `choco install nsis`, `wails build -nsis` |

Weekly cadence makes full matrix acceptable (vs daily where single `ubuntu` check would be cheaper). Check names are `Check (just check)` and `Build (linux/amd64)` etc. — these strings are the `required_status_checks.contexts` in branch protection.

## release.yml

**Trigger:** `workflow_dispatch` (manual `release_version` + `create_release`) OR `pull_request: types [closed], branches [main]`.

**Prepare job** only runs if `workflow_dispatch` OR (`pull_request.merged == true` AND (`label dependencies` OR `head ref chore/update-deps`)). Computes `version`:
- Manual: use `inputs.release_version`.
- Auto: `git describe --tags --abbrev=0` → `vMAJOR.MINOR.PATCH` → `PATCH+1` (or `0.1.0` if no tags).

**Build job** needs `prepare`, matrix same as `ci.yml`, plus `Compress binaries` (`7z`/`tar.xz`) and `Upload artifact`.

**Release job** needs `prepare+build` and `create_release==true`, generates notes from `git log` since last tag (grouped `feat`/`fix`/… + `Other`) and creates `softprops/action-gh-release` with `vVERSION`.

## Branch Protection

Set on `main`:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Check (just check)", "Build (linux/amd64)", "Build (darwin/universal)", "Build (windows/amd64)"]
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

And repo settings:

```json
{"allow_rebase_merge": true, "allow_squash_merge": false, "allow_merge_commit": false}
```

Effect: PR cannot be merged unless all 4 checks pass and branch is up-to-date; only `Rebase and merge` button is enabled.

## Customization

- Change `BINARY_NAME` in `release.yml:22` and `ci.yml` artifact names.
- Change `BUN_MIN_RELEASE_AGE`/`GO_MIN_RELEASE_AGE` to adjust min-age.
- Replace `just check` with your own `check` recipe or inline `go vet`/`oxlint`.
- For non-Wails projects, remove `libgtk`/`webkit` and `wails` steps, keep `go build`/`bun run build`.

## History

Extracted from a production Wails project after fixing TS7 breakage (vue-tsc requires TS6 until 7.1, side-by-side `typescript: npm:@typescript/typescript6@6.0.2` + `@typescript/native: npm:typescript@7.0.2`, `overrides` hold).
