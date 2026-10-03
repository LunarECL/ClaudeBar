/// Helpers every mapping script gets, so money never passes through a binary
/// float: `jsonDecimal(text)` parses JSON with each number kept as its exact
/// text, and `decimalCents(amount)` rounds such a text to cents, half up.
enum DecimalScript {
    static let source = #"""
function jsonDecimal(text) {
    return JSON.parse(text.replace(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/g,
        token => token.charAt(0) === '"' ? token : JSON.stringify(token)));
}
function decimalCents(value) {
    const match = String(value).match(/^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/);
    if (!match || !(match[2] || match[3])) throw new Error('Not a decimal amount');
    const negative = match[1] === '-', exponent = Number(match[4] || 0);
    if (!Number.isInteger(exponent) || Math.abs(exponent) > 1000) throw new Error('Amount exponent out of range');
    let digits = (match[2] || '') + (match[3] || ''), point = (match[2] || '').length + exponent;
    if (point < 0) { digits = '0'.repeat(-point) + digits; point = 0; }
    if (point > digits.length) digits += '0'.repeat(point - digits.length);
    let cents = (digits.slice(0, point) || '0') + (digits.slice(point) + '00').slice(0, 2);
    cents = cents.replace(/^0+(?=\d)/, '');
    if (Number(digits.charAt(point + 2) || '0') >= 5) {
        let carry = 1, out = '';
        for (let i = cents.length - 1; i >= 0; i--) {
            const n = Number(cents[i]) + carry;
            out = String(n % 10) + out;
            carry = n >= 10 ? 1 : 0;
        }
        cents = (carry ? '1' : '') + out;
    }
    cents = cents.padStart(3, '0');
    return (negative && /[1-9]/.test(cents) ? '-' : '') + cents.slice(0, -2) + '.' + cents.slice(-2);
}
"""#
}
