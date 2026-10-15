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
- **Five crypto providers** — LZT itself, CoinGecko, Binance, Kraken and Coinbase (the last three need **no key**)
- **Currency conversion** by Lolzteam's own forum rates (RUB, USD, EUR, UAH, BTC)
- **One-click money transfer** dialog — by **User ID** or **Username**, pick currency, optional comment
- **Fast & gentle** — balance + rates arrive via two parallel `GET`s (no `/batch` POST), every N seconds
- **Resilient** — keeps showing the last known balance & rates if the API hiccups, backing off exponentially
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
| **API Server** | `api.lzt.market` |
| **Refresh interval** | Seconds between updates (default 30) |
| **Display currency** | Currency for the balance in the panel |

### CRYPTO tab

- **Add** a coin → pick the coin and the currency to price it in.
- **Edit / Remove**, reorder with **↑ / ↓**.
- **Sort by price** button orders coins by their USD price — first click expensive→cheap, next click cheap→expensive.
- Coins appear in the panel after a separator: `1451₽ / 10₽ │ ₿ 73 595$  Ⓜ 387$`

**Supported coins:** BTC · ETH · BNB · XMR · BCH · SOL · LTC · DASH · AVAX · GRAM · USDC · DAI · USDT · TRX · POL · MATIC · SHIB

### Crypto providers

| Provider | Key needed | Coins covered |
|---|---|---|
| **LZT Market** | LZT token | all 17 |
| **CoinGecko** | free Demo key recommended | all 17 |
| **Binance** | none | all except XMR & DAI |
| **Kraken** | none | all except MATIC |
| **Coinbase** | none | all except XMR & TRX |

Coins a provider doesn't list are simply **hidden in the panel** while that provider is selected (the icon set is fixed, so the widget never invents new coins); the CRYPTO tab dims them with a *"not on …"* hint. Binance and Kraken are priced in USD/USDT and converted with LZT's own RUB/EUR/UAH rates — or, when there's no LZT token, a free keyless `open.er-api.com` snapshot.

### CoinGecko

Set **Crypto provider** to *CoinGecko* (LZT tab) to price coins with live CoinGecko data instead of LZT's own rates. CoinGecko's *keyless* API is rate-limited **per IP and shared with everyone on that IP**, so it often returns `403` / `429` on busy or shared connections. A **free Demo API key** ([coingecko.com/en/developers/dashboard](https://www.coingecko.com/en/developers/dashboard)) raises the limit to 100 calls/min — paste it into **CoinGecko API key** in the LZT tab (stored obfuscated, sent as `x-cg-demo-api-key`).

## Usage

- **Left-click** → Transfer dialog
- **Right-click** → Transfer / Refresh / Configure / Remove
- **Refresh** updates the balance and every crypto rate at once

## How it works

Every refresh fires two **independent `GET`s in parallel** — `/currency` and `/me` — instead of one `POST /batch`. That's cheaper (a batch fans out to three upstream calls and the POST is capped at 30/min) and far less likely to be rate-limited. The balance, hold and all crypto rates then arrive together, and crypto prices are computed locally from those rates (`coin ÷ currency`), so adding coins costs **zero** extra requests. When the crypto provider isn't *LZT*, one extra request pulls the coin prices (CoinGecko / Binance / Kraken / Coinbase; Binance & Kraken also fetch a free fiat anchor when needed). Failed fetches use **exponential backoff** (3s, 6s, 12s … capped at 5 min, with jitter) and honor the server's `Retry-After` header, so a rate-limited API is never hammered.

## Privacy & safety

- Talks to `api.lzt.market` over HTTPS. Depending on the crypto provider it may also query `api.coingecko.com`, `api.binance.com`, `api.kraken.com`, `api.coinbase.com`, and (only when there's no LZT token) `open.er-api.com` for fiat anchors. No telemetry.
- Transfers go **only** to `api.lzt.market`. They retry on network/5xx errors only, never on errors that could mean the first attempt already went through — so no double-sends.
- The API token is stored **obfuscated** (not as plain text) in Plasma's per-user config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`) and sent only to the LZT API. Note: this is obfuscation, not encryption — a local widget must decode the token to use it, so the key lives in the code. It stops casual reading of the config file; for true at-rest security use a system keyring.
- Transfers retry on the backup server **only** for infrastructure errors (5xx / timeout / network drop), never on errors that could mean the first attempt already went through — so no double-sends.

## Develop

Pure QML/JS — no build step. Iterate locally with `./install.sh` (it detects the clone and upgrades in place, then restarts plasmashell).

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## License

[MIT](LICENSE) © [gay1234](https://lolz.live/gay1234)
