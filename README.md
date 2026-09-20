# actions

Reusable [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/) for
driving builds on **GitHub-hosted runners**: keep the source private on Forgejo,
run the CI on a public GitHub "twin" (free minutes), and have Forgejo trigger it
and wait for the result.

## The pattern

```
push to Forgejo (Delnegend/<repo>)
  └─ .forgejo/workflows/<name>.yaml                      (private, source of truth)
       └─ uses: …/actions/dispatch-build@v1
            └─ gh api dispatches event_type=<name> ─────▶ .github/workflows/<name>.yaml
                 ▲                                          (public twin, no source)
                 │                                          ├─ clone Forgejo (secrets.FORGEJO)
                 │                                          └─ just check / build …
                 └──── gh run watch → delete ◀──────────────┘
```

- **Private Forgejo repo = source of truth.** A **public GitHub repo = workflows
  only** so the builds are free.
- **The repo names must match** (only the owner differs): `Delnegend/<repo>` ⇄
  `Vessel9457/<repo>`. The action resolves the GitHub repo from that rule.
- **One Forgejo action per GitHub action, identical file name.** Each
  `.forgejo/workflows/<name>.yaml` dispatches `event_type = <name>`; the
  same-named `.github/workflows/<name>.yaml` listens for exactly that. The
  `name:` of the calling workflow *is* the event, so there is nothing to
  duplicate.
- **Nothing is left public.** The trigger stays alive for the whole run
  (`gh run watch --exit-status`), pulls any artifacts, then deletes the public
  run (logs + artifacts). A scheduled `cleanup` workflow on the GitHub side is
  the backstop.

## `dispatch-build`

Composite action; runs with plain shell (no Node/checkout needed). It dispatches
the twin's workflow, resolves the run, waits for it, optionally downloads the
artifacts, and always deletes the public run. It exits non-zero if the GitHub run
fails, so the Forgejo job mirrors the result.

| Input | Default | Description |
|---|---|---|
| `gh_token` | — | GitHub token with Actions read/write (**required**) |
| `gh_owner` | `Vessel9457` | Owner of the public GitHub mirror |
| `ref` | caller's `GITHUB_SHA` | Commit/SHA to build |
| `download` | `false` | Download artifacts before deleting the run |
| `artifacts_dir` | `dist` | Destination for `download` |

```yaml
# .forgejo/workflows/ci.yaml
name: ci
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  github:
    runs-on: alpine
    steps:
      - uses: https://git.delnegend.com/Delnegend/actions/dispatch-build@v1
        with:
          gh_token: ${{ secrets.GH_ACTIONS }}
```

For a release — download the artifacts, then publish them (e.g. as a Forgejo
release):

```yaml
# .forgejo/workflows/release.yaml
name: release
on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  github:
    runs-on: alpine
    steps:
      - uses: https://git.delnegend.com/Delnegend/actions/dispatch-build@v1
        with:
          gh_token: ${{ secrets.GH_ACTIONS }}
          download: true
      - name: Publish to a Forgejo release
        env:
          TOKEN: ${{ github.token }}
        run: |
          # files are in ./dist — create/attach them to a release
          ...
```

## Secrets

| Repo | Secret | Value |
|---|---|---|
| Forgejo (source) | `GH_ACTIONS` | fine-grained PAT on the GitHub twin: **Actions** read/write, **Contents** read/write |
| GitHub (twin) | `FORGEJO` | Forgejo PAT, `read:repository` only (clones the private source) |
| GitHub (twin) | any build-time secrets | e.g. `GLOBAL_CLIENT_CRT`/`GLOBAL_CLIENT_KEY` |

The GitHub twin's workflow listens on `repository_dispatch` (plus
`workflow_dispatch` for manual runs) and echoes the caller's `correlation_id` in
`run-name`, which is what the action matches on.

## Requirements

- Runner image with `gh`, `jq`, `git`, `curl` and `bash` (the trimmed
  `registry.local:5000/forgejo-runner` image has them).
- The private repo's `.forgejo/workflows/*.yaml` and the twin's
  `.github/workflows/*.yaml` must use the same file names.
- Repository names must match on both sides; only `gh_owner` differs.

## Versioning

Pin `@v1`. Fixes to this repo move the `v1` tag; breaking changes cut `v2`.
