# Changelog

## Unreleased

- Import matches from tuttocampo (one matchday, the rest of the season, or the whole season), from CSI Live through an in-app browser, and from the federation PDF calendar. Every import goes through a review before saving.
- "Scarica tutti gli avversari…" fills the opponent list with names and logos in one go.
- Opponents are pre-matched in every import review; confirmed links are remembered as aliases.
- Matches: Weekend / Tutte switch to manage every recorded match.

## 0.1.0 - first release

First version for the weekend routine of ASD Sergnanese.

- Weekly workflow: pick the weekend's matches and generate the images for Instagram (post, story) and Facebook.
- Built-in HTML templates rendered off-screen to exact-size PNG, with the network blocked.
- Local database with matches, opponents and logos; seed data for a first trial.
- Share generated images with AirDrop or the Share menu.
- Italian interface, Light and Dark Mode.
- Apple silicon only (macOS 15 or later). The app is ad-hoc signed and not notarized: the first launch needs "Open Anyway" in System Settings, see docs/INSTALL.md.
