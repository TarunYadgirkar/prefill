// Chrome and Arc name the extension API `chrome`, and their onMessage listeners answer
// through `sendResponse` rather than a returned promise. esbuild injects this `browser`
// wherever the shared code uses the global one.

type SendResponse = (response: unknown) => void;
type ChromeListener = (message: unknown, sender: MessageSender, sendResponse: SendResponse) => boolean;

declare const chrome: {
  runtime: {
    id: string;
    sendMessage(message: unknown): Promise<unknown>;
    sendNativeMessage(application: string, message: unknown): Promise<unknown>;
    onMessage: { addListener(listener: ChromeListener): void };
  };
  tabs: ExtensionTabs;
  action: ExtensionAction;
};

export function answering(listener: MessageListener): ChromeListener {
  return (message, sender, sendResponse) => {
    const reply = listener(message, sender);
    if (reply === undefined) return false;
    reply.then(sendResponse, () => {
      sendResponse(undefined);
    });
    return true;
  };
}

export const browser = {
  runtime: {
    get id() {
      return chrome.runtime.id;
    },
    sendMessage: (message: unknown) => chrome.runtime.sendMessage(message),
    sendNativeMessage: (application: string, message: unknown) => chrome.runtime.sendNativeMessage(application, message),
    onMessage: {
      addListener: (listener: MessageListener) => {
        chrome.runtime.onMessage.addListener(answering(listener));
      },
    },
  },
  get tabs() {
    return chrome.tabs;
  },
  get action() {
    return chrome.action;
  },
};
