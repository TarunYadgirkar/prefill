import { APP_ID } from "./native";
import { relayToNative } from "./relay";

browser.runtime.onMessage.addListener((message, sender) =>
  relayToNative(
    message,
    sender,
    browser.runtime.id,
    (payload) => browser.runtime.sendNativeMessage(APP_ID, payload),
    (tabId, count) => {
      browser.action.setBadgeText({ tabId, text: String(count) }).catch(() => undefined);
    },
  ),
);
