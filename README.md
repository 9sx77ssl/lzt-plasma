<div align="center">

<img src="package/contents/ui/images/lolzteam.svg" width="80" height="80" alt="LZT" />

# LZT Plasmoid

**Your [Lolzteam Market](https://lzt.market) balance & crypto rates, live in your KDE panel — straight from the LZT API. >.<**

![Plasma 6](https://img.shields.io/badge/Plasma-6.0+-2BAD72?style=flat-square)
![Qt](https://img.shields.io/badge/Qt-6-2BAD72?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-2BAD72?style=flat-square)

</div>

---

## Features

- **Live balance + hold** in the panel: `1451₽ / 10₽`
- **Crypto rates** next to your balance — add any of 17 coins, each shown in **its own currency**, sortable by price
- **Currency conversion** by Lolzteam's own forum rates (RUB, USD, EUR, UAH, GBP, BYN, KZT, BTC)
- **One-click money transfer** dialog — by **User ID** or **Username**, pick currency, optional comment
- **One request, everything** — balance + all rates come from a single batched call every N seconds
- **Resilient** — keeps showing the last known balance & rates if the API hiccups, and auto-falls back to the backup server
- **Desktop notifications** on balance changes
- **Native Plasma 6** look, themed in LZT green `#2BAD72`

## Install

One-liner (always pulls latest):

```bash
sh -c "$(curl -sS https://raw.githubusercontent.com/9sx77ssl/lzt-plasma/main/install.sh)"
```

Manual:

```bash
git clone https://github.com/9sx77ssl/lzt-plasma.git
cd lzt-plasma
./install.sh
```

The installer auto-detects your distro (Arch / Debian / Ubuntu / Fedora / openSUSE / Gentoo / RHEL & derivatives) and pulls the needed Plasma 6 packages. If the widget doesn't show up right away:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Then right-click your panel → **Add Widgets** → search **"LZT Plasmoid"**.

## Configure

Right-click the widget → **Configure**:

### LZT tab

| Setting | What it does |
|---|---|
| **API Key** | Your LZT Bearer token — [lolz.live/account/api](https://lolz.live/account/api), `market` scope |
| **API Server** | `prod-api.lzt.market` by default; auto-falls back to `api.lzt.market` |
| **Refresh interval** | Seconds between updates (default 30) |
| **Display currency** | Currency for the balance in the panel |

### CRYPTO tab

- **Add** a coin → pick the coin and the currency to price it in.
- **Edit / Remove**, reorder with **↑ / ↓**.
- **Sort by price** button orders coins by their USD price — first click expensive→cheap, next click cheap→expensive.
- Coins appear in the panel after a separator: `1451₽ / 10₽ │ ₿ 73 595$  Ⓜ 387$`

**Supported coins:** BTC · ETH · BNB · XMR · BCH · SOL · LTC · DASH · AVAX · TON · USDC · DAI · USDT · TRX · POL · MATIC · SHIB

## Usage

- **Left-click** → Transfer dialog
- **Right-click** → Transfer / Refresh / Configure / Remove
- **Refresh** updates the balance and every crypto rate at once

## How it works

Every refresh sends a single `POST /batch` with two jobs — `/currency` and `/me` — so the balance, hold, and all crypto rates arrive together. Crypto prices are computed locally from those rates (`coin ÷ currency`), so adding coins costs **zero** extra requests. If a refresh fails (offline, 5xx, timeout), the last good values stay on screen and the next tick retries on the backup server.

## Privacy & safety

- Talks **only** to `*.lzt.market` over HTTPS — no telemetry, no third-party calls.
- The API token is stored in Plasma's per-user config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) and sent only to the LZT API. It is not encrypted at rest (standard for Plasma widgets) — treat that file as private.
- Transfers retry on the backup server **only** for infrastructure errors (5xx / timeout / network drop), never on errors that could mean the first attempt already went through — so no double-sends.

## Develop

Logic helpers are unit-tested with plain Node:

```bash
node tests/rates.test.js
```

The widget is pure QML/JS — no build step. Iterate locally with `./install.sh` (it detects the clone and upgrades in place).

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## License

[MIT](LICENSE) © [gay1234](https://lolz.live/gay1234)
