# AI Dock

<img width="1254" height="1254" alt="icon-iadock" src="https://github.com/user-attachments/assets/55bcb730-6f1c-4626-a675-3799c249bc62" />
A premium macOS utility: a floating **liquid-glass edge tab** that watches your
**live local AI subscriptions** (Claude, Codex, Gemini, …) and shows per-session
usage — built for **macOS 26 (Tahoe)** with the native Liquid Glass API.

It renders **exactly the providers installed/signed-in on your Mac**: one ring
per live provider. If you have four, it shows four. Nothing hardcoded.

## What it looks like

A vertical black glass tab hugging the **left or right screen edge**, with the
concave curved cutouts from the reference mockups (wallpaper shows through the
curves). Inside: one organic progress ring per provider with its percentage
below. **Hover a ring → a glass speech-bubble popover** slides out on the inner
side, tail aimed at that ring, showing:

- `<Provider> Usage` header
- **Current session** — red/accent bar + `NN% Used` + `Resets in 51 min`
- **All models** — green bar + `NN% Used` + `Resets Thu 12:00 AM`

Drag the tab and it **snaps organically to the nearest edge** on release.

## Detection (local-only, no network)

Each detector looks for binaries, config dirs, credential files, **and exported
API keys in your shell rc** — so a "live subscription" is caught even without a
CLI binary installed.

| Provider | Signals | Usage source |
|---|---|---|
| Claude / Anthropic | `claude` binary, `~/.claude/`, `.credentials.json`, `ANTHROPIC_API_KEY` | recent `~/.claude/projects/**/*.jsonl` |
| OpenAI / Codex | `codex` binary, `~/.codex/`, `auth.json`, `OPENAI_API_KEY` | recent `~/.codex/sessions/**/*.jsonl` |
| Google Gemini | `gemini` binary, `~/.gemini/`, `GOOGLE_API_KEY`/`GEMINI_API_KEY` | recent `~/.gemini/tmp/**/chats/*` |

Detected ∩ enabled = what's shown. Add a provider = write a `…Detector` and
register it in `ProviderRegistry`.

> Usage fractions are soft estimates from local file activity. For authoritative
> numbers, point each detector's `estimateUsage()` at the provider's real API —
> the `ProviderRegistry` / `UsageStore` architecture is built for that swap.

## Settings (real window, ⌘,)

- **Edge**: Left / Right (the notch re-anchors live)
- **Providers**: toggle each detected provider on/off (shows its source: CLI / config / credentials)
- **Refresh every**: 15s / 30s / 1m / 5m
- **Launch at login** (via `SMAppService`)

All preferences persist via `UserDefaults` and apply instantly.

## Run

```bash
open "AI Dock.xcodeproj"      # then ⌘R
# or
xcodebuild -project "AI Dock.xcodeproj" -scheme "AI Dock" -destination 'platform=macOS' build
```

Requires **Xcode 26 / macOS 26 SDK** (uses `GlassEffect`). Deployment target
macOS 26.0. Runs as an accessory (`LSUIElement`): no Dock icon — just the edge
tab + a small ✦ status-bar item (Settings / Refresh / Quit).

## Project layout

```
AI Dock/
  App/        AIDockApp.swift (Settings scene), AppDelegate.swift (panel, status item, refresh loop)
  Design/     DesignTokens.swift, GlassModifiers.swift (palette, glass surfaces incl. tab + bubble)
  Window/     NotchPanelController.swift, EdgeSnapping.swift (floating panel, snap, dynamic height)
  Models/     Provider.swift, UsageSnapshot.swift
  Services/   DockSettings.swift, ProviderRegistry.swift, EnvKeys.swift,
              ClaudeCodeDetector.swift, CodexCLIDetector.swift, GeminiDetector.swift, UsageStore.swift
  Views/      NotchView.swift, UsagePopoverView.swift, SettingsView.swift
  Components/ ProgressRing.swift, ProviderGlyph.swift, UsageBar.swift,
              EdgeTabShape.swift, PopoverBubbleShape.swift
  Resources/  Assets.xcassets, AIDock.entitlements, Info.plist
```

## Notes

- Sandboxing is **off** so the app can read `~/.claude` / `~/.codex` / `~/.gemini`
  and your shell rc files. An App Store build would need user-selected-folder
  bookmarks or a privileged helper.
- The popover is hover-driven (tap pins it); positioning tracks the active ring
  so the tail always points at the right circle.
