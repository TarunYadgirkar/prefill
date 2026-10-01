browser.runtime.onMessage.addListener((request) => {
    if (request?.type === "ping") return Promise.resolve({ pong: true });
});
