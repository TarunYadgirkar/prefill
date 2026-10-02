import { classify } from "./classify";
import { eventOrigin, isFieldElement } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { parseExtensionResponse, type LinkSuggestionsRequest, type LinkType, type SuggestedLink } from "./messages";

export interface LinkOptions {
  host: () => string;
  send: (request: LinkSuggestionsRequest) => Promise<unknown>;
  // Only focus the browser made counts. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
}

// Safari's bar shows at most three datalist options.
const MAX_OPTIONS = 3;

// Shorter in the bar: no scheme and no trailing slash.
export function shown(url: string): string {
  return url.replace(/^https?:\/\//iu, "").replace(/\/+$/u, "");
}

// What the bar offers a field that wants `wanted`, best first. A field that names two
// kinds ("GitHub/Portfolio") gets both in one option first, then each alone. A url field
// gets whole addresses, which a combined option is not, so it gets none.
export function linkOptions(wanted: readonly LinkType[], links: readonly SuggestedLink[], fullUrl: boolean): string[] {
  const text = (link: SuggestedLink): string => (fullUrl ? link.url : shown(link.url));
  const firsts = wanted.flatMap((type) => links.find((link) => link.type === type) ?? []);
  const [first, second] = firsts;
  const combined = !fullUrl && first !== undefined && second !== undefined ? [`${text(first)} - ${text(second)}`] : [];
  const rest = wanted.flatMap((type) => links.filter((link) => link.type === type));
  return [...new Set([...combined, ...firsts.map(text), ...rest.map(text)])].slice(0, MAX_OPTIONS);
}

function linkTypesOf(element: FieldElement): readonly LinkType[] {
  if (element.localName !== "input") return [];
  const field = classify(element);
  return field.kind === "link" ? (field.linkTypes ?? []) : [];
}

function wantsUrl(element: FieldElement): boolean {
  return element.localName === "input" && (element as HTMLInputElement).type.toLowerCase() === "url";
}

function attach(element: HTMLInputElement, options: readonly string[]): () => void {
  const doc = element.ownerDocument;
  const list = doc.createElement("datalist");
  list.id = `prefill-links-${crypto.randomUUID()}`;
  list.append(
    ...options.map((value) => {
      const option = doc.createElement("option");
      option.value = value;
      return option;
    }),
  );
  // Outside the page's own markup, but in the field's tree, where its list id resolves.
  const root = element.getRootNode();
  (root instanceof ShadowRoot ? root : doc.body).append(list);
  element.setAttribute("list", list.id);
  return () => {
    element.removeAttribute("list");
    list.remove();
  };
}

// When the person focuses a field that asks for a profile link, asks the app for the
// card's links of those kinds and offers them in Safari's bar through a datalist, which
// goes away again when the field loses focus. A field with a list of its own is left alone.
export function installLinks(doc: Document, options: LinkOptions): () => void {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  let detach: (() => void) | undefined;
  let focused: FieldElement | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
  };

  const offer = (element: HTMLInputElement, wanted: readonly LinkType[], reply: unknown): void => {
    const response = parseExtensionResponse(reply);
    if (focused !== element || response?.type !== "linkSuggestionsResult") return;
    const choices = linkOptions(wanted, response.links, wantsUrl(element));
    if (choices.length > 0) detach = attach(element, choices);
  };

  const onFocus = (event: Event): void => {
    const target = eventOrigin(event);
    if (!isUserEvent(event) || !isFieldElement(target) || target.hasAttribute("list")) return;
    const wanted = linkTypesOf(target);
    if (wanted.length === 0) return;
    clear();
    focused = target;
    const element = target as HTMLInputElement;
    options
      .send({ type: "linkSuggestions", host: options.host(), types: [...wanted] })
      .then((reply) => {
        offer(element, wanted, reply);
      })
      .catch(() => undefined);
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === focused) clear();
  };

  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
