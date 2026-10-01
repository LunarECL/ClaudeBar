// Anthropic's OAuth usage API → usage. Runs in JavaScriptCore with no I/O.
//
// `context.credential.subscriptionType` names the plan (the definition lets
// this script see that one credential value, never the token).
//
// Ported from the Swift probe this replaced; its tests pinned these rules.

function read(response, context) {
  var body = response.json;
  // A body that is not a JSON object is a failed parse, not "no usage".
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: { parseFailed: "Failed to parse usage response" } };
  }
  var now = context.now;
  var quotas = [];

  addWindow(quotas, body.five_hour, "session", null, now);
  addWindow(quotas, body.seven_day, "weekly", null, now);
  addWindow(quotas, body.seven_day_sonnet, "model", "sonnet", now);
  addWindow(quotas, body.seven_day_opus, "model", "opus", now);

  // Weekly limits scoped to a model, named by the first word of the model's
  // name — "Fable 5" → "fable", the key the CLI uses too. First one wins.
  var limits = Array.isArray(body.limits) ? body.limits : [];
  for (var i = 0; i < limits.length; i++) {
    var entry = limits[i] || {};
    var display = entry.scope && entry.scope.model && entry.scope.model.display_name;
    if (entry.kind !== "weekly_scoped" || typeof display !== "string") continue;
    var name = display.split(" ").filter(function (part) { return part !== ""; })[0];
    if (!name || typeof entry.percent !== "number") continue;
    name = name.toLowerCase();
    if (quotas.some(function (q) { return q.type === "model" && q.name === name; })) continue;
    quotas.push(quota("model", name, 100 - entry.percent, entry.resets_at, now));
  }

  var result = { quotas: quotas };
  var plan = planFrom(context.credential && context.credential.subscriptionType);
  if (plan) result.plan = plan;
  var cost = spend(body.spend) || extraUsage(body.extra_usage);
  if (cost) result.cost = cost;
  return result;
}

function addWindow(quotas, data, type, name, now) {
  if (!data || typeof data.utilization !== "number") return;
  // Not clamped: over the limit shows as negative, as the API reports it.
  quotas.push(quota(type, name, 100 - data.utilization, data.resets_at, now));
}

function quota(type, name, percentLeft, resetsAt, now) {
  var q = { type: type, percentRemaining: percentLeft };
  if (name) q.name = name;
  var at = parseISO(resetsAt);
  if (at !== null) {
    q.resetsAt = at;
    var text = countdown(at - now);
    if (text !== null) q.resetText = text;
  }
  return q;
}

function parseISO(text) {
  if (typeof text !== "string") return null;
  var ms = Date.parse(text);
  return isNaN(ms) ? null : ms / 1000;
}

// "Resets in 50h 3m" — hours, not days, as the API path always showed.
function countdown(seconds) {
  if (seconds <= 0) return null;
  var hours = Math.floor(seconds / 3600);
  var minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) return "Resets in " + hours + "h " + minutes + "m";
  if (minutes > 0) return "Resets in " + minutes + "m";
  return "Resets soon";
}

function planFrom(subscriptionType) {
  if (typeof subscriptionType !== "string") return null;
  switch (subscriptionType.toLowerCase()) {
    case "claude_max": case "max": return "claudeMax";
    case "claude_pro": case "pro": return "claudePro";
    case "api": case "claude_api": return "claudeApi";
    default: return subscriptionType;
  }
}

// MARK: - Money

// `spend`: minor units with an exponent. Preferred when it answers.
function spend(data) {
  if (!data || data.enabled !== true) return null;
  var used = minorUnits(data.used);
  if (used === null) return null;
  if (data.limit === undefined || data.limit === null) return { kind: "extraUsage", used: used };
  var limit = minorUnits(data.limit);
  if (limit === null) return null;
  return { kind: "extraUsage", used: used, limit: limit };
}

// Legacy `extra_usage`: credits in hundredths unless `decimal_places` says otherwise.
function extraUsage(data) {
  if (!data || data.is_enabled !== true) return null;
  var places = data.decimal_places === undefined || data.decimal_places === null ? 2 : data.decimal_places;
  var used = scaled(data.used_credits, places);
  if (used === null) return null;
  if (data.monthly_limit === undefined || data.monthly_limit === null) return { kind: "extraUsage", used: used };
  var limit = scaled(data.monthly_limit, places);
  if (limit === null) return null;
  return { kind: "extraUsage", used: used, limit: limit };
}

function minorUnits(money) {
  if (!money) return null;
  return scaled(money.amount_minor, money.exponent);
}

// amount × 10^-places as an exact decimal string; negative or missing → null.
function scaled(amount, places) {
  if (typeof amount !== "number" || amount < 0) return null;
  if (typeof places !== "number" || places < 0 || Math.floor(places) !== places) return null;
  return shift(String(amount), places);
}

function shift(text, places) {
  if (/e/i.test(text)) text = Number(text).toFixed(20).replace(/0+$/, "").replace(/\.$/, "");
  var parts = text.split(".");
  var digits = parts[0] + (parts[1] || "");
  var point = parts[0].length - places;
  while (point <= 0) { digits = "0" + digits; point += 1; }
  var whole = digits.slice(0, point).replace(/^0+(?=\d)/, "");
  var fraction = digits.slice(point);
  return fraction === "" ? whole : whole + "." + fraction;
}
