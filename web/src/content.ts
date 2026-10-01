import type { Ping } from "./messages";

const ping: Ping = { type: "ping" };

void browser.runtime.sendMessage(ping);
