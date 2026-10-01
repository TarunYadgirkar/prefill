type MessageListener = (message: unknown) => Promise<unknown> | undefined;

interface ExtensionRuntime {
  sendMessage(message: unknown): Promise<unknown>;
  sendNativeMessage(application: string, message: unknown): Promise<unknown>;
  onMessage: {
    addListener(listener: MessageListener): void;
  };
}

declare const browser: { runtime: ExtensionRuntime };
