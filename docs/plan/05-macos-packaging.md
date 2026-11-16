# 05 — Building the Mac app on GitHub

**Question:** can the app be built on GitHub and downloaded from there to run on a Mac?

**Answer:** yes. A GitHub Actions workflow builds the app on a macOS runner and attaches a `.dmg` to a GitHub Release. The one limit is that, without a paid Apple Developer account, the app is not notarized, so the first launch needs a manual approval.

Checked on 2026-11-16. Nothing here has been run yet; T1.5 is the task that proves it.

## What was verified

| Point | Finding | Source |
|---|---|---|
| Cost of building | Standard GitHub-hosted runners are free for public repositories. This repo is public. Larger runners are billed even for public repos, so the workflow uses standard ones. | [GitHub Docs: Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage), [GitHub Docs: runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing) |
| macOS runners | Standard macOS runners exist for both Apple Silicon and Intel (labels such as `macos-15-intel`). | [GitHub Docs: choosing the runner](https://docs.github.com/actions/using-jobs/choosing-the-runner-for-a-job) |
| Architectures | electron-builder builds `x64`, `arm64` or `universal` Mac apps. | [electron-builder: macOS](https://www.electron.build/docs/mac) |
| Signing without a certificate | With no certificate, current electron-builder skips signing unless ad-hoc signing is requested with identity `-`. Ad-hoc builds get a built-in entitlements file. The option's location changed in v27 (`mac.sign.identity`), so T1.5 must follow the docs of the version pinned in `package.json`. | [electron-builder: code signing for macOS](https://www.electron.build/docs/features/code-signing/code-signing-mac) |
| First launch | An app without a Developer ID signature and notarization is blocked by Gatekeeper on first open. The user allows it once in System Settings → Privacy & Security → "Open Anyway". | [electron-builder: code signing](https://www.electron.build/docs/features/code-signing/), [note on unsigned macOS apps](https://chrplr.github.io/note-about-macos-unsigned-apps) |
| Removing the warning | Sign with a Developer ID certificate and notarize with Apple. | [Flavio Copes: Open Anyway](https://flaviocopes.com/macos-open-anyway/) |

## Release flow

```
git tag v0.1.0 && git push --tags
        │
        ▼
GitHub Actions (release.yml, macOS runner)
  npm ci → npm run build → electron-builder --mac (arm64 + x64, ad-hoc signed)
  → run the packaged app with --smoke
  → upload .dmg and .zip to the GitHub Release
        │
        ▼
User: Releases page → download the .dmg for their Mac → drag to Applications
      → first launch: System Settings → Privacy & Security → Open Anyway (once)
```

Which file to download: `arm64` for Macs with Apple Silicon (M1 and later), `x64` for Intel Macs.

## Risks and fallbacks

| Risk | Detected by | Fallback |
|---|---|---|
| `better-sqlite3` (native module) fails to build for one architecture when cross-compiling | T1.5 smoke step on CI | Build each architecture on its own runner (matrix: one Apple Silicon, one Intel). |
| Native module still a problem | T1.5 | Replace the driver behind the repository interfaces with a non-native one (Node's built-in SQLite if the pinned Electron has it, or a WebAssembly build). Only `src/server/db/` changes. Decision goes to `foundation-architect`. |
| Ad-hoc signed app refuses to start after download | T1.5 acceptance on the user's Mac | Document `xattr -cr "/Applications/Sergnanese Social.app"` in `INSTALL.md` as a second way to clear the download quarantine. |
| First-launch approval is too awkward for other volunteers | Real use | T4.7: join the Apple Developer Program, sign and notarize in the workflow. |
| App size (Electron bundles a browser) | Release artefact | Accepted: that bundled browser is what renders the templates. |

## What is not possible

- An App Store or TestFlight build. Not planned.
- A native iOS app from this codebase. iPhone use comes through the browser over the home Wi-Fi (T4.4).
- Auto-update without proper signing. Updating means downloading the newer `.dmg`. The app shows its version and a link to the Releases page.
