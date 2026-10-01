import { relayToNative } from "./relay";

const APP_ID = "com.tarunyadgirkar.prefill";

browser.runtime.onMessage.addListener((message, sender) =>
  relayToNative(message, sender, browser.runtime.id, (payload) => browser.runtime.sendNativeMessage(APP_ID, payload)),
);
