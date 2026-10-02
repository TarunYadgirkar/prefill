import { startPage } from "./page";

startPage({
  doc: document,
  win: window,
  protocol: location.protocol,
  hostname: location.hostname,
  isSecureContext: window.isSecureContext,
  isTopFrame: window === window.top,
  send: (request) => browser.runtime.sendMessage(request),
});
