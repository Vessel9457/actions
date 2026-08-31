# actions

![License](https://img.shields.io/badge/License-MIT-yellow?style=flat)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Go%20%7C%20Bun%20%7C%20Wails-lightgrey?style=flat)

Reusable GitHub Actions flow: **Weekly Update → PR with full-matrix CI gate → Rebase & merge → Auto Release**. Designed for AI agents to apply to new Go + Bun + Wails projects.

## Flow

```mermaid
flowchart TD
    A[Dependabot<br/>weekly Mon 02:00<br/>dependabot.yml] -->|grouped PR<br/>chore(deps)<br/>assignees: Delnegend| B[Pull Request]
    B --> C[CI Checks<br/>ci.yml<br/>Check + Build ×3]
    C -->|all green, patch/minor| D[Auto-merge<br/>dependabot-auto-merge.yml<br/>rebase]
    C -->|any red or major| E[Assigned to you<br/>human fix required]
    D --> F[Release<br/>release.yml<br/>patch bump + artifacts]
```

* **Dependabot** creates/updates PRs (`gomod` + `npm` frontend, 1 per ecosystem, grouped `all-dependencies`, `cooldown: 14d`) weekly Mon 02:00, label `dependencies`, `assignees: [Delnegend]` (always), `ignore: typescript >=7.0.0` for TS6 hold. No local build validation — `ci.yml` full-matrix is the single gate (pure YAGNI).
* **Dependabot auto-merge** (`dependabot-auto-merge.yml:1` `on: pull_request` + `workflow_dispatch`) gates `major` (`fetch-metadata@v2:1` `update-type != major`) and enables `gh pr merge --auto --rebase:1` for patch/minor when `actor == dependabot[bot]` + `label dependencies`; on red, PR stays open assigned to you (`weekly: update dependencies PR -> ci guards -> ok ? merge+release new version : assign me to the PR`).
* **CI** runs full matrix (`linux/amd64`, `darwin/universal`, `windows/amd64`) + `just check` on every PR to `main`. Weekly is cheap, so full matrix is acceptable.
* **Branch protection** on `main` requires 4 checks + linear history. Only `Rebase and merge` is allowed, `allow_auto_merge: true:1` for Dependabot patch/minor.
* **Release** runs only on `pull_request:closed` to `main` with `dependencies` label — auto patch bump (`v0.0.0` → `v0.1.0` → `v0.1.1` …) and `softprops/action-gh-release`.

## Quick Start (for humans)

```bash
# 1. Copy templates to your repo
cp templates/ci.yml .github/workflows/ci.yml
cp templates/release.yml .github/workflows/release.yml
cp templates/dependabot.yml .github/dependabot.yml
cp templates/dependabot-auto-merge.yml .github/workflows/dependabot-auto-merge.yml
cp scripts/setup-branch-protection.sh ./scripts/

# 2. Customize
# - Edit BINARY_NAME in release.yml & ci.yml
# - Edit cooldown in dependabot.yml (14d) if needed
# - Edit justfile `check` recipe to match your stack

# 3. Apply branch protection (requires gh cli)
./scripts/setup-branch-protection.sh Delnegend/your-repo

# 4. Push to main
git add .github/workflows/ci.yml .github/workflows/release.yml .github/workflows/dependabot-auto-merge.yml .github/dependabot.yml frontend/package.json
git commit -m "ci: add dependabot→PR→CI→release flow from actions template"
git push
```

## Templates

| File | Purpose | Trigger |
|------|---------|---------|
| `templates/ci.yml` | Full-matrix checks + `just check` | `pull_request` to `main`, `push` to `main` |
| `templates/dependabot.yml` | Weekly grouped deps, 14d cooldown + TS6 ignore (`schedule` weekly Mon 02:00) | `dependabot` app |
| `templates/dependabot-auto-merge.yml` | Auto-merge patch/minor (`fetch-metadata` gate, `gh pr merge --auto --rebase`) + manual test | `pull_request` + `workflow_dispatch` |
| `templates/release.yml` | Cross-platform build + auto patch release | `pull_request:closed` to `main`, `workflow_dispatch` |
| `templates/package.json.overrides` | Bun `overrides` + comment for TS hold | Bun |

See `docs/FLOW.md` for detailed behavior and `AGENTS.md` for AI agent instructions.

## AI Agent Guide

This repo is optimized for AI agents. See [AGENTS.md](./AGENTS.md) for step-by-step instructions to apply the flow to a new project. The agent should:

1. Detect stack (`go.mod`, `frontend/package.json`, `justfile`)
2. Copy and customize templates (replace `BINARY_NAME`, adjust `libgtk` deps, etc.)
3. Run `scripts/setup-branch-protection.sh` via `gh api`
4. Verify with `python3 -c "import yaml; yaml.safe_load(...)"`

## License

MIT
