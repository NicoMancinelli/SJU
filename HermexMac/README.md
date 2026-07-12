# Hermex for Mac

A native macOS SwiftUI client for a self-hosted [hermes-webui](https://github.com/nesquena/hermes-webui) server — the Mac counterpart to [Hermex for iOS](https://github.com/uzairansaruzi/hermex). Your Mac is the control plane; the agent, its tools, and your data stay on hardware you control.

## Features

- **Connect** to your server with its URL and password (stored in the macOS Keychain; auth cookie handled automatically).
- **Chat** with your agent and watch responses stream in live, with reasoning blocks, tool-call cards, and rendered Markdown (headings, lists, quotes, code blocks). Dropped streams reconnect and replay.
- **Steer or stop** a run mid-flight.
- **Approvals & clarifications** — respond inline when the agent asks to run a command or has a question.
- **Sessions** sidebar — browse, search, open, create, rename, pin, archive, and delete every conversation on your server.
- **Attachments** — drag files onto the chat (or use the paperclip) to upload and send them with your message.
- **Workspaces** — start new sessions in any workspace registered on the server.
- **Skills** — browse, filter, and enable/disable the agent's installed skills.
- **Tasks** — view your agent's scheduled cron jobs; run, pause, or resume them.
- **Memory** — read the agent's memory, user profile, and soul files.
- **Model picker** — switch between any model or provider your server exposes.
- No analytics, no tracking, no third-party relay. The app talks only to your server.

## Install

Grab the latest `.dmg` (or `.zip`) from [Releases](../../releases), open it, and drag **Hermex** to Applications.

The app is ad-hoc signed, not notarized, so macOS Gatekeeper warns on first launch. Either right-click the app → **Open** → **Open**, or clear the quarantine flag:

```sh
xattr -cr /Applications/Hermex.app
```

Requires macOS 13 Ventura or later (universal: Apple Silicon + Intel).

## Getting started

Hermex is a client only — you bring your own [hermes-webui](https://github.com/nesquena/hermes-webui) server:

1. Run `hermes-webui` on a machine you control and set `HERMES_WEBUI_PASSWORD`.
2. Make it reachable (Cloudflare Tunnel / reverse proxy with real HTTPS, Tailscale, or `http://localhost:8787` on the same Mac).
3. Launch Hermex, enter the server URL and password, and connect.

## Build from source

Requires Xcode 15+ on macOS.

```sh
cd HermexMac
swift build            # debug binary
./Packaging/package_app.sh 1.0.0   # full Hermex.app + zip + dmg in dist/
```

## Releasing

The [`hermex-macos` workflow](../.github/workflows/hermex-macos.yml) builds a universal binary on a macOS runner, assembles and ad-hoc signs `Hermex.app`, and publishes the `.zip` and `.dmg` to a GitHub Release. It publishes when any of these name a new version:

- bumping [`VERSION`](VERSION) in a commit (the workflow creates the matching `v*` tag and release automatically),
- pushing a tag like `v1.0.0`,
- running the workflow manually with the `release_tag` input.

Every branch push also runs the build as a compile check and uploads the app as a workflow artifact.

## License

MIT. This project is inspired by and derived in part from [Hermex for iOS](https://github.com/uzairansaruzi/hermex) (MIT, © 2026 Uzair Ansar) — see [NOTICE.md](NOTICE.md) and [LICENSE-hermex-upstream.txt](LICENSE-hermex-upstream.txt).
