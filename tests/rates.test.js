const assert = require('assert')
const { convert, formatRate, parseCryptoList } = require('../package/contents/ui/rates.js')

// ── convert(rates, code, currency) ────────────────────────────────
const rates = { BTC: 5218725.85339486, USD: 70.91026973, RUB: 1, ETH: 142928.24 }
assert.ok(Math.abs(convert(rates, 'BTC', 'USD') - 73596.2) < 0.5, 'BTC in USD ~ 73596')
assert.strictEqual(convert(rates, 'BTC', 'RUB'), 5218725.85339486, 'RUB passthrough = base rate')
assert.strictEqual(convert(rates, 'DOGE', 'USD'), null, 'missing base -> null')
assert.strictEqual(convert(rates, 'BTC', 'XXX'), null, 'missing quote -> null')
assert.strictEqual(convert(null, 'BTC', 'USD'), null, 'no rates -> null')
assert.strictEqual(convert({ BTC: 100, USD: 0 }, 'BTC', 'USD'), null, 'zero quote -> null')

// ── formatRate(v) ─────────────────────────────────────────────────
// >= 10000 gets a NBSP ( ) thousands separator; 1000..9999 stays plain.
assert.strictEqual(formatRate(73595.06), '73 595',          '>=10k -> grouped')
assert.strictEqual(formatRate(62934),    '62 934',          '>=10k -> grouped')
assert.strictEqual(formatRate(5218726),  '5 218 726',  '7 digits -> grouped')
assert.strictEqual(formatRate(2007.4),   '2007',   '1k..9999 -> plain integer')
assert.strictEqual(formatRate(1500),     '1500',   '1k..9999 -> plain integer')
assert.strictEqual(formatRate(382),      '382',    'mid whole -> integer')
assert.strictEqual(formatRate(2.4562),   '2.46',   'mid -> 2 decimals')
assert.strictEqual(formatRate(1),        '1',      'one -> 1')
assert.strictEqual(formatRate(0.5),      '0.5',    'sub-1 -> sig figs')
assert.strictEqual(formatRate(0.0042),   '0.0042', 'small sub-1 -> sig figs')
assert.strictEqual(formatRate(null),     '…',      'null -> ellipsis')
assert.strictEqual(formatRate(0),        '…',      'zero -> ellipsis')
assert.strictEqual(formatRate(NaN),      '…',      'NaN -> ellipsis')
assert.strictEqual(formatRate(-3),       '…',      'negative -> ellipsis')

// ── parseCryptoList(str) ──────────────────────────────────────────
assert.deepStrictEqual(parseCryptoList(''),            [], 'empty string -> []')
assert.deepStrictEqual(parseCryptoList('[]'),          [], '[] -> []')
assert.deepStrictEqual(parseCryptoList('not json'),    [], 'garbage -> []')
assert.deepStrictEqual(parseCryptoList('{"a":1}'),     [], 'object -> []')
assert.deepStrictEqual(parseCryptoList('[{"code":"BTC"}]'), [{ code: 'BTC' }], 'array preserved')

console.log('all rates.js tests passed')
