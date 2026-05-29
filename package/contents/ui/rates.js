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
