# LZT Balance Widget — Crypto Rates in Panel

**Date:** 2026-05-29
**Status:** Approved (design)

## Goal

Extend the existing LZT Market Balance plasmoid so the panel shows, next to the
balance/hold, a configurable list of crypto rates — each coin in its own
currency and its own text color. Match the single unified style (same font
size as the balance). All data comes from the Lolzteam Market `/currency`
endpoint we already fetch. The third-party crypto-tracker plasmoid in the
parent folder is used **only as a reference pattern — never modified**.

## Key insight: no new networking

`parseBatchResponse()` already stores every rate from `/currency` into
`root.currencyRates` (RUB per unit, for every code with `rate > 0`), including
BTC/ETH/XMR/etc. So a coin's price in any currency is pure math:

```
price(code, currency) = currencyRates[code] / currencyRates[currency]
```

For `currency == "RUB"` the divisor is `1`. No extra request is needed; the
panel re-renders whenever the existing refresh timer updates `currencyRates`.

## Supported coins (17)

Defined by the icon set in `icons.ts`: BTC, ETH, LTC, TRX, DASH, BCH, USDT,
BNB, TON, XMR, USDC, DAI, POL, MATIC, SOL, AVAX, SHIB. All 17 have a rate in
`/currency`. MATIC reuses POL's icon. DOGE is excluded (has a rate, but no icon
in `icons.ts`); it can be added later if an icon is supplied.

## Per-coin display currencies (8)

Same shortlist as the balance display currency:
RUB, USD, EUR, UAH, GBP, BYN, KZT, BTC. Currency symbol is rendered after the
number (e.g. `73328$`), matching the balance style. Reuses the existing
`root.currencySymbols` map.

## Data model & persistence

New config entry in `package/contents/config/main.xml`:

```xml
<entry name="cryptoList" type="String">
    <default>[]</default>
</entry>
```

Value is a JSON array, each element:

```json
{ "code": "BTC", "currency": "USD", "color": "#FFFFFF" }
```

**Default is empty** (`[]`) — out of the box the widget shows only the balance;
the user adds coins themselves. This mirrors the crypto-tracker's proven
"store the ticker list as a JSON string" approach.

## Config UI

`package/contents/config/config.qml` gets two categories:

- **LZT** — the current `General.qml` page (category renamed General → LZT;
  file renamed `General.qml` → `LZT.qml`).
- **CRYPTO** — new `config/Crypto.qml`.

`Crypto.qml` mirrors the crypto-tracker's `Exchanges.qml` editor:

- A `ListView` of the chosen coins (icon + code + currency + color swatch).
- Buttons: **Add / Edit / Remove / Move Up / Move Down**.
- An edit `Dialog` with: coin `ComboBox` (icon + name, 17 options), currency
  `ComboBox` (the 8 options), and a color picker (swatch button + `ColorDialog`).
- A hidden `Text` holds the serialized JSON (`cfg_cryptoList`); a `ListModel`
  mirrors it; every mutation re-serializes via `saveCryptoList()`.

## Panel rendering (compact representation)

Current `contentRow`: `[lolz icon] [balance] / [hold]`.

Appended after the hold:

1. **Separator** — a thin vertical `Rectangle` (~1–2px wide, height ≈ icon
   size, subtle gray), visible only when ≥1 coin is configured.
2. A `Repeater` over the parsed `cryptoEntries`. Each delegate:
   `[coin icon (iconSizes.smallMedium, same as lolz logo)] [price + symbol]`.
   - Price text: same `font.pixelSize` and `font.bold` as the balance (unified
     size), `color` = the entry's own color.
   - Coin icons keep their brand colors.

Root gets `property var cryptoEntries` parsed from
`Plasmoid.configuration.cryptoList`, refreshed via a `Connections`
`onCryptoListChanged` handler.

## Number formatting

A dedicated `formatRate(v)` (separate from the balance `formatNumber`):

- `v >= 1000` → integer (`73328`)
- `1 <= v < 1000` → 1–2 decimals
- `v < 1` → significant digits (e.g. `toPrecision(4)`, trailing zeros trimmed) —
  needed for SHIB-class values
- rate not yet loaded / missing → `…`

## Testable logic (TDD)

The bug-prone pure math is extracted into `package/contents/ui/rates.js`:

- `convert(rates, code, currency)` — returns the converted price, or `null`
  if either rate is missing/zero.
- `formatRate(v)` — the formatting rules above.
- `parseCryptoList(str)` — safe JSON parse → array (returns `[]` on bad input).

The file ends with a `if (typeof module !== 'undefined') module.exports = {...}`
guard so it is importable both by QML (`import "rates.js" as Rates`) and by a
Node test (`tests/rates.test.js`). Tests are written first (TDD) and cover:
large/mid/small/sub-1 values, missing rate, RUB passthrough, bad JSON.

QML rendering is verified manually via local install + screenshot.

## Out of scope / known limitations

- **Vertical panels**: the crypto row stays horizontal. Target is a horizontal
  panel (as in the user's screenshots). Documented as a known limitation.
- The third-party crypto-tracker is **not touched**.

## Misc

- Bump `metadata.json` version `3.2.0` → `3.3.0`.
- Update `README.md` features list with the crypto rates.
- Git: work happens in `lzt-balance-widget` (repo `9sx77ssl/lzt-plasma`).
  Install locally via `install.sh` (auto-detects the local clone). **No push**
  until the user asks.
