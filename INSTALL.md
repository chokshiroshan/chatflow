# ChatFlow — Install Guide

## Installation (one-time Terminal step)

Since ChatFlow is not yet signed with an Apple certificate, macOS will block it on first launch.

Open **Terminal** (Cmd+Space → type "Terminal" → Enter) and paste this:

```
xattr -cr ~/Downloads/ChatFlow* && open ~/Downloads/ChatFlow.dmg
```

Then double-click **Install.command** in the DMG window.

This is a one-time step. After installation, ChatFlow opens normally every time.

## What you'll see after installing

1. **Onboarding** — ChatGPT sign in, microphone permission, shortcut setup
2. **Menu bar icon** — a small waveform icon appears in your menu bar
3. **Hold Ctrl+Space** anywhere to start dictating

## Uninstall

Download the DMG again and double-click **Uninstall.command**, or delete:
- `/Applications/ChatFlow.app`
- `~/Library/Application Support/ChatFlow`

## Need help?

Send logs from Settings → About → Export Logs
