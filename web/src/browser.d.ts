interface Tab {
  id?: number | undefined;
  url?: string | undefined;
  incognito?: boolean | undefined;
}

interface MessageSender {
  id?: string | undefined;
  url?: string | undefined;
  frameId?: number | undefined;
  tab?: Tab | undefined;
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

interface ExtensionTabs {
  query(query: { active: boolean; currentWindow: boolean }): Promise<Tab[]>;
  sendMessage(tabId: number, message: unknown): Promise<unknown>;
}

interface ExtensionAction {
  setBadgeText(details: { tabId: number; text: string }): Promise<void>;
}

declare const browser: { runtime: ExtensionRuntime; tabs: ExtensionTabs; action: ExtensionAction };
