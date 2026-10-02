interface MessageSender {
  id?: string | undefined;
  url?: string | undefined;
  frameId?: number | undefined;
  tab?: { incognito?: boolean | undefined } | undefined;
}

type MessageListener = (message: unknown, sender: MessageSender) => Promise<unknown> | undefined;

interface ExtensionRuntime {
  id: string;
  sendMessage(message: unknown): Promise<unknown>;
  sendNativeMessage(application: string, message: unknown): Promise<unknown>;
  onMessage: {
    addListener(listener: MessageListener): void;
  };
}

declare const browser: { runtime: ExtensionRuntime };
