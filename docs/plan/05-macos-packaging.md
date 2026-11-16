# 05 — Building the Mac app on GitHub

**Question:** can the app be built on GitHub and downloaded from there to run on a Mac?

**Answer:** yes. A GitHub Actions workflow builds the app on a macOS runner and attaches a `.dmg` to a GitHub Release. The one limit is that, without a paid Apple Developer account, the app is not notarized, so the first launch needs a manual approval.

Checked on 2026-11-16. The local build was tried on the user's Mac (see README, "What was verified"). The GitHub build has not been run yet; T1.5 is the task that proves it.

## How the app is built

There is no Xcode project. The app is a Swift package; a script turns the built binary into a Mac app. The approach and the starting scripts come from the `macos-spm-app-packaging` skill.

```
swift build -c release --arch arm64
        │
        ▼
Scripts/package_app.sh
  build/Sergnanese Social.app/Contents/
    MacOS/SergnaneseSocial          the binary
    Info.plist                      from Packaging/Info.plist + version.env
    Resources/AppIcon.icns
    Resources/Templates, Seed, Fixtures   plain folders copied from Resources/
    Resources/it.lproj/             marks the app as Italian, so system menus and panels are in Italian
  codesign --force --sign - …       ad-hoc signature
  hdiutil create …                  Sergnanese-Social-<version>.dmg with an Applications shortcut
```

`Info.plist` essentials: `CFBundleIdentifier com.sergnanese.social`, `CFBundleDevelopmentRegion it`, `LSMinimumSystemVersion 15.0`, `LSApplicationCategoryType public.app-category.graphics-design`, `NSHighResolutionCapable`, `NSPrincipalClass NSApplication`.

## What was verified

| Point | Finding | Source |
|---|---|---|
| Cost of building | Standard GitHub-hosted runners are free for public repositories. This repo is public. Larger runners are billed even for public repos, so the workflow uses standard ones. | [GitHub Docs: Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage), [GitHub Docs: runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing) |
| macOS runners | Standard Apple silicon macOS runners exist. They come with Xcode, so the Swift toolchain is there. | [GitHub Docs: choosing the runner](https://docs.github.com/actions/using-jobs/choosing-the-runner-for-a-job) |
| Local toolchain | Swift 6.4.2 from the Command Line Tools builds SwiftUI, GRDB, swift-mustache and ZIPFoundation and renders a template to an exact-size PNG. | Tried on the user's Mac, 2026-11-16 |
| Signing without a certificate | `codesign --sign -` makes an ad-hoc signature. Apple silicon refuses to run unsigned code, so this step is required, not optional. | Apple `codesign` manual |
| First launch | An app without a Developer ID signature and notarization is blocked by Gatekeeper on first open. The user allows it once in System Settings → Privacy & Security → "Open Anyway". | [note on unsigned macOS apps](https://chrplr.github.io/note-about-macos-unsigned-apps), [Flavio Copes: Open Anyway](https://flaviocopes.com/macos-open-anyway/) |
| Removing the warning | Sign with a Developer ID certificate and notarize with Apple (T4.7). | — |

The exact first-launch wording on macOS 27 has not been checked. It is checked by the user at the Wave 1 gate, on the real Mac, with a `.dmg` **downloaded through a browser**: a locally built app is never quarantined and proves nothing about Gatekeeper.

## Release flow

```
git tag v0.1.0 && git push --tags
        │
        ▼
GitHub Actions (release.yml, Apple silicon macOS runner)
  Scripts/check.sh → Scripts/package_app.sh release
  → copy the .app to a temp folder, delete .build, run it with --smoke
  → upload the .dmg to the GitHub Release
        │
        ▼
User: Releases page → download the .dmg → drag to Applications
      → first launch: System Settings → Privacy & Security → Open Anyway (once)
```

One file to download. There is no Intel build (decision P7).

## Risks and fallbacks

| Risk | Detected by | Fallback |
|---|---|---|
| The runner's Swift is older than the user's and rejects some syntax | T1.5, first CI run | `swift-tools-version` is 6.0 and code avoids newer-only features. If still needed, select a newer Xcode on the runner with `xcode-select`. |
| Off-screen `WKWebView` does not render on a CI runner (no logged-in display) | T1.5 smoke step | Run render tests and the smoke step only where a window server exists; if GitHub's runner lacks one, mark render tests "local only" and keep the rest on CI. The release is then smoke-tested by the user before tagging. |
| Resources not found when the app runs on another Mac | Smoke step runs from a copied `.app` with `.build` deleted | Resources are plain folders under `Contents/Resources`, never `Bundle.module` (see `01-architecture.md` §2). |
| Ad-hoc signed app refuses to start after download | Wave 1 gate on the user's Mac | Document `xattr -cr "/Applications/Sergnanese Social.app"` in `INSTALL.md` as a second way to clear the download quarantine. |
| First-launch approval is too awkward for other volunteers | Real use | T4.7: join the Apple Developer Program, sign and notarize in the workflow. |
| App icon looks soft | Wave 1 gate | Needs a crest of at least 1024 px or a vector file from the user (README, "Inputs still needed"). |

## What is not possible

- An App Store or TestFlight build. Not planned.
- An iPhone app. Images reach the phone by AirDrop or the Share menu (decision D8).
- Auto-update without proper signing. Updating means downloading the newer `.dmg`. The Aiuto menu has "Scarica aggiornamenti…", which opens the Releases page, and the About panel shows the version.
- The new layered icon format (`.icon`). It needs Xcode's `actool`. The app ships a classic `.icns`.
