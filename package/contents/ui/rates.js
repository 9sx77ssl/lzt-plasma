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

// ── Additional crypto providers ───────────────────────────────────────────
// Each map translates the widget's coin code to the provider's native ticker.
// A code missing from a provider's map simply isn't offered there, so the
// panel hides that coin while the provider is selected (Level: the widget's
// icon set is fixed, we never add new coins).

// Binance spot pairs (USDT quote). XMR was delisted, DAI is halted, USDT is the
// quote asset itself (no USDT/USDT pair) and MATIC was migrated to POL — so none
// of those four are offered here.
var BINANCE_PAIRS = {
    "BTC": "BTCUSDT", "ETH": "ETHUSDT", "BNB": "BNBUSDT", "BCH": "BCHUSDT",
    "SOL": "SOLUSDT", "LTC": "LTCUSDT", "DASH": "DASHUSDT", "AVAX": "AVAXUSDT",
    "USDC": "USDCUSDT", "TRX": "TRXUSDT", "POL": "POLUSDT", "SHIB": "SHIBUSDT"
}

// Kraken: USDT pairs where available, USD pairs for DASH/TRX/POL/USDT.
// BTC is XBT and GRAM is TON on Kraken; MATIC isn't listed.
var KRAKEN_PAIRS = {
    "BTC": "XBTUSDT", "ETH": "ETHUSDT", "BNB": "BNBUSDT", "XMR": "XMRUSDT",
    "BCH": "BCHUSDT", "SOL": "SOLUSDT", "LTC": "LTCUSDT", "DASH": "DASHUSD",
    "AVAX": "AVAXUSDT", "GRAM": "TONUSDT", "USDC": "USDCUSDT", "DAI": "DAIUSDT",
    "USDT": "USDTUSD", "TRX": "TRXUSD", "POL": "POLUSD", "SHIB": "SHIBUSDT"
}

// Kraken occasionally rewrites the result key (USDTUSD -> USDTZUSD), so match
// leniently on top of the exact pair.
function krakenLookupKey(rev, key) {
    if (rev[key]) return rev[key]
    var k2 = key.replace("ZUSD", "USD")
    if (rev[k2]) return rev[k2]
    return ""
}

// Coinbase /v2/exchange-rates?currency=USD keys. No XMR/TRX; GRAM is TON.
var COINBASE_KEYS = {
    "BTC": "BTC", "ETH": "ETH", "BNB": "BNB", "BCH": "BCH", "SOL": "SOL",
    "LTC": "LTC", "DASH": "DASH", "AVAX": "AVAX", "GRAM": "TON", "USDC": "USDC",
    "DAI": "DAI", "USDT": "USDT", "POL": "POL", "MATIC": "MATIC", "SHIB": "SHIB"
}

// Provider ids accepted by the config combo box.
var CRYPTO_PROVIDERS = ["lzt", "coingecko", "binance", "kraken", "coinbase"]

// Does `provider` offer `code`? "lzt" (and anything unknown) offers them all.
function providerSupports(provider, code) {
    if (provider === "coingecko") return coingeckoId(code).length > 0
    if (provider === "binance")   return BINANCE_PAIRS[code] !== undefined
    if (provider === "kraken")    return KRAKEN_PAIRS[code]  !== undefined
    if (provider === "coinbase")  return COINBASE_KEYS[code] !== undefined
    return true
}

// Entries the current provider can actually price.
function providerVisibleEntries(provider, entries) {
    var out = []
    for (var i = 0; entries && i < entries.length; i++)
        if (providerSupports(provider, entries[i].code)) out.push(entries[i])
    return out
}

function providerSymbolsForEntries(map, entries) {
    var out = []
    for (var i = 0; entries && i < entries.length; i++) uniquePush(out, map[entries[i].code])
    return out
}

// Reverse "CODE -> ticker" into "ticker -> CODE".
function reverseSymbolMap(map) {
    var out = {}
    for (var k in map) if (map.hasOwnProperty(k)) out[map[k]] = k
    return out
}

// Binance ticker/price -> { CODE: priceInQuote }.
function parseBinancePrices(raw) {
    var arr = JSON.parse(raw)
    var rev = reverseSymbolMap(BINANCE_PAIRS)
    var out = {}
    for (var i = 0; i < arr.length; i++) {
        var code = rev[arr[i].symbol]
        var p = parseFloat(arr[i].price)
        if (code && p > 0) out[code] = p
    }
    return out
}

// Kraken /Ticker -> { CODE: price }.
function parseKrakenPrices(raw) {
    var j = JSON.parse(raw)
    var res = (j && j.result) ? j.result : {}
    var rev = reverseSymbolMap(KRAKEN_PAIRS)
    var out = {}
    for (var pair in res) {
        if (!res.hasOwnProperty(pair)) continue
        var code = krakenLookupKey(rev, pair)
        if (!code) continue
        var t = res[pair]
        var p = (t && t.c && t.c.length) ? parseFloat(t.c[0]) : 0
        if (p > 0) out[code] = p
    }
    return out
}

// Coinbase exchange-rates -> { coins: { CODE: usdPerCoin }, fiat: { RUB, EUR, UAH } }.
// The endpoint reports "units of X per 1 USD", so USD-per-coin is reciprocal.
function parseCoinbaseRates(raw) {
    var j = JSON.parse(raw)
    var r = (j && j.data && j.data.rates) ? j.data.rates : {}
    var coins = {}
    for (var code in COINBASE_KEYS) {
        if (!COINBASE_KEYS.hasOwnProperty(code)) continue
        var v = parseFloat(r[COINBASE_KEYS[code]])
        if (v > 0) coins[code] = 1 / v
    }
    return {
        coins: coins,
        fiat: { "RUB": parseFloat(r.RUB), "EUR": parseFloat(r.EUR), "UAH": parseFloat(r.UAH) }
    }
}

// open.er-api.com/v6/latest/USD -> { USD, EUR, UAH } as RUB-per-unit.
// Used only when LZT's own /currency rates aren't available (no token).
function parseErApiFiat(raw) {
    var j = JSON.parse(raw)
    var r = (j && j.rates) ? j.rates : {}
    var rub = parseFloat(r.RUB)
    if (!(rub > 0)) return null
    var out = { "USD": rub }
    if (parseFloat(r.EUR) > 0) out["EUR"] = rub / parseFloat(r.EUR)
    if (parseFloat(r.UAH) > 0) out["UAH"] = rub / parseFloat(r.UAH)
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
        coingeckoQuotesForEntries: coingeckoQuotesForEntries,
        providerSupports: providerSupports,
        providerVisibleEntries: providerVisibleEntries,
        providerSymbolsForEntries: providerSymbolsForEntries,
        parseBinancePrices: parseBinancePrices,
        parseKrakenPrices: parseKrakenPrices,
        parseCoinbaseRates: parseCoinbaseRates,
        parseErApiFiat: parseErApiFiat,
        BINANCE_PAIRS: BINANCE_PAIRS,
        KRAKEN_PAIRS: KRAKEN_PAIRS,
        COINBASE_KEYS: COINBASE_KEYS,
        CRYPTO_PROVIDERS: CRYPTO_PROVIDERS
    }
}
