# Changelog

All notable changes to Hermex for Mac.

## 1.0.0 — 2026-07-12

- Long transcripts page: a **Load earlier messages** control fetches history windows on demand.
- **Check for Updates** in Settings compares the running version with the latest GitHub Release.
- First stable release: the full v0.x feature set is considered complete.

## 0.3.0 — 2026-07-12

- File **attachments**: drag & drop onto the chat or pick via the paperclip; 20 MB cap per file.
- Sidebar section switcher with three new panels:
  - **Skills** — grouped, filterable list with enable/disable toggles.
  - **Tasks** — scheduled cron jobs with run / pause / resume actions.
  - **Memory** — read-only agent memory, user profile, and soul files.

## 0.2.0 — 2026-07-12

- **Session search** (server-side with local-title fallback), pin/unpin and archive actions.
- New sessions can target any server-registered **workspace**.
- **Steer** an in-flight run from the composer.
- **Approval and clarification prompts** surface inline with respond controls.
- Tool-call notes carry the server's preview text.
- Block-level Markdown: headings, bullet/numbered lists, block quotes.
- Chat stream reconnects once on transport drop and replays missed events.
- Settings window with connection status, version, and project links.

## 0.1.0 — 2026-07-12

- Initial release: connect to a self-hosted hermes-webui server (password in Keychain),
  streaming chat over SSE with reasoning and tool notes, sessions sidebar
  (create/rename/delete), model picker, ad-hoc-signed universal `.app` published as
  `.dmg`/`.zip` via GitHub Actions.
