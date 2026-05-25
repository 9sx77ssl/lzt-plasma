<div align="center">

<img src="package/contents/ui/images/lolzteam.svg" width="80" height="80" alt="LZT" />

# LZT Market Balance

**KDE Plasma 6 widget** that shows your [Lolzteam Market](https://lzt.market) balance in the panel and lets you send money with one click.

![Plasma 6](https://img.shields.io/badge/Plasma-6.0+-2BAD72?style=flat-square)
![Qt](https://img.shields.io/badge/Qt-6-2BAD72?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-2BAD72?style=flat-square)

</div>

---

## Features

- **Live balance + hold** displayed in the panel: `1451₽ / 10₽`
- **Currency conversion** by Lolzteam's own forum rates (RUB, USD, EUR, UAH, GBP, BYN, KZT, BTC)
- **One-click money transfer** dialog
  - Send by **User ID** or **Username**
  - Pick transfer currency (RUB or USD) independently from display currency
  - Optional comment
- **Auto-refresh** every N seconds — balance and rates fetched in a single request
- **Auto-fallback** to the backup API server on network or server errors
- **Native Plasma 6 dialog** themed in LZT brand colors

## Install

One-line installer (always pulls latest):

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

The installer detects your distro automatically (Arch / Debian / Ubuntu / Fedora / openSUSE / Gentoo / RHEL and derivatives) and installs the required Plasma packages.

If the widget doesn't appear immediately, restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Then right-click the panel → **Add Widgets** → search **"LZT Market Balance"**.

## Setup

Right-click the widget → **Configure** and fill in:

| Setting | Description |
|---|---|
| **API Key** | Your LZT Bearer token. Get one at [lolz.live/account/api](https://lolz.live/account/api) — requires `market` scope |
| **API Server** | `prod-api.lzt.market` by default. Falls back automatically to `api.lzt.market` if the primary fails |
| **Refresh interval** | How often to check the balance, in seconds (default 30) |
| **Display currency** | Currency shown in the panel. The widget converts using live forum rates |

## Usage

- **Left-click** the widget → opens the Transfer dialog
- **Right-click** the widget → context menu (Transfer / Refresh / Configure / Remove)
- **Click outside** the dialog → closes and resets the form

## Privacy & Safety

- The widget talks **only** to `*.lzt.market` — no telemetry, no third-party calls
- Your API token is stored in Plasma's local config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) and is never transmitted anywhere except to the LZT API
- All requests use HTTPS
- Transfers retry on the backup server only for infrastructure errors (5xx, timeout, network drop) — never on errors that might mean the first transfer already succeeded, so duplicate transfers are not possible

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## License

[MIT](LICENSE) © [gay1234](https://lolz.live/gay1234)
