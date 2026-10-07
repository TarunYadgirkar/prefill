# Prefill

Prefill remembers your emails, phone numbers, addresses, profile links and answers to common form questions, and offers the right one when you click a field.

- **iPhone (Safari):** click a field and Prefill's list shows your values, best first, each saying why it's there. What you pick comes first on that site next time. Fill form fills a whole application when you want it.
- **iPhone app:** an Inbox of what Prefill learned, and a searchable You tab with everything it knows and where each value was used.
- **Mac:** a menu bar app that suggests in any app (Chrome, Arc, Safari and others) through Accessibility. There's also an optional Chrome/Arc extension that saves new values you type.
- **Sync:** everything lives in iCloud Contacts, so the iPhone and Mac stay in step with no server and no paid developer account.

Read [docs/PRODUCT.md](docs/PRODUCT.md) for the full picture: what it was built to do, how it works, and how it was built. Read [AGENTS.md](AGENTS.md) before changing code.

## Install

These steps need Xcode 27, pnpm and xcodegen; `scripts/bootstrap.sh` checks for them.

**iPhone.** Plug the phone in, unlock it, then run:

```bash
zsh scripts/install-device.sh <device-udid>
```

On the iPhone:
1. Trust the developer profile in Settings → General → VPN & Device Management.
2. Turn on the Prefill extension in Settings → Apps → Safari → Extensions, and set All Websites to Allow.

A free Apple ID signs the app for 7 days only, so rerun the script weekly, or let the Mac do it.

### Weekly reinstall

```bash
zsh scripts/auto-reinstall.sh --force        # once, by hand: click Always Allow on keychain prompts
zsh scripts/install-auto-reinstall.sh        # then a launchd agent checks daily at 12:15
```

The agent reinstalls when the last install is 5.5 days old or its profile expires within 36 hours, and retries every 10 minutes for 3 hours while the phone is locked or away. It posts a notification either way. The log is in `~/Library/Logs/Prefill/auto-reinstall.log`. Leave the phone plugged in or on the same Wi-Fi, and keep the repo out of Desktop, Documents and iCloud Drive (launchd jobs can't read those). Pass a device ID to either script to target another phone; `--uninstall` removes the agent.

**Mac.**

```bash
zsh scripts/install-mac.sh
```

Then:
1. Allow Contacts from the Prefill menu.
2. Turn Prefill on in System Settings → Privacy & Security → Accessibility.
3. Optional: load the extension unpacked in `chrome://extensions` and `arc://extensions` (Developer mode → Load unpacked) from `/Applications/Prefill.app/Contents/Resources/ChromeExtension`. The `Chrome Extension` shortcut in the repo root points there. After each reinstall, click Reload on it in each browser.

## Develop

```bash
zsh scripts/build.sh
zsh scripts/test.sh unit
pnpm --dir web test
```

`scripts/test.sh e2e` runs the simulator end-to-end tests. `scripts/e2e-mac-chrome.sh` and `scripts/e2e-mac-ax.sh` cover the Mac.
