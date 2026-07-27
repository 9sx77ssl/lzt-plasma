// Pure helpers for crypto-rate display.
// Importable by QML (import "rates.js" as Rates) and by Node tests
// (the module.exports guard at the bottom — `module` is undefined in QML).

var COINGECKO_IDS = {
    "BTC":   "bitcoin",
    "ETH":   "ethereum",
    "BNB":   "binancecoin",
    "XMR":   "monero",
    "BCH":   "bitcoin-cash",
    "SOL":   "solana",
    "LTC":   "litecoin",
    "DASH":  "dash",
    "AVAX":  "avalanche-2",
    "GRAM":  "the-open-network",
    "USDC":  "usd-coin",
    "DAI":   "dai",
    "USDT":  "tether",
    "TRX":   "tron",
    "POL":   "polygon-ecosystem-token",
    "MATIC": "matic-network",
    "SHIB":  "shiba-inu"
}

var COINGECKO_SUPPORTED_QUOTES = {
    "RUB": true, "USD": true, "EUR": true, "UAH": true,
    "BTC": true
}

function coingeckoId(code) {
    return COINGECKO_IDS[code] || ""
}

function coingeckoSupportsQuote(currency) {
    return COINGECKO_SUPPORTED_QUOTES[currency] === true
}

function uniquePush(arr, value) {
    if (!value || arr.indexOf(value) !== -1) return
    arr.push(value)
}

function coingeckoIdsForEntries(entries, includeBitcoin) {
    var out = []
    if (includeBitcoin) uniquePush(out, COINGECKO_IDS["BTC"])
    for (var i = 0; entries && i < entries.length; i++) {
        uniquePush(out, coingeckoId(entries[i].code))
    }
    return out
}

function coingeckoQuotesForEntries(entries, extraCurrency) {
    var out = ["rub"]
    if (coingeckoSupportsQuote(extraCurrency)) uniquePush(out, String(extraCurrency).toLowerCase())
    for (var i = 0; entries && i < entries.length; i++) {
        var c = entries[i].currency || "USD"
        if (coingeckoSupportsQuote(c)) uniquePush(out, String(c).toLowerCase())
    }
    return out
}

// Coin price in a target currency. rates = code -> RUB-per-unit.
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

// Group an integer with a non-breaking space every 3 digits: 5218726 -> "5 218 726".
// NBSP (U+00A0) keeps the number on one line and reads cleaner than a normal space.
function groupThousands(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, String.fromCharCode(0xa0))
}

// Format a converted rate for the panel:
//   >= 10000    -> grouped integer    (73 595)
//   1000..9999  -> plain integer      (2007)
//   1 .. 1000   -> up to 2 decimals   (2.46 / 382)
//   0 .. 1      -> 4 significant figs  (0.0042) — needed for SHIB-class values
//   null/NaN/<=0 -> "…"
function formatRate(v) {
    if (v === null || v === undefined || isNaN(v) || v <= 0) return "…"
    if (v >= 10000) return groupThousands(Math.round(v))
    if (v >= 1000)  return String(Math.round(v))
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

if (typeof module !== "undefined") {
    module.exports = {
        convert: convert,
        trimZeros: trimZeros,
        groupThousands: groupThousands,
        formatRate: formatRate,
        parseCryptoList: parseCryptoList,
        coingeckoId: coingeckoId,
        coingeckoSupportsQuote: coingeckoSupportsQuote,
        coingeckoIdsForEntries: coingeckoIdsForEntries,
        coingeckoQuotesForEntries: coingeckoQuotesForEntries
    }
}
