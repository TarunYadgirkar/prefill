import { startPage } from "./page";
import { answerPageNeeds } from "./pageNeeds";

startPage({
  doc: document,
  win: window,
  protocol: location.protocol,
  hostname: location.hostname,
  isSecureContext: window.isSecureContext,
  isTopFrame: window === window.top,
  send: (request) => browser.runtime.sendMessage(request),
});

if (window === window.top && window.isSecureContext) {
  browser.runtime.onMessage.addListener((message, sender) =>
    answerPageNeeds(message, sender, browser.runtime.id, {
      doc: document,
      protocol: location.protocol,
      hostname: location.hostname,
    }),
  );
}
