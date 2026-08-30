# Templates

Copy these to your repo's `.github/workflows/` and customize `TODO` placeholders.

## Files

- `ci.yml` — PR checks (full matrix) on `pull_request` to `main`. Requires `just check`.
- `weekly-update.yml` — Weekly dependency update (2-week min-age, TS6 hold) → always PR.
- `release.yml` — Auto patch release on `pull_request:closed` with `dependencies` label.

## Customization Checklist

1. **BINARY_NAME**: In `release.yml:22` `env.BINARY_NAME` and `ci.yml` artifact names, replace `gallery-preprocessor` with your repo name.
2. **System deps**: In `ci.yml:27` and `weekly-update.yml:116`, adjust `libgtk-3-dev libwebkit2gtk-4.1-dev` to your needs (remove for non-Wails).
3. **Build tags**: In `ci.yml:73` `wails build -tags webkit2_41` and `weekly-update.yml:135` `go build -tags`, adjust to your `-tags`.
4. **justfile**: Ensure `just check` exists (`go fmt`, `go vet`, `oxlint`, `prettier`).
5. **TS hold**: If not using Vue, remove `overrides` in `frontend/package.json` and the `Verifying typescript hold` step in `weekly-update.yml:98`.
