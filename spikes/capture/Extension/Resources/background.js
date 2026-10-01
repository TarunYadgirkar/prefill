const APP_ID = "com.tarunyadgirkar.prefill.spike.capture";

browser.runtime.onMessage.addListener((message, sender) => {
    if (message?.type !== "capture") return;
    const payload = { ...message, t_bg: Date.now(), tab_url: sender?.tab?.url ?? null };
    return browser.runtime.sendNativeMessage(APP_ID, payload)
        .then((reply) => ({ ok: true, reply, t_bg_reply: Date.now() }))
        .catch((error) => ({ ok: false, error: String(error) }));
});
