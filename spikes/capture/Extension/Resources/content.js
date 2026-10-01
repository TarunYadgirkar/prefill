const SKIP_TOKENS = new Set(["current-password", "new-password", "one-time-code"]);
const SKIP_TYPES = new Set(["password", "hidden", "submit", "button", "reset", "image", "checkbox", "radio", "file", "search"]);
const NAME_TOKENS = new Set(["name", "given-name", "family-name", "additional-name", "nickname", "honorific-prefix", "honorific-suffix"]);
const ADDRESS_TOKENS = new Set(["street-address", "postal-code", "country", "country-name"]);

const lastValues = new Map();
let lastSentSignature = "";

function labelText(el) {
    return [...(el.labels ?? [])].map((l) => l.textContent).join(" ") + " " + (el.getAttribute("aria-label") ?? "");
}

function kindOf(el) {
    const type = (el.type ?? "").toLowerCase();
    if (SKIP_TYPES.has(type)) return null;
    const tokens = (el.getAttribute("autocomplete") ?? "").toLowerCase().trim().split(/\s+/);
    const field = tokens[tokens.length - 1];
    if (SKIP_TOKENS.has(field) || field.startsWith("cc-")) return null;
    if (field === "email" || type === "email") return "email";
    if (field.startsWith("tel") || type === "tel") return "tel";
    if (NAME_TOKENS.has(field)) return "name";
    if (field.startsWith("address") || ADDRESS_TOKENS.has(field)) return "address";
    const hint = [el.name, el.id, el.placeholder, labelText(el)].join(" ").toLowerCase();
    if (/one.?time|otp|passcode|verification|password/.test(hint)) return null;
    if (/e-?mail/.test(hint)) return "email";
    if (/phone|mobile|\btel\b/.test(hint)) return "tel";
    if (/address|street|city|zip|postal/.test(hint)) return "address";
    if (/name/.test(hint)) return "name";
    return null;
}

function describeField(el) {
    const kind = kindOf(el);
    const value = (el.value ?? "").trim();
    if (!kind || !value) return null;
    return { kind, field: el.getAttribute("autocomplete") || el.name || el.id || "", value };
}

function collect(root) {
    return [...root.querySelectorAll("input, textarea, select")].map(describeField).filter(Boolean);
}

function showBadge(text) {
    let badge = document.getElementById("prefill-capture-badge");
    if (!badge) {
        badge = document.createElement("div");
        badge.id = "prefill-capture-badge";
        badge.setAttribute("role", "status");
        badge.style.cssText = "position:fixed;left:8px;right:8px;bottom:8px;padding:8px;background:#111;color:#fff;font:13px system-ui;z-index:2147483647;border-radius:8px";
        document.documentElement.appendChild(badge);
    }
    badge.textContent = text;
}

function send(trigger, fields, tEvent) {
    if (!fields.length) return;
    const signature = JSON.stringify(fields);
    if ((trigger === "pagehide" || trigger === "visibility-hidden") && signature === lastSentSignature) return;
    lastSentSignature = signature;
    const message = { type: "capture", trigger, url: location.href, host: location.host, fields, t_event: tEvent };
    browser.runtime.sendMessage(message).then((response) => {
        const total = Date.now() - tEvent;
        const written = response?.reply?.latency_event_to_written_ms;
        showBadge(`Captured ${fields.length} via ${trigger}. Written ${Math.round(written ?? -1)} ms, reply ${total} ms. ${response?.ok ? "" : response?.error ?? ""}`);
    }).catch((error) => showBadge(`Capture failed: ${error}`));
}

function isSubmitButton(el) {
    const button = el?.closest?.("button, input[type=submit], input[type=image]");
    if (!button) return null;
    if (button.tagName === "BUTTON" && (button.getAttribute("type") ?? "submit").toLowerCase() !== "submit") return null;
    return button;
}

document.addEventListener("input", (event) => {
    const info = describeField(event.target);
    if (info) lastValues.set(event.target, info);
}, true);

document.addEventListener("change", (event) => {
    const info = describeField(event.target);
    if (info) lastValues.set(event.target, info);
}, true);

document.addEventListener("submit", (event) => {
    send("submit", collect(event.target), Date.now());
}, true);

document.addEventListener("click", (event) => {
    const button = isSubmitButton(event.target);
    if (!button) return;
    send("submit-click", collect(button.form ?? document), Date.now());
}, true);

window.addEventListener("pagehide", () => {
    send("pagehide", [...lastValues.values()], Date.now());
}, true);

document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") send("visibility-hidden", [...lastValues.values()], Date.now());
}, true);
