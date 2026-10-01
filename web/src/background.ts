import { relayToNative } from "./relay";

const APP_ID = "com.tarunyadgirkar.prefill";

browser.runtime.onMessage.addListener((message) =>
  relayToNative(message, (payload) => browser.runtime.sendNativeMessage(APP_ID, payload)),
);
