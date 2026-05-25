# LZT Market Balance — KDE Plasma 6 Widget

Plasmoid that shows your [Lolzteam Market](https://lzt.market) balance in the panel, with quick money transfers.

![Plasma 6](https://img.shields.io/badge/Plasma-6.0+-blue) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Live balance** in the panel, auto-refreshes every N seconds
- **Hold display** next to the balance (e.g. `1455₽ · 10₽` when funds are on hold)
- **Currency conversion** by Lolzteam forum rates (RUB, USD, EUR, UAH, GBP, BYN, KZT, BTC)
- **Batch API** — balance + currency rates fetched in a single `POST /batch` request
- **Money transfer** via right-click → Transfer Money, or left-click on the widget
  - Independent transfer currency (RUB / USD), not tied to display currency
  - By User ID or by Username
  - Optional comment (max 255 chars)
  - Amount limit: 10 000 000
  - **Auto-fallback** on backup API server for 5xx / timeout / network errors
- **Fallback API server** if primary fails (also for balance refresh)
- **Native Plasma 6 dialog** with brand-themed UI (LZT green `#2BAD72`)
- **Form auto-reset** when the dialog is closed
- **Silent background updates**, no UI flicker
- **Native Plasma config** dialog (right-click → Configure)

## Install

One-line install (always latest):

```bash
sh -c "$(curl -sS https://raw.githubusercontent.com/9sx77ssl/lzt-plasma/main/install.sh)"
```

Or manual:

```bash
git clone https://github.com/9sx77ssl/lzt-plasma.git
cd lzt-plasma
chmod +x install.sh
./install.sh
```

Restart Plasma (if widget doesn't appear):

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Then: right-click panel → Add Widgets → search **"LZT Market Balance"**.

## Settings

Right-click the widget → Configure:

| Setting | Description |
|---------|-------------|
| **API Key** | Your LZT Bearer token. Get at [lolz.live/account/api](https://lolz.live/account/api) — needs `market` scope |
| **API Server** | `prod-api.lzt.market` (default) or `api.lzt.market` (alternative). Auto-fallback on errors |
| **Refresh interval** | Seconds between balance/currency updates (default 30, min 10) |
| **Display currency** | Currency shown in panel. Balance is converted by forum rates |

## Usage

- **Left-click** widget → opens Transfer dialog
- **Right-click** widget → context menu (Transfer / Refresh / Configure / Remove)
- **Click outside** dialog → closes & resets form

## How transfers work

1. Enter amount (validated 0.01 – 10 000 000)
2. Pick currency (RUB or USD)
3. Choose recipient by **User ID** or by **Username**
4. Optional comment
5. Hit **Send** — request goes to your configured API server
6. On 5xx server errors, timeout, or network failure → auto-retries once on the backup API server
7. On success: balance refreshes and form clears

4xx errors (401 Bad Token, 429 Rate Limit, validation errors) are NOT retried — these would fail the same way on the backup server, and retrying could mask real auth issues.

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## Brand palette

The dialog uses the official LZT forum color scheme:

| Color | Hex | Usage |
|-------|-----|-------|
| Green | `#2BAD72` | Active buttons, accents, balance text |
| Red | `#884444` | Errors |
| White | `#FFFFFF` | Primary text |
| Dialog BG | `#1A1A1A` | Dialog background |
| Card/Field | `#272727` | Header card, input fields, inactive buttons |
| Border | `#363636` | Default borders |
| Asphalt | `#505050` | Placeholders |

## Tech

- QML / Qt 6 / KF6
- `XMLHttpRequest` for API calls
- `PlasmaCore.Dialog` for the native popup
- Standard Plasma 6 sizing pattern (`Layout.fillHeight`/`fillWidth` based on `formFactor`)

## Author

[gay1234](https://lolz.live/gay1234)

## License

MIT
