import { PAGE_NEEDS_QUERY, parsePageNeeds, parseSheetResponse, type ContactKind, type SheetRequest } from "../messages";
import { APP_ID } from "../native";
import { render, renderProblem, type SheetView } from "./render";
import { merge, openingFor, type Site } from "./sheet";

const root = document.getElementById("sheet") ?? document.body;

const NOTES: Partial<Record<SheetRequest["type"], string>> = {
  pin: "Done. Tap the field again to see it first.",
  unpin: "Prefill picks for this site again.",
  undoCapture: "Taken off your card.",
};

function startSheet(site: Site): void {
  let view: SheetView = { host: site.host, kind: site.kinds[0] ?? "email", state: undefined, busy: false, note: undefined };

  const actions = {
    send: (request: SheetRequest) => void send(request),
    showKind: (kind: ContactKind) => {
      update({ kind, note: undefined });
    },
  };

  // Lets the slots slide to their new places where Safari supports view transitions.
  function update(change: Partial<SheetView>): void {
    view = { ...view, ...change };
    const draw = (): void => {
      render(root, view, actions);
    };
    if (change.state !== undefined && "startViewTransition" in document) document.startViewTransition(draw);
    else draw();
  }

  async function send(request: SheetRequest): Promise<void> {
    update({ busy: true, note: undefined });
    const raw = await browser.runtime.sendNativeMessage(APP_ID, request).catch(() => undefined);
    const reply = parseSheetResponse(raw);
    if (reply === undefined || reply.type === "error") {
      update({ busy: false, note: "Prefill didn't answer. Try again in a moment." });
      return;
    }
    const isDone = reply.status !== "failed";
    update({ busy: false, state: merge(view.state, reply), note: isDone ? NOTES[request.type] : undefined });
  }

  update({});
  void send({ type: "popupState", host: site.host, kinds: site.kinds });
}

async function open(): Promise<void> {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true }).catch(() => []);
  const tabId = tab?.id;
  const answer = tabId === undefined ? undefined : await browser.tabs.sendMessage(tabId, PAGE_NEEDS_QUERY).catch(() => undefined);
  const opening = openingFor(tab, parsePageNeeds(answer));
  if (tabId !== undefined) browser.action.setBadgeText({ tabId, text: "" }).catch(() => undefined);
  if ("site" in opening) {
    startSheet(opening.site);
    return;
  }
  if (opening.problem === "private") renderProblem(root, "Not in Private Browsing", "Prefill doesn't run in private tabs.");
  else renderProblem(root, "Nothing to fill here", "Prefill works on websites that load over a secure connection.");
}

void open();
