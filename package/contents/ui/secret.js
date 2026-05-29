// Light obfuscation for the stored API token.
//
// IMPORTANT: this is OBFUSCATION, not real encryption. A local widget must be
// able to decode the token to call the API, so the key necessarily lives in
// this file — anyone reading the source can reverse it. What this buys you:
// the token is NOT sitting as plain text in the Plasma config file, so a
// casual look (grep, backup, screen-share) won't leak it. For real at-rest
// security use a system keyring (KWallet).

var KEY = "lzt-plasmoid-9sx77ssl-v3"

function xorStr(s, key) {
    var out = ""
    for (var i = 0; i < s.length; i++)
        out += String.fromCharCode(s.charCodeAt(i) ^ key.charCodeAt(i % key.length))
    return out
}

// raw token -> "enc:<base64>"
function encode(raw) {
    if (!raw || String(raw).length === 0) return ""
    try { return "enc:" + Qt.btoa(xorStr(String(raw), KEY)) }
    catch (e) { return String(raw) }
}

// "enc:<base64>" -> raw token. Legacy plain values (no "enc:" prefix) pass through.
function decode(stored) {
    if (!stored || String(stored).length === 0) return ""
    var s = String(stored)
    if (s.indexOf("enc:") !== 0) return s
    try { return xorStr(Qt.atob(s.substring(4)), KEY) }
    catch (e) { return "" }
}

// True if a stored value still needs migrating to the encoded form.
function isPlain(stored) {
    var s = stored ? String(stored) : ""
    return s.length > 0 && s.indexOf("enc:") !== 0
}
