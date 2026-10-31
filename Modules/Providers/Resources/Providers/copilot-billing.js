function read(response, context) {
    const failure = message => ({error: {parseFailed: message}});
    const json = response.json;
    if (!json || typeof json !== 'object' || !json.timePeriod || !Number.isInteger(json.timePeriod.year)
        || !Number.isInteger(json.timePeriod.month) || !Array.isArray(json.usageItems)) {
        return failure('Failed to parse billing response');
    }
    const items = json.usageItems.filter(item => item && typeof item.product === 'string' && item.product.toLowerCase().includes('copilot'));
    // The plan the person picked carries its monthly allowance and unit:
    // AI credits, or premium requests for an annual plan still billed by request.
    const limit = Number(context.values.allowance), unit = context.values.unit;
    if (!(limit > 0) || !unit) return failure('No monthly allowance for this Copilot plan');

    // No items is nothing used yet — or a seat an organization pays for,
    // which GitHub doesn't report here. For that, the person enters what
    // GitHub's settings page shows. GitHub's own numbers win when it has any.
    let used = items.reduce((sum, item) => sum + (Number(item.grossQuantity) || 0), 0), manual = false;
    if (!items.length && context.values.manualUsage) {
        const text = context.values.manualUsage;
        used = text.endsWith('%') ? Number(text.slice(0, -1)) / 100 * limit : Number(text);
        manual = true;
    }

    // The billing period is the calendar month GitHub names, in UTC.
    const start = Date.UTC(json.timePeriod.year, json.timePeriod.month - 1, 1) / 1000;
    const end = Date.UTC(json.timePeriod.year, json.timePeriod.month, 1) / 1000;
    const quota = {
        type: 'time', name: 'Monthly',
        // Below zero shows how far over the limit this month is.
        percentRemaining: Math.min(100, (limit - used) / limit * 100),
        resetsAt: end, windowSeconds: end - start,
        resetText: Math.round(used) + '/' + Math.round(limit) + ' ' + unit + (manual ? ' (manual)' : '')
    };
    const result = {quotas: [quota]};
    if (context.credential.username) result.account = {email: context.credential.username};
    return result;
}
