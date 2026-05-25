<div align="center">

<img src="package/contents/ui/images/lolzteam.svg" width="80" height="80" alt="LZT" />

# LZT Market Balance

**KDE Plasma 6 widget** — live Lolzteam Market balance in your panel, with one-click money transfers.

![Plasma 6](https://img.shields.io/badge/Plasma-6.0+-2BAD72?style=flat-square)
![Qt](https://img.shields.io/badge/Qt-6-2BAD72?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-2BAD72?style=flat-square)

</div>

---

## Features

- **Live balance + hold** in the panel — `1451₽ / 10₽` format, hold same size as balance with grey divider
- **Smart number formatting** — `10` for integers, `10.5` for fractions, extra precision for crypto (`<1`)
- **Currency conversion** by Lolzteam's own forum rates (RUB / USD / EUR / UAH / GBP / BYN / KZT / BTC)
- **Both balance and hold** convert to the selected display currency
- **Batch API** — `/me` and `/currency` fetched in a single `POST /batch` request per refresh
- **Native Plasma 6 transfer dialog**
  - Left-click on the widget, or right-click → Transfer Money
  - Independent transfer currency selector (RUB / USD)
  - Send by **User ID** or **Username**
  - Optional comment, max 255 chars
  - Amount validated 0.01 – 10 000 000
  - Form auto-resets when closed
- **Auto-fallback API server** on `/balance/transfer` for 5xx / timeout / network errors
- **Auto-fallback API server** on `/batch` for the same errors
- **Brand-themed UI** in the Lolzteam palette (`#2BAD72`, `#0d0d0d`, `#161616`, `#262626`)
- **Native Plasma sizing** — uses the same `formFactor` state pattern as `digital-clock` upstream

## Install

One-line install (always pulls latest from `main`):

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

The installer detects your distro (Arch, Debian, Ubuntu, Fedora, RHEL, openSUSE, Gentoo) and installs the required Plasma packages.

Restart Plasma if the widget doesn't immediately appear:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Then: right-click the panel → **Add Widgets** → search **"LZT Market Balance"**.

## Settings

Right-click the widget → **Configure**:

| Setting | Default | Description |
|---|---|---|
| API Key | _empty_ | Your LZT Bearer token from [lolz.live/account/api](https://lolz.live/account/api) (requires `market` scope) |
| API Server | `prod-api.lzt.market` | Primary endpoint. Falls back to `api.lzt.market` automatically on errors |
| Refresh interval | `30` sec | Single interval for both balance and currency rates (min 10, max 3600) |
| Display currency | `RUB` | Currency shown in the panel. Conversion uses live forum rates |

## Usage

- **Left-click** the widget → opens the Transfer dialog
- **Right-click** the widget → context menu (Transfer / Refresh / Configure / Remove)
- **Click outside** the dialog → closes and resets the form

## Architecture

```
Panel widget  (compactRepresentation = MouseArea)
    [SVG icon]   1451₽   /   10₽
                       │
                       │  left-click  /  right-click → Transfer Money
                       ▼
PlasmaCore.Dialog  (NoBackground, radius 12)
    Header card
        [icon]  Transfer                       1451 ₽
                                              hold 10 ₽
    Amount field                                  ₽
    Currency picker        [ ₽ RUB ]   [ $ USD ]
    Recipient mode         [ By ID ]   [ By Username ]
    Recipient input        User ID / Username
    Comment input          optional, max 255 chars
    Status pill            success (green)  /  error (red)
    Send button            full-width, green
```

## Security

| Layer | Implementation |
|---|---|
| Transport | HTTPS only (no plain HTTP endpoints) |
| API token | Stored in Plasma's standard config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`, mode 600 by the user) |
| Token in UI | Settings field uses `echoMode: TextInput.Password` |
| Input validation | Amount: `DoubleValidator 0.01 – 10 000 000`. User ID: `parseInt(_, 10)` + NaN/<=0 check. Username: trim. Comment: `maximumLength: 255` |
| Request body | All values go through `JSON.stringify` (auto-escapes) — no string concatenation, no injection vectors |
| Transfer retry | Only retries on **infrastructure errors** (5xx, timeout, network). Never retries 4xx errors that might mean the first request was processed — prevents duplicate transfers |
| Error messages | Server error messages displayed verbatim, but limited to the `errors[0]` field; no raw HTML or response bodies rendered |
| Third-party calls | Zero. Talks only to `*.lzt.market` |

## Future feature ideas

Based on [LZT Market API](https://lzt-market.readme.io/reference) and [LZT Forum API](https://lolzteam.readme.io/reference), the following extensions are technically possible without changing the architecture:

### Market API additions

1. **Sub-balance breakdown** — `/me` already returns `balances[]` (merchant, account, custom wallets). Could be shown in an expandable section below the main balance
2. **Active listings counter** — `/me.active_items_count` → badge on the widget icon
3. **Sold items counter** — `/me.sold_items_count`
4. **Recent payments** — `GET /payments?type=in/out` to show the last few incoming/outgoing transactions in the dialog
5. **Payout history** — `GET /payouts` for withdrawal status tracking
6. **My listings** — quick list of currently published items with prices
7. **Item search** — small search box that opens results in browser

### Forum API additions

1. **Unread DM badge** — `GET /conversations` → small red dot on the icon when `unread_count > 0`
2. **Reputation counter** — `like_count`, `like2_count` in an expanded view
3. **Notifications feed** — last 5 site notifications, click to open in browser
4. **Forum thread bookmarks** — quick links to subscribed threads

### UX improvements

1. **Balance trend** — small arrow `▲ +12₽` / `▼ -8₽` showing delta since last refresh
2. **Threshold alert** — desktop notification when balance drops below a configured amount
3. **Copy-to-clipboard** on click of the panel balance
4. **Quick links** — submenu with "Open profile", "Open market", "Top up" links
5. **Sub-balances popup** — expandable section showing each individual wallet

## Brand palette

```
#2BAD72  Green     active buttons, balance, accent
#884444  Red       errors
#FFFFFF  White     primary text
#0D0D0D  Dialog    dialog background (deepest)
#161616  Card      card / field background
#262626  Border    subtle borders
#404040  Divider   panel separators
#707070  Subtle    hold text, dim labels
```

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## Tech stack

- **QML** (Qt 6.5+) — UI
- **KF6** — `kirigami`, `plasma-framework`
- **JavaScript** — API client logic
- **XMLHttpRequest** — HTTP transport
- **No external runtime dependencies** beyond stock Plasma 6

## Contributing

PRs welcome. The whole widget is one `main.qml` (~600 lines), one `main.xml` config schema, one `General.qml` config UI, and an `install.sh` for distro detection — easy to grok.

## License

[MIT](LICENSE) © [gay1234](https://lolz.live/gay1234)
