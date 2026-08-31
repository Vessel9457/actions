# Flow — Weekly Update → PR → CI Gate → Release

Detailed behavior of the three workflows and branch protection.

## Overview

```
Renovate (before 4am Mon, 14d, grouped)
  │
  ▼
renovate.json ──grouped──► PR chore/update-deps-all (label: dependencies)
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

## dependabot.yml

**Schedule:** `weekly` `day: monday` `time: "02:00"` (Mon 02:00 UTC), `cooldown: 14d` grouped `all-dependencies` → 1 PR per ecosystem (`gomod` + `npm` frontend).

**Config** (`dependabot.yml:1` `version: 2`):
- `labels: [dependencies]`, `commit-message: prefix: "chore(deps)"`, `groups: all-dependencies: patterns: ["*"]` (single PR per ecosystem, 2 PRs/week, `open-pull-requests-limit: 1`)
- `ignore: typescript >=7.0.0` (TS6 hold, `vuejs/language-tools#6124`, `frontend/package.json:overrides` stays as stdlib safety net)
- `cooldown: default-days: 14` for Go+Bun

**Repo-level:** No `frontend/bunfig.toml` (pure YAGNI, deleted) — Dependabot `cooldown` is single source.

**Flow:** Dependabot creates/updates `PR dependabot/*` (grouped, 14d) → `ci.yml` full-matrix single gate → `release.yml` auto patch on `label: dependencies` (label-only gate).

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
