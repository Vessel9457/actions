# actions

Reusable [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/) for
driving builds on **GitHub-hosted runners**: keep the source private on Forgejo,
run the CI on a public GitHub "twin" (free minutes), and have Forgejo trigger it
and wait for the result. This README is the single source of truth for the
pattern — the GitHub twin's own README stays minimal on purpose.

## The pattern

```
push to Forgejo (Delnegend/<repo>)
  └─ .forgejo/workflows/<name>.yaml                       (private, source of truth)
       └─ uses: …/actions/dispatch-github@v1
            └─ gh api dispatches event_type=<name> ─────▶ Vessel9457/<repo>
                 ▲                                        .github/workflows/<name>.yaml
                 │                                        (public twin, no source)
                 │                                          ├─ clone Forgejo (secrets.FORGEJO)
                 │                                          └─ just check / build …
                 └──── gh run watch → delete ◀──────────────┘
```

- **Private Forgejo repo = source of truth.** A **public GitHub repo = workflows
  only**, so the builds are free.
- **The repo names must match** (only the owner differs): `Delnegend/<repo>` ⇄
  `Vessel9457/<repo>`. The action resolves the GitHub repo from that rule.
- **One Forgejo action per GitHub action, identical file name.** Each
  `.forgejo/workflows/<name>.yaml` dispatches `event_type = <name>`; the
  same-named `.github/workflows/<name>.yaml` listens for exactly that. The
  calling workflow's `name:` *is* the event, so there is nothing to duplicate.
- **Nothing is left public.** The trigger stays alive for the whole run
  (`gh run watch --exit-status`), pulls any artifacts, then deletes the public
  run (logs + artifacts). The twin's `cleanup` workflow is the backstop.

## `dispatch-github`

A composite action — plain shell, **no Node/checkout needed**. It dispatches the
twin's workflow, resolves the run, waits for it, optionally downloads the
artifacts, and always deletes the public run. It exits non-zero if the GitHub run
fails, so the Forgejo job mirrors the result.

| Input | Default | Description |
|---|---|---|
| `gh_token` | — | GitHub token with Actions read/write (**required**) |
| `gh_owner` | `Vessel9457` | Owner of the public GitHub mirror |
| `ref` | caller's `GITHUB_SHA` | Commit/SHA to build |
| `download` | `false` | Download artifacts before deleting the run |
| `artifacts_dir` | `dist` | Destination for `download` |

The event is taken from the calling workflow's name, and the repo from
`GITHUB_REPOSITORY` — so neither is configured per call.

### Forgejo caller — CI

```yaml
# .forgejo/workflows/ci.yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  github:
    name: Dispatch to Github
    runs-on: alpine
    steps:
      - name: Dispatch to Github
        uses: https://git.delnegend.com/Delnegend/actions/dispatch-github@v1
        with:
          gh_token: ${{ secrets.GH_ACTIONS }}
```

### Forgejo caller — release

`download: true` pulls the artifacts into `./dist`; the caller then publishes
them (here: as a Forgejo release).

```yaml
# .forgejo/workflows/release.yaml
name: release

on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  github:
    name: Dispatch to Github
    runs-on: alpine
    steps:
      - name: Dispatch to Github
        uses: https://git.delnegend.com/Delnegend/actions/dispatch-github@v1
        with:
          gh_token: ${{ secrets.GH_ACTIONS }}
          download: true

      - name: Publish to a Forgejo release
        env:
          TOKEN: ${{ github.token }}
          SERVER: ${{ github.server_url }}
          REPO: ${{ github.repository }}
          SHA: ${{ github.sha }}
        run: |
          set -euo pipefail
          ASSET="$(find dist -type f | head -1)"
          VERSION="$(basename "$ASSET" | sed -E 's/.*-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"
          TAG="v${VERSION}"
          API="${SERVER}/api/v1/repos/${REPO}"
          REL_ID="$(curl -fsSL -H "Authorization: token ${TOKEN}" "$API/releases/tags/$TAG" 2>/dev/null | jq -r '.id' 2>/dev/null || true)"
          [ -n "${REL_ID:-}" ] && [ "$REL_ID" != "null" ] || REL_ID="$(curl -fsSL -X POST \
            -H "Authorization: token ${TOKEN}" -H 'Content-Type: application/json' \
            -d "$(jq -n --arg t "$TAG" --arg s "$SHA" '{tag_name:$t, target_commitish:$s, name:$t, draft:false, prerelease:false}')" \
            "$API/releases" | jq -r '.id')"
          find dist -type f -print0 | while IFS= read -r -d '' f; do
            curl -fsSL -X POST -H "Authorization: token ${TOKEN}" \
              -F "attachment=@$f" "$API/releases/$REL_ID/assets?name=$(basename "$f")" >/dev/null
            echo "uploaded $(basename "$f")"
          done
```

## Secrets

| Repo | Secret | Value |
|---|---|---|
| Forgejo (source) | `GH_ACTIONS` | fine-grained PAT on the GitHub twin: **Actions** read/write, **Contents** read/write |
| GitHub (twin) | `FORGEJO` | Forgejo PAT, `read:repository` only (clones the private source) |
| GitHub (twin) | build-time secrets | e.g. `GLOBAL_CLIENT_CRT` / `GLOBAL_CLIENT_KEY` |

## The GitHub twin

A public repo with the same name, holding only workflows. Both
`repository_dispatch` (the Forgejo trigger) and `workflow_dispatch` (manual) are
wired; the run echoes the caller's `correlation_id` in `run-name`, which is what
`dispatch-github` matches on. Source is always cloned from Forgejo with
`secrets.FORGEJO`.

### `.github/workflows/ci.yaml` — the check gate

```yaml
name: ci

on:
  repository_dispatch:
    types: [ci]
  workflow_dispatch:
    inputs:
      ref: { required: false, default: main }
      correlation_id: { required: false }

run-name: "ci ${{ github.event.client_payload.correlation_id || inputs.correlation_id || github.sha }}"

permissions:
  contents: read

env:
  FJ_HOST: git.delnegend.com
  FJ_OWNER: Delnegend

jobs:
  check:
    name: Check (just check)
    runs-on: ubuntu-latest
    steps:
      - name: Fetch source from Forgejo
        env:
          TOKEN: ${{ secrets.FORGEJO }}
          REF: ${{ github.event.client_payload.ref || inputs.ref || 'main' }}
        run: |
          set -euo pipefail
          REPO="${GITHUB_REPOSITORY#*/}"
          git clone "https://oauth2:${TOKEN}@${FJ_HOST}/${FJ_OWNER}/${REPO}.git" .
          git remote set-url origin "https://${FJ_HOST}/${FJ_OWNER}/${REPO}.git"
          git checkout "$REF"

      # … language setup, then the single gate:
      - name: Run checks
        run: just check
```

### `.github/workflows/release.yaml` — batched release

Version comes from the **source repo's** `v*` tags (the Forgejo action creates
them when it publishes), so the workflow clones Forgejo with tags; it does not
publish anything itself. The project-specific build/packaging is marked.

```yaml
name: release

on:
  schedule:
    - cron: '0 0 * * 0' # Weekly
  workflow_dispatch:
    inputs:
      ref: { required: false, default: main }
      release_version: { required: false, type: string, default: "" }
      correlation_id: { required: false }
  repository_dispatch:
    types: [release]

run-name: "release ${{ github.event.client_payload.correlation_id || inputs.correlation_id || github.sha }}"
concurrency:
  group: release-main
  cancel-in-progress: false
permissions:
  contents: read

jobs:
  prepare:
    name: Prepare
    runs-on: ubuntu-slim
    outputs: { version: ${{ steps.version.outputs.version }}, skip: ${{ steps.version.outputs.skip }} }
    steps:
      - name: Fetch source and tags from Forgejo
        env:
          TOKEN: ${{ secrets.FORGEJO }}
          REF: ${{ github.event.client_payload.ref || inputs.ref || 'main' }}
        run: |
          set -euo pipefail
          REPO="${GITHUB_REPOSITORY#*/}"
          git clone --quiet "https://oauth2:${TOKEN}@git.delnegend.com/Delnegend/${REPO}.git" src
          git -C src checkout --quiet "$REF"
      - name: Determine version and whether to release
        id: version
        run: |
          set -euo pipefail
          EXPLICIT="${{ inputs.release_version }}"
          if [ -n "$EXPLICIT" ]; then echo "version=${EXPLICIT#v}" >> "$GITHUB_OUTPUT"; echo "skip=false" >> "$GITHUB_OUTPUT"; exit 0; fi
          LATEST="$(git -C src describe --tags --match 'v*' --abbrev=0 2>/dev/null || echo 'v0.0.0')"
          [ "$LATEST" = "v0.0.0" ] && COUNT="$(git -C src rev-list --count HEAD)" || COUNT="$(git -C src rev-list "${LATEST}..HEAD" --count)"
          if [ "$COUNT" -eq 0 ]; then echo "skip=true" >> "$GITHUB_OUTPUT"; echo "version=${LATEST#v}" >> "$GITHUB_OUTPUT"; exit 0; fi
          if [ "$LATEST" = "v0.0.0" ]; then NEXT="0.1.0"; else
            RAW="${LATEST#v}"; IFS='.' read -r major minor patch <<< "$RAW"
            NEXT="${major:-0}.${minor:-0}.$(( ${patch:-0} + 1 ))"
          fi
          echo "version=$NEXT" >> "$GITHUB_OUTPUT"; echo "skip=false" >> "$GITHUB_OUTPUT"

  build:
    name: Build
    needs: prepare
    if: needs.prepare.outputs.skip != 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Fetch source from Forgejo
        env:
          TOKEN: ${{ secrets.FORGEJO }}
          REF: ${{ github.event.client_payload.ref || inputs.ref || 'main' }}
        run: |
          set -euo pipefail
          REPO="${GITHUB_REPOSITORY#*/}"
          git clone "https://oauth2:${TOKEN}@git.delnegend.com/Delnegend/${REPO}.git" .
          git checkout "$REF"
      # … project build, then:
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: <repo>-<target>
          path: <artifact>
          if-no-files-found: error
          retention-days: 1
```

### `.github/workflows/cleanup.yaml` — privacy backstop

```yaml
name: cleanup

on:
  schedule:
    - cron: '0 0 * * *'
  workflow_dispatch:

permissions:
  actions: write
  contents: read

jobs:
  delete-old-runs:
    runs-on: ubuntu-24.04
    steps:
      - uses: Mattraks/delete-workflow-runs@v2
        with:
          token: ${{ github.token }}
          repository: ${{ github.repository }}
          keep_minimum_runs: 0
          retain_days: 0
```

## Runner

The Forgejo runner's job container needs `gh`, `jq`, `git`, `curl` and `bash`
(this homelab builds `registry.local:5000/forgejo-runner`: Alpine + the pinned
`forgejo-runner` binary + those tools; host executor, `labels: ["alpine:host"]`).

## Adopting for a new repo

1. Create the public GitHub twin `Vessel9457/<repo>` (name must match) with the
   three workflows above.
2. Twin secrets: `FORGEJO` (read-only PAT) + any build-time secrets.
3. Forgejo repo secret: `GH_ACTIONS` (Actions + Contents read/write on the twin).
4. Add `.forgejo/workflows/<name>.yaml` per GitHub workflow, same file name, one
   `dispatch-github@v1` step.
5. Push, or run the release action manually.

## Versioning

Pin `@v1`. Non-breaking fixes move the `v1` tag; breaking changes cut `v2`.
