import { installCapture } from "./capture";
import { installContext } from "./context";
import type { ExtensionRequest } from "./messages";

const send = (request: ExtensionRequest): Promise<unknown> => browser.runtime.sendMessage(request);

// Runs in every frame. A frame with no contact fields sends nothing.
if (location.protocol === "https:" || location.protocol === "http:") {
  const host = (): string => location.hostname;
  installContext(document, { host, send });
  installCapture(document, window, {
    host,
    send: (request) => {
      send(request).catch(() => undefined);
    },
  });
}
