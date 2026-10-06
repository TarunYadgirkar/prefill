import { parseExtensionResponse, type PickedRequest } from "./messages";

export type SendPick = (request: PickedRequest) => Promise<unknown>;

// Tells the app the person picked a value from Prefill's list, so it comes first on the
// site next time. `remembered` runs once the app has taken it, to fetch the new order.
export function reportPick(
  send: SendPick,
  request: PickedRequest,
  remembered?: () => void,
): void {
  send(request)
    .then((reply) => {
      const response = parseExtensionResponse(reply);
      if (response?.type === "pickedResult" && response.remembered)
        remembered?.();
    })
    .catch(() => undefined);
}
