# Templates

Copy these to your repo's `.github/workflows/` and customize `TODO` placeholders. All `Wails`/`Bun` specifics below are examples — keep only what your stack needs.

## Files

- `ci.yml` — PR checks (full matrix) on `pull_request` to `main`. Requires `just check` (example: `Wails` full matrix `linux/amd64`, `darwin/universal`, `windows/amd64` + `just check`; adapt `go build`/`wails build`/`bun` to your stack).
- `weekly-update.yml` — Weekly dependency update (2-week min-age, TS6 hold) → always PR.
- `release.yml` — Auto patch release on `pull_request:closed` with `dependencies` label.

## Customization Checklist

1. **BINARY_NAME**: In `release.yml:22` `env.BINARY_NAME` and `ci.yml` artifact names, replace `your-app` with your repo name.
2. **System deps** (example for `Wails`): In `ci.yml:27` adjust `libgtk-3-dev libwebkit2gtk-4.1-dev` to your needs (remove for pure Go/generic).
3. **Build tags** (example for `Wails`): In `ci.yml:73` `wails build -tags webkit2_41` adjust to your `-tags` or remove.
4. **justfile**: Ensure `just check` exists (`go fmt`, `go vet`, `oxlint`, `prettier`).
5. **TS hold**: If not using Vue, remove `overrides` in `frontend/package.json` and the `Verifying typescript hold` step in `weekly-update.yml:98`.
