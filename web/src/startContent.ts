import { startPage, type PageEnvironment, type PageFill } from "./page";
import { answerFill, answerPageNeeds } from "./pageNeeds";

// Chrome leaves a reloaded or updated extension's old scripts running in open tabs, cut off
// from the extension, and starts a new copy beside them.
function isConnected(): boolean {
  try {
    return (browser.runtime as { id?: string }).id !== undefined;
  } catch {
    return false;
  }
}

export function startContent(
  kind: NonNullable<PageEnvironment["browser"]>,
): void {
  // Registered before the page's own listeners, so a cut-off copy steps aside before it
  // shows anything from what it fetched earlier.
  const retire = (): void => {
    if (isConnected()) return;
    stop();
    document.removeEventListener("focusin", retire, true);
  };
  document.addEventListener("focusin", retire, true);
  let fill: PageFill | undefined;
  const stop = startPage({
    doc: document,
    win: window,
    protocol: location.protocol,
    hostname: location.hostname,
    isSecureContext: window.isSecureContext,
    isTopFrame: window === window.top,
    send: (request) => browser.runtime.sendMessage(request),
    browser: kind,
    onFill: (pageFill) => {
      fill = pageFill;
    },
  });

  if (window === window.top && window.isSecureContext) {
    browser.runtime.onMessage.addListener((message, sender) => {
      const page = {
        doc: document,
        protocol: location.protocol,
        hostname: location.hostname,
        ...(fill === undefined ? {} : { fill }),
      };
      return (
        answerPageNeeds(message, sender, browser.runtime.id, page) ??
        answerFill(message, sender, browser.runtime.id, page)
      );
    });
  }
}
