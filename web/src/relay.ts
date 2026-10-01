import { isExtensionRequest } from "./messages";

export type SendNative = (message: unknown) => Promise<unknown>;

export function relayToNative(message: unknown, sendNative: SendNative): Promise<unknown> | undefined {
  return isExtensionRequest(message) ? sendNative(message) : undefined;
}
