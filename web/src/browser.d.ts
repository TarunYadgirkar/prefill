interface MessageSender {
  id?: string;
  url?: string;
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
