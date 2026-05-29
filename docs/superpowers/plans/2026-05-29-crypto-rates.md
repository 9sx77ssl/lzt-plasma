# Crypto Rates in Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a configurable list of crypto rates next to the LZT balance in the panel — each coin in its own currency and color, unified font size.

**Architecture:** Crypto rates already arrive in `root.currencyRates` from the existing `/currency` batch fetch, so this is pure rendering + config. A new `cryptoList` JSON config entry (default empty) drives a `Repeater` in the compact representation, after a vertical separator. A new CRYPTO config tab edits the list (Add/Edit/Remove/Up/Down). Conversion + formatting math lives in a Node-tested `rates.js`.

**Tech Stack:** QML (Plasma 6 / Qt 6), JavaScript, KConfig (kcfg), Node (tests only).

**Working dir:** `/home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget` (repo `9sx77ssl/lzt-plasma`, branch `feat/crypto-rates`). The crypto-tracker plasmoid in the Y7Plasma root is **reference only — never modified**.

---

## File structure

- Create: `package/contents/ui/rates.js` — pure `convert()`, `formatRate()`, `parseCryptoList()`.
- Create: `tests/rates.test.js` — Node assertions for `rates.js`.
- Create: `package/contents/ui/images/crypto/*.svg` — 16 coin icons extracted from `icons.ts`.
- Create: `package/contents/ui/config/Crypto.qml` — CRYPTO tab list editor.
- Rename: `package/contents/ui/config/General.qml` → `LZT.qml` (unchanged content).
- Modify: `package/contents/config/config.qml` — two categories (LZT + CRYPTO).
- Modify: `package/contents/config/main.xml` — add `cryptoList` entry.
- Modify: `package/contents/ui/main.qml` — import rates.js, `cryptoEntries`, separator + Repeater.
- Modify: `package/metadata.json` — version 3.2.0 → 3.3.0.
- Modify: `README.md` — features bullet.

---

## Task 1: rates.js pure logic (TDD)

**Files:**
- Create: `package/contents/ui/rates.js`
- Test: `tests/rates.test.js`

- [ ] **Step 1: Write the failing test**

Create `tests/rates.test.js`:

```js
const assert = require('assert')
const { convert, formatRate, parseCryptoList } = require('../package/contents/ui/rates.js')

// ── convert(rates, code, currency) ────────────────────────────────
const rates = { BTC: 5218725.85339486, USD: 70.91026973, RUB: 1, ETH: 142928.24 }
assert.ok(Math.abs(convert(rates, 'BTC', 'USD') - 73595.0) < 1, 'BTC in USD ≈ 73595')
assert.strictEqual(convert(rates, 'BTC', 'RUB'), 5218725.85339486, 'RUB passthrough = base rate')
assert.strictEqual(convert(rates, 'DOGE', 'USD'), null, 'missing base -> null')
assert.strictEqual(convert(rates, 'BTC', 'XXX'), null, 'missing quote -> null')
assert.strictEqual(convert(null, 'BTC', 'USD'), null, 'no rates -> null')
assert.strictEqual(convert({ BTC: 100, USD: 0 }, 'BTC', 'USD'), null, 'zero quote -> null')

// ── formatRate(v) ─────────────────────────────────────────────────
assert.strictEqual(formatRate(73595.06), '73595', 'large -> integer')
assert.strictEqual(formatRate(2007.4),   '2007',  'large -> integer')
assert.strictEqual(formatRate(382),      '382',   'mid whole -> integer')
assert.strictEqual(formatRate(2.4562),   '2.46',  'mid -> 2 decimals')
assert.strictEqual(formatRate(1),        '1',     'one -> 1')
assert.strictEqual(formatRate(0.5),      '0.5',   'sub-1 -> sig figs')
assert.strictEqual(formatRate(0.0042),   '0.0042','small sub-1 -> sig figs')
assert.strictEqual(formatRate(null),     '…',     'null -> ellipsis')
assert.strictEqual(formatRate(0),        '…',     'zero -> ellipsis')
assert.strictEqual(formatRate(NaN),      '…',     'NaN -> ellipsis')
assert.strictEqual(formatRate(-3),       '…',     'negative -> ellipsis')

// ── parseCryptoList(str) ──────────────────────────────────────────
assert.deepStrictEqual(parseCryptoList(''),            [], 'empty string -> []')
assert.deepStrictEqual(parseCryptoList('[]'),          [], '[] -> []')
assert.deepStrictEqual(parseCryptoList('not json'),    [], 'garbage -> []')
assert.deepStrictEqual(parseCryptoList('{"a":1}'),     [], 'object -> []')
assert.deepStrictEqual(parseCryptoList('[{"code":"BTC"}]'), [{ code: 'BTC' }], 'array preserved')

console.log('all rates.js tests passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && node tests/rates.test.js`
Expected: FAIL — `Cannot find module '../package/contents/ui/rates.js'`.

- [ ] **Step 3: Write minimal implementation**

Create `package/contents/ui/rates.js`:

```js
// Pure helpers for crypto-rate display.
// Importable by QML (import "rates.js" as Rates) and by Node tests
// (the module.exports guard at the bottom — `module` is undefined in QML).

// Coin price in a target currency. rates = code -> RUB-per-unit (from /currency).
// Returns null when either rate is missing or non-positive (caller shows a placeholder).
function convert(rates, code, currency) {
    if (!rates) return null
    var base  = rates[code]
    var quote = (currency === "RUB") ? 1 : rates[currency]
    if (!base  || base  <= 0) return null
    if (!quote || quote <= 0) return null
    return base / quote
}

// Trim trailing zeros (and a dangling dot) from a decimal string.
function trimZeros(s) {
    if (s.indexOf(".") === -1) return s
    return s.replace(/\.?0+$/, "")
}

// Format a converted rate for the panel:
//   >= 1000     -> integer            (73328)
//   1 .. 1000   -> up to 2 decimals   (2.46 / 382)
//   0 .. 1      -> 4 significant figs  (0.0042) — needed for SHIB-class values
//   null/NaN/<=0 -> "…"
function formatRate(v) {
    if (v === null || v === undefined || isNaN(v) || v <= 0) return "…"
    if (v >= 1000) return String(Math.round(v))
    if (v >= 1) {
        var r = Math.round(v * 100) / 100
        if (Math.abs(r - Math.round(r)) < 0.005) return String(Math.round(r))
        return trimZeros(r.toFixed(2))
    }
    return trimZeros(v.toPrecision(4))
}

// Safe parse of the cryptoList config string -> array (always an array).
function parseCryptoList(str) {
    if (!str) return []
    try {
        var arr = JSON.parse(str)
        return Array.isArray(arr) ? arr : []
    } catch (e) {
        return []
    }
}

if (typeof module !== 'undefined')
    module.exports = { convert: convert, formatRate: formatRate, parseCryptoList: parseCryptoList, trimZeros: trimZeros }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && node tests/rates.test.js`
Expected: PASS — `all rates.js tests passed`.

- [ ] **Step 5: Commit**

```bash
git add tests/rates.test.js package/contents/ui/rates.js
git commit -m "feat: rates.js — convert/formatRate/parseCryptoList with node tests"
```

---

## Task 2: Extract coin icons from icons.ts

**Files:**
- Create: `package/contents/ui/images/crypto/{btc,eth,ltc,trx,dash,bch,usdt,bnb,ton,xmr,usdc,dai,pol,sol,avax,shib}.svg`

- [ ] **Step 1: Run the one-off extractor**

The icon source `icons.ts` lives in the Y7Plasma root (two levels up). Run:

```bash
cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && python3 - <<'PY'
import re, os
src = open('/home/rsz/Desktop/Y7Plasma/icons.ts').read()
block = src.split('SVG_SOURCES: Record<string, string> = {', 1)[1].split('\n};', 1)[0]
out = 'package/contents/ui/images/crypto'
os.makedirs(out, exist_ok=True)
n = 0
for m in re.finditer(r'(\w+):\s*`(.*?)`', block, re.S):
    code, svg = m.group(1), m.group(2).strip()
    if not svg.startswith('<svg'): continue
    open(os.path.join(out, code.lower() + '.svg'), 'w').write(svg + '\n')
    n += 1
print('wrote', n, 'icons:', sorted(os.listdir(out)))
PY
```

Expected: `wrote 16 icons: [...]` listing avax.svg, bch.svg, bnb.svg, btc.svg, dai.svg, dash.svg, eth.svg, ltc.svg, pol.svg, shib.svg, sol.svg, ton.svg, trx.svg, usdc.svg, usdt.svg, xmr.svg.

- [ ] **Step 2: Sanity-check one icon renders as valid SVG**

Run: `head -c 60 package/contents/ui/images/crypto/btc.svg`
Expected: starts with `<svg xmlns="http://www.w3.org/2000/svg"`.

- [ ] **Step 3: Commit**

```bash
git add package/contents/ui/images/crypto
git commit -m "feat: bundle 16 crypto coin icons (extracted from icons.ts)"
```

---

## Task 3: Config entry + CRYPTO tab

**Files:**
- Modify: `package/contents/config/main.xml`
- Modify: `package/contents/config/config.qml`
- Rename: `package/contents/ui/config/General.qml` → `package/contents/ui/config/LZT.qml`
- Create: `package/contents/ui/config/Crypto.qml`

- [ ] **Step 1: Add the `cryptoList` entry to main.xml**

In `package/contents/config/main.xml`, inside `<group name="General">`, after the `apiServer` entry (before `</group>`), add:

```xml
        <entry name="cryptoList" type="String">
            <default>[]</default>
        </entry>
```

- [ ] **Step 2: Rename General.qml → LZT.qml**

```bash
git mv package/contents/ui/config/General.qml package/contents/ui/config/LZT.qml
```

(Content is unchanged — it still defines `cfg_apiKey`, `cfg_updateInterval`, `cfg_displayCurrency`, `cfg_apiServer`.)

- [ ] **Step 3: Update config.qml to two categories**

Replace the entire body of `package/contents/config/config.qml` with:

```qml
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("LZT")
        icon: "preferences-system"
        source: "config/LZT.qml"
    }
    ConfigCategory {
        name: i18n("CRYPTO")
        icon: "office-chart-line"
        source: "config/Crypto.qml"
    }
}
```

- [ ] **Step 4: Create Crypto.qml**

Create `package/contents/ui/config/Crypto.qml`:

```qml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: page
    Layout.fillWidth: true
    Layout.fillHeight: true

    // KConfig binding — the hidden Text below holds the serialized JSON.
    property alias cfg_cryptoList: serialized.text

    // Coins that have BOTH an icon and a /currency rate.
    readonly property var supportedCoins: [
        "BTC","ETH","BNB","XMR","BCH","SOL","LTC","DASH",
        "AVAX","TON","USDC","DAI","USDT","TRX","POL","MATIC","SHIB"
    ]
    // Same shortlist as the balance display currency.
    readonly property var currencyModel: [
        { text: "RUB  ₽",  value: "RUB" },
        { text: "USD  $",  value: "USD" },
        { text: "EUR  €",  value: "EUR" },
        { text: "UAH  ₴",  value: "UAH" },
        { text: "GBP  £",  value: "GBP" },
        { text: "BYN  Br", value: "BYN" },
        { text: "KZT  ₸",  value: "KZT" },
        { text: "BTC  ₿",  value: "BTC" }
    ]

    function iconSource(code) {
        var f = (code === "MATIC") ? "pol" : code.toLowerCase()
        return Qt.resolvedUrl("../images/crypto/" + f + ".svg")
    }

    // Serialized JSON <-> ListModel mirror (crypto-tracker pattern).
    Text {
        id: serialized
        visible: false
        onTextChanged: {
            coinsModel.clear()
            var arr = []
            try { arr = JSON.parse(serialized.text) } catch (e) { arr = [] }
            if (!Array.isArray(arr)) arr = []
            for (var i = 0; i < arr.length; i++) {
                coinsModel.append({
                    code:     arr[i].code     || "BTC",
                    currency: arr[i].currency || "USD",
                    color:    arr[i].color    || "#FFFFFF"
                })
            }
        }
    }

    ListModel { id: coinsModel }

    function saveCoins() {
        var out = []
        for (var i = 0; i < coinsModel.count; i++) {
            var it = coinsModel.get(i)
            out.push({ code: it.code, currency: it.currency, color: it.color })
        }
        serialized.text = JSON.stringify(out)
    }

    function currencyLabel(value) {
        for (var i = 0; i < currencyModel.length; i++)
            if (currencyModel[i].value === value) return currencyModel[i].text
        return value
    }

    // ── Edit dialog state ───────────────────────────────────────────
    property int    editIndex: -1
    property string editColor: "#FFFFFF"

    function openAdd() {
        editIndex = -1
        coinCombo.currentIndex = 0
        currencyCombo.currentIndex = 1   // USD
        editColor = "#FFFFFF"
        editDialog.open()
    }
    function openEdit(idx) {
        if (idx < 0 || idx >= coinsModel.count) return
        var it = coinsModel.get(idx)
        editIndex = idx
        coinCombo.currentIndex     = Math.max(0, supportedCoins.indexOf(it.code))
        currencyCombo.currentIndex = (function() {
            for (var i = 0; i < currencyModel.length; i++)
                if (currencyModel[i].value === it.currency) return i
            return 1
        })()
        editColor = it.color
        editDialog.open()
    }

    // ── Layout ──────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1

            ListView {
                id: coinsList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: coinsModel
                currentIndex: -1

                delegate: Rectangle {
                    width: coinsList.width
                    height: 38
                    color: ListView.isCurrentItem ? Kirigami.Theme.highlightColor
                         : (index % 2 === 0 ? Kirigami.Theme.backgroundColor : Kirigami.Theme.alternateBackgroundColor)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Image {
                            source: page.iconSource(model.code)
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            smooth: true; mipmap: true
                        }
                        PlasmaComponents.Label {
                            text: model.code
                            font.bold: true
                            Layout.preferredWidth: 70
                        }
                        PlasmaComponents.Label {
                            text: page.currencyLabel(model.currency)
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            width: 18; height: 18; radius: 3
                            color: model.color
                            border.color: Kirigami.Theme.disabledTextColor
                            border.width: 1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: coinsList.currentIndex = index
                        onDoubleClicked: { coinsList.currentIndex = index; page.openEdit(index) }
                    }
                }

                PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar { }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: coinsModel.count === 0
                    text: i18n("No coins yet — click Add")
                    opacity: 0.6
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: false

            PlasmaComponents.Button {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                text: i18n("Add"); icon.name: "list-add"
                onClicked: page.openAdd()
            }
            PlasmaComponents.Button {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                text: i18n("Edit"); icon.name: "edit-entry"
                enabled: coinsList.currentIndex >= 0 && coinsList.currentIndex < coinsModel.count
                onClicked: page.openEdit(coinsList.currentIndex)
            }
            PlasmaComponents.Button {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                text: i18n("Remove"); icon.name: "list-remove"
                enabled: coinsList.currentIndex >= 0 && coinsList.currentIndex < coinsModel.count
                onClicked: {
                    coinsModel.remove(coinsList.currentIndex)
                    page.saveCoins()
                }
            }
            PlasmaComponents.Button {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                text: i18n("Move Up"); icon.name: "arrow-up"
                enabled: coinsList.currentIndex > 0 && coinsList.currentIndex < coinsModel.count
                onClicked: {
                    var from = coinsList.currentIndex
                    coinsModel.move(from, from - 1, 1)
                    coinsList.currentIndex = from - 1
                    page.saveCoins()
                }
            }
            PlasmaComponents.Button {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                text: i18n("Move Down"); icon.name: "arrow-down"
                enabled: coinsList.currentIndex >= 0 && (coinsList.currentIndex + 1) < coinsModel.count
                onClicked: {
                    var from = coinsList.currentIndex
                    coinsModel.move(from, from + 1, 1)
                    coinsList.currentIndex = from + 1
                    page.saveCoins()
                }
            }
        }
    }

    // ── Add/Edit dialog ─────────────────────────────────────────────
    QQC2.Dialog {
        id: editDialog
        title: page.editIndex === -1 ? i18n("Add coin") : i18n("Edit coin")
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel

        onAccepted: {
            var obj = {
                code:     page.supportedCoins[coinCombo.currentIndex],
                currency: page.currencyModel[currencyCombo.currentIndex].value,
                color:    page.editColor
            }
            if (page.editIndex === -1) coinsModel.append(obj)
            else                       coinsModel.set(page.editIndex, obj)
            page.saveCoins()
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: coinCombo
                Layout.fillWidth: true
                model: page.supportedCoins
            }
            QQC2.ComboBox {
                id: currencyCombo
                Layout.fillWidth: true
                model: page.currencyModel
                textRole: "text"
            }
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: i18n("Color:") }
                Rectangle {
                    Layout.preferredWidth: 28; Layout.preferredHeight: 28
                    radius: 4
                    color: page.editColor
                    border.color: Kirigami.Theme.disabledTextColor
                    border.width: 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            colorDialog.selectedColor = page.editColor
                            colorDialog.open()
                        }
                    }
                }
                PlasmaComponents.Label { text: page.editColor; opacity: 0.7 }
                Item { Layout.fillWidth: true }
            }
        }
    }

    Dialogs.ColorDialog {
        id: colorDialog
        onAccepted: page.editColor = colorDialog.selectedColor.toString()
    }
}
```

- [ ] **Step 5: Validate QML syntax**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && qmllint package/contents/ui/config/Crypto.qml package/contents/config/config.qml 2>&1 | head -30 || true`
Expected: no hard syntax errors (import/type warnings for Plasma modules are acceptable — qmllint can't always resolve `org.kde.*` without the full plugin path). If it reports a genuine syntax error (unbalanced braces, bad property), fix it.

- [ ] **Step 6: Commit**

```bash
git add package/contents/config/main.xml package/contents/config/config.qml package/contents/ui/config
git commit -m "feat: CRYPTO config tab + cryptoList entry; rename General tab to LZT"
```

---

## Task 4: Render crypto rates in the panel

**Files:**
- Modify: `package/contents/ui/main.qml`

- [ ] **Step 1: Add the rates.js import**

In `package/contents/ui/main.qml`, after the last import line `import org.kde.notification`, add:

```qml
import "rates.js" as Rates
```

- [ ] **Step 2: Add the cryptoEntries property**

After the `currencySymbols` readonly property block (the `})` that closes it), add:

```qml
    // Parsed from Plasmoid.configuration.cryptoList; drives the panel Repeater.
    property var cryptoEntries: []
```

- [ ] **Step 3: Add the rebuild + display functions**

In the Logic section, after `function resetTransferForm() { ... }`, add:

```qml
    function rebuildCryptoEntries() {
        cryptoEntries = Rates.parseCryptoList(Plasmoid.configuration.cryptoList)
    }

    // Display string for one crypto entry, e.g. "73328$".
    function cryptoText(entry) {
        if (!hasFetchedOnce) return "…"
        var v = Rates.convert(currencyRates, entry.code, entry.currency)
        var sym = currencySymbols[entry.currency] || entry.currency
        return Rates.formatRate(v) + sym
    }
```

- [ ] **Step 4: Wire config + init**

In `Component.onCompleted`, after the existing `if (apiKey.length > 0) ...` line, add a call:

```qml
    Component.onCompleted: {
        rebuildCryptoEntries()
        if (apiKey.length > 0) fetchAll()
        else { statusText = "No API Key"; hasError = true }
    }
```

In the `Connections { target: Plasmoid.configuration ... }` block, add a handler:

```qml
        function onCryptoListChanged() { root.rebuildCryptoEntries() }
```

- [ ] **Step 5: Add the separator + Repeater to the panel**

In `compactRepresentation` → `RowLayout { id: contentRow ... }`, after the hold `Text { ... }` block (the one showing `root.displayHold + root.displaySymbol`), add:

```qml
            // ── Separator before crypto rates ───────────────────────
            Rectangle {
                visible: root.cryptoEntries.length > 0
                Layout.preferredWidth: 1
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignVCenter
                color: "#404040"
            }

            // ── Crypto rates ────────────────────────────────────────
            Repeater {
                model: root.cryptoEntries
                delegate: RowLayout {
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        source: {
                            var f = (modelData.code === "MATIC") ? "pol" : String(modelData.code).toLowerCase()
                            return Qt.resolvedUrl("images/crypto/" + f + ".svg")
                        }
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        Layout.alignment: Qt.AlignVCenter
                        smooth: true; mipmap: true
                    }
                    Text {
                        text: root.cryptoText(modelData)
                        color: modelData.color || "#FFFFFF"
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
```

- [ ] **Step 6: Validate QML syntax**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && qmllint package/contents/ui/main.qml 2>&1 | head -30 || true`
Expected: no hard syntax errors (Plasma import warnings acceptable).

- [ ] **Step 7: Commit**

```bash
git add package/contents/ui/main.qml
git commit -m "feat: render configurable crypto rates after the balance in the panel"
```

---

## Task 5: Version bump + README

**Files:**
- Modify: `package/metadata.json`
- Modify: `README.md`

- [ ] **Step 1: Bump version**

In `package/metadata.json`, change `"Version": "3.2.0"` to `"Version": "3.3.0"`.

- [ ] **Step 2: Add README feature bullet**

In `README.md`, in the `## Features` list, after the `**Currency conversion** ...` bullet, add:

```markdown
- **Crypto rates in the panel** — add coins (BTC, ETH, XMR, …) next to your balance, each in its own currency and color, configured in the CRYPTO tab
```

- [ ] **Step 3: Commit**

```bash
git add package/metadata.json README.md
git commit -m "docs: bump to 3.3.0 and document crypto rates"
```

---

## Task 6: Install locally & verify

**Files:** none (verification only)

- [ ] **Step 1: Re-run the rates tests (guard against regressions)**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && node tests/rates.test.js`
Expected: `all rates.js tests passed`.

- [ ] **Step 2: Install the widget from the local clone**

Run: `cd /home/rsz/Desktop/Y7Plasma/LZT/lzt-balance-widget && kpackagetool6 -t Plasma/Applet -u package/ 2>&1 | tail -5`
Expected: "Successfully upgraded ..." (or run `install.sh` which upgrades + restarts plasmashell).

- [ ] **Step 3: Confirm registration**

Run: `kpackagetool6 -t Plasma/Applet -l | grep lztbalance`
Expected: `org.kde.plasma.lztbalance`.

- [ ] **Step 4: Visual confirmation (user)**

Restart plasmashell (`install.sh` does this) and ask the user to: open widget settings → confirm the **LZT** and **CRYPTO** tabs; add BTC/USD (white) and ETH/USD in CRYPTO; confirm the panel shows the separator + coin icon + rate next to the balance, all at the same font size. The user's live API token + desktop are required for a real visual check.

- [ ] **Step 5: Mark complete**

Once the user confirms it looks right, the feature is done on `feat/crypto-rates`. Offer to merge into `main` / push (only on request).

---

## Self-review

**Spec coverage:** no-new-networking (Task 4 cryptoText reuses currencyRates ✓), 17 coins (Task 2 + Crypto.qml supportedCoins ✓), per-coin currency+color (Crypto.qml + Repeater ✓), empty default (main.xml `[]` ✓), Add/Edit/Remove/reorder (Crypto.qml ✓), General→LZT + CRYPTO tabs (Task 3 ✓), separator (Task 4 ✓), unified font size (Task 4 Text pixelSize matches balance ✓), formatRate rules (Task 1 ✓), TDD rates.js (Task 1 ✓), version bump + README (Task 5 ✓), install local / no push (Task 6 ✓).

**Placeholder scan:** none — all steps carry full code/commands.

**Type consistency:** `cryptoList` (config) ↔ `cfg_cryptoList` (Crypto.qml) ↔ `parseCryptoList`/`cryptoEntries` (main.qml) consistent. `convert`/`formatRate`/`parseCryptoList` signatures match between rates.js, tests, and main.qml usage. Icon filename rule (`MATIC`→`pol`, else lowercase) identical in Crypto.qml and main.qml.
