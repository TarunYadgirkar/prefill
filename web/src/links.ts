import { parseAutocomplete } from "./autocomplete";
import { classify } from "./classify";
import { attachDatalist } from "./datalist";
import type { Attach, Choice } from "./dropdown";
import { trackGestures } from "./gesture";
import { eventOrigin, hasOwnList, fieldElements, isFieldElement } from "./dom";
import type { FieldElement } from "./fieldTypes";
import {
  parseExtensionResponse,
  type LinkSuggestionsRequest,
  type LinkType,
  type SuggestedLink,
} from "./messages";

export interface LinkOptions {
  host: () => string;
  send: (request: LinkSuggestionsRequest) => Promise<unknown>;
  // Only focus the browser made counts. Tests pass their synthetic events through here.
  isUserEvent?: (event: Event) => boolean;
  // How the links are shown: a datalist for Safari's bar unless the caller draws its own list.
  attach?: Attach;
}

// Safari's bar shows at most three datalist options.
const MAX_OPTIONS = 3;
const MAX_INSPECTED = 200;

const TYPE_LABELS: Readonly<Record<LinkType, string>> = {
  github: "GitHub",
  linkedin: "LinkedIn",
  x: "X",
  website: "Website",
  other: "Link",
};

// Shorter in the bar: no scheme and no trailing slash.
export function shown(url: string): string {
  return url.replace(/^https?:\/\//iu, "").replace(/\/+$/u, "");
}

// What the bar offers a field that wants `wanted`, best first. A field that names two
// kinds ("GitHub/Portfolio") gets both in one option first, then each alone. A url field
// gets whole addresses, which a combined option is not, so it gets none.
export function linkOptions(
  wanted: readonly LinkType[],
  links: readonly SuggestedLink[],
  fullUrl: boolean,
): string[] {
  const text = (link: SuggestedLink): string =>
    fullUrl ? link.url : shown(link.url);
  const firsts = wanted.flatMap(
    (type) => links.find((link) => link.type === type) ?? [],
  );
  const [first, second] = firsts;
  const combined =
    !fullUrl && first !== undefined && second !== undefined
      ? [`${text(first)} - ${text(second)}`]
      : [];
  const rest = wanted.flatMap((type) =>
    links.filter((link) => link.type === type),
  );
  return [
    ...new Set([...combined, ...firsts.map(text), ...rest.map(text)]),
  ].slice(0, MAX_OPTIONS);
}

// Each option with the kind of link it is, or both kinds for a combined one.
export function linkChoices(
  wanted: readonly LinkType[],
  links: readonly SuggestedLink[],
  fullUrl: boolean,
): Choice[] {
  const detail = (value: string): string => {
    const link = links.find(
      (candidate) => value === candidate.url || value === shown(candidate.url),
    );
    return link === undefined
      ? wanted.map((type) => TYPE_LABELS[type]).join(" and ")
      : TYPE_LABELS[link.type];
  };
  return linkOptions(wanted, links, fullUrl).map((value) => ({
    value,
    detail: detail(value),
  }));
}

function linkTypesOf(element: FieldElement): readonly LinkType[] {
  if (element.localName !== "input") return [];
  const field = classify(element);
  return field.kind === "link" ? (field.linkTypes ?? []) : [];
}

// A url input, or a field tagged autocomplete="url" (Airtable's), wants a whole address.
function wantsUrl(element: FieldElement): boolean {
  if (parseAutocomplete(element.getAttribute("autocomplete"))?.field === "url")
    return true;
  return (
    element.localName === "input" &&
    (element as HTMLInputElement).type.toLowerCase() === "url"
  );
}

// The link types the page's fields ask for, so the links can be fetched before the first focus.
function wantedOnPage(doc: Document): LinkType[] {
  return [...new Set(fieldElements(doc, MAX_INSPECTED).flatMap(linkTypesOf))];
}

// When the person focuses a field that asks for a profile link, offers the card's links of
// those kinds in Safari's bar through a datalist, which goes away again when the field
// loses focus. Safari reads the list as the field takes focus, so the links are fetched
// when the page loads and the list is attached right away; a field that shows up later
// gets its list once the app answers. A field with a list of its own is left alone.
export function installLinks(doc: Document, options: LinkOptions): () => void {
  const isUserEvent =
    options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const attach = options.attach ?? attachDatalist;
  // Safari's bar takes a datalist's values as typing, which a page's combobox handles;
  // Prefill's own list would sit on top of the page's, so it skips fields that have one.
  const isTaken = (element: Element): boolean =>
    attach === attachDatalist
      ? element.hasAttribute("list")
      : hasOwnList(element);
  const gestures = trackGestures(doc, isUserEvent);
  let known:
    | { types: ReadonlySet<LinkType>; links: readonly SuggestedLink[] }
    | undefined;
  let detach: (() => void) | undefined;
  let focused: FieldElement | undefined;

  const clear = (): void => {
    detach?.();
    detach = undefined;
    focused = undefined;
  };

  const fetchLinks = (
    types: readonly LinkType[],
  ): Promise<readonly SuggestedLink[] | undefined> =>
    options
      .send({
        type: "linkSuggestions",
        host: options.host(),
        types: [...types],
      })
      .then((reply) => {
        const response = parseExtensionResponse(reply);
        if (response?.type !== "linkSuggestionsResult") return undefined;
        known = { types: new Set(types), links: response.links };
        return response.links;
      })
      .catch(() => undefined);

  const offer = (
    element: HTMLInputElement,
    wanted: readonly LinkType[],
    links: readonly SuggestedLink[] | undefined,
  ): void => {
    if (focused !== element || detach !== undefined || links === undefined)
      return;
    const choices = linkChoices(wanted, links, wantsUrl(element));
    if (choices.length > 0) detach = attach(element, choices);
  };

  const onFocus = (event: Event): void => {
    const target = isUserEvent(event) ? eventOrigin(event) : null;
    if (!isFieldElement(target) || isTaken(target)) return;
    const wanted = linkTypesOf(target);
    if (wanted.length === 0 || !gestures.allows(target)) return;
    clear();
    focused = target;
    suggest(target as HTMLInputElement, wanted);
  };

  const suggest = (
    element: HTMLInputElement,
    wanted: readonly LinkType[],
  ): void => {
    const cached = known;
    if (cached !== undefined && wanted.every((type) => cached.types.has(type)))
      offer(element, wanted, cached.links);
    const types = [...new Set([...(cached?.types ?? []), ...wanted])];
    void fetchLinks(types).then((links) => {
      offer(element, wanted, links);
    });
  };

  const onBlur = (event: Event): void => {
    if (eventOrigin(event) === focused) clear();
  };

  const prefetch = (): void => {
    const types = wantedOnPage(doc);
    if (types.length > 0) void fetchLinks(types);
  };

  if (doc.readyState === "loading")
    doc.addEventListener("DOMContentLoaded", prefetch, { once: true });
  else prefetch();
  doc.addEventListener("focusin", onFocus, true);
  doc.addEventListener("focusout", onBlur, true);
  return () => {
    clear();
    gestures.stop();
    doc.removeEventListener("DOMContentLoaded", prefetch);
    doc.removeEventListener("focusin", onFocus, true);
    doc.removeEventListener("focusout", onBlur, true);
  };
}
