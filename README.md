# AI Cost Monitor for macOS

A native macOS menu-bar application for monitoring AI service spend, starting with OpenRouter.

## Current status

The app queries OpenRouter **Analytics**:

```text
POST https://openrouter.ai/api/v1/analytics/query
```

That endpoint accepts an explicit `time_range` and `granularity` (`minute`, `hour`, `day`, `week`, `month`). The browser Activity UI uses the same contract. A management key is required. Regular inference keys and OpenRouter OAuth PKCE keys return 403 here.

The older Activity endpoint (`GET /api/v1/activity`) remains available as a fallback client method, but the live dashboard uses Analytics.

## Reporting

All screenshot-style ranges are enabled:

- Relative: Past 15/30 minutes, 1/3/24/48 hours, 1 week, 1 month, 1 year
- Calendar: Today, Yesterday, This/Previous Week, This/Previous Month, This/Previous Year
- Custom range with From/To pickers
- Latest available completed UTC day and last 30 days

Calendar ranges use the selected display timezone. The example payload from the OpenRouter UI:

```json
{
  "metrics": ["total_usage"],
  "dimensions": ["model"],
  "granularity": "day",
  "time_range": {
    "start": "2026-08-16T22:00:00.000Z",
    "end": "2026-08-17T20:59:02.061Z"
  }
}
```

is the same shape this app sends. `Today` in GMT+2 therefore starts at `22:00Z` the previous UTC day.

## Settings

The retained settings window has:

- **General / Overview** — live connection state, management-key status, current report, last refresh, and cache/console activity
- **Provider** — OpenRouter is enabled; other providers remain listed as coming soon
- **Reporting** — menu-bar dialog range selection, timezone, decimals, and raw HTTP capture
- **Alerts** — local budget threshold and optional macOS notification
- **Release** — signed update status and automatic-update preference
- **Console** — filter, copy, clear, sanitized log export

General is intentionally an operational overview rather than a second settings form. Configuration lives in Provider, Reporting, and Alerts; General tells you what the monitor is doing right now and provides shortcuts to those areas.

The window can only be closed. It cannot be minimized or maximized.

### Settings overview

The settings window provides a live overview of the connection, current report, and recent local activity:

![AI Cost Monitor settings overview](docs/screenshots/settings-overview.png)

### Menu-bar popover

The menu-bar popover keeps the current spend, request/session counts, remaining credits, model breakdown, and selected time range visible at a glance:

![AI Cost Monitor menu-bar popover](docs/screenshots/menu-bar-popover.png)

## Product features

![AI Cost Monitor app icon](docs/app-icon-live-spend.svg)

The app icon uses a live-spend sparkline and wallet motif to represent usage costs at a glance.

- Compact menu-bar popover with spend, Sessions, remaining Credits, model/provider details, and a sparkline
- Local budget threshold with optional notification
- Sanitized console export to Application Support
- Signed local `.app` via `Scripts/build-app.sh`
- Live Spend app icon with Sparkline and wallet motif

Distribution limitations, documented in Settings → Release:

- Developer ID notarization
- Mac App Store packaging

Auto-update is implemented with Sparkle 2.9.6. It is enabled only in packaged releases that include a Sparkle EdDSA public key and a signed appcast; direct `swift run` binaries and unsigned previews keep it disabled.
OAuth login is not included because OpenRouter OAuth mints an inference key, not a management key.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools or Xcode
- An OpenRouter management API key with analytics/activity access

## Updates

The app uses Sparkle 2.9.6 with EdDSA-signed appcasts hosted on GitHub Releases. Update checks run over HTTPS, and Sparkle verifies the signed feed and update archive before installation. The `Automatic updates` setting controls whether Sparkle may download and install updates without a separate approval step.

The release workflow requires these GitHub Actions secrets:

- `SPARKLE_PUBLIC_ED_KEY` — public key embedded into the packaged app
- `SPARKLE_EDDSA_PRIVATE_KEY` — private key used only by the release workflow to sign appcasts and update archives

Never commit the private key. Generate the key pair with Sparkle's `generate_keys` tool on macOS, store the private value as a GitHub Actions secret, and keep only the public value in the release configuration.

## Install a release

1. Download the latest **DMG** from the repository's [Releases](https://github.com/LukaAsceric/macos-ai-cost-monitor/releases) page.
2. Open the disk image and drag **MacOSAICostMonitor.app** to **Applications**.
3. On first launch, macOS may show an unidentified-developer warning because public preview builds are ad-hoc signed. Control-click the app, choose **Open**, and confirm. If needed, use **System Settings → Privacy & Security → Open Anyway**.
4. Open **Settings → Provider** and add an OpenRouter management key.

The ZIP contains the same universal app. `SHA256SUMS.txt` contains SHA-256 checksums for both installers.

### Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- OpenRouter management key with analytics access

### Security

The management key is stored in macOS Keychain. It is not included in the app, DMG, ZIP, logs, cache, or release artifacts.

### Distribution and updates

Public preview builds are ad-hoc signed and not notarized. A future Developer ID + notarized release will remove the first-launch Gatekeeper step.

Packaged releases use Sparkle 2.9.6 with signed EdDSA appcasts. The update behavior is controlled in Release settings.

## Build and run

```bash
swift build
swift test
bash Scripts/build-app.sh
open dist/MacOSAICostMonitor.app
```

Use the signed `.app` for normal operation. `swift run` can change the development executable identity and cause repeated Keychain prompts.

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash Scripts/build-app.sh
```

The key is stored in the macOS Keychain. It is not written to UserDefaults, the usage cache, logs, or the application bundle.

## Setup

1. Create a management key in OpenRouter Settings → Management Keys.
2. Grant analytics/activity read access.
3. Launch the signed app.
4. Open Settings and paste the key.
5. Choose a report range and use **Refresh now**.

## Troubleshooting

- **401:** the key was rejected or revoked
- **403:** the key is not a management key or lacks analytics access
- **429:** OpenRouter rate-limited the request
- **Repeated Keychain prompts:** launch `dist/MacOSAICostMonitor.app`, not `swift run`

## Development note

The repository can be edited on Linux, but AppKit, SwiftUI, Keychain, `swift test`, and `.app` verification must be run on macOS.
