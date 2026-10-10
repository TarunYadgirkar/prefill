import { isAtsHost } from "./atsFrames";
import { isPlaceholder } from "./choices";
import { comboboxChoice, isCombobox } from "./combobox";
import { classifyForCapture, isSignIn } from "./classify";
import { joinFieldText } from "./custom";
import { isDemographic } from "./demographics";
import { eventOrigin, fieldElements, inferredLabel, isRendered, labelText, nearbyText, placeholderText } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { questionOf } from "./fill";
import { jobQuestion } from "./learn";
import { LIMITS, type ApplicationRequest } from "./messages";

// The record of a job application the person sent: every question on the form with what
// went in, and the names of the files uploaded, so they can look up later which resume,
// graduation date or essay went where. Sensitive fields (passwords, card, ID, codes,
// signatures) and demographic questions are never read. Only the page's path is kept, never
// its query, which can carry tokens.

type Field = ApplicationRequest["fields"][number];
type FileName = ApplicationRequest["files"][number];

const MAX_INSPECTED = 300;
// The whole record has to fit in one message, so long essays share this many characters.
const ANSWER_BUDGET = 48_000;
const SKIPPED_TYPES: ReadonlySet<string> = new Set(["hidden", "password", "submit", "button", "reset", "image"]);
const HIDDEN = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu;

function clean(text: string, max: number): string {
  const flat = text.replace(/\r\n?/gu, "\n").replace(/[^\P{Cc}\n]|[\p{Cf}\p{Zl}\p{Zp}]/gu, " ").trim();
  return flat.slice(0, max).replace(/[\uD800-\uDBFF]$/u, "");
}

const typeOf = (element: FieldElement): string =>
  element.localName === "input" ? (element as HTMLInputElement).type.toLowerCase() : element.localName;

// The field's own label first: labelText joins it with aria-labelledby, which on Greenhouse
// names the same label again.
function questionFor(element: FieldElement): string {
  const own = [...(element.labels ?? [])].map((label) => label.textContent).join(" ");
  const label = joinFieldText([own]) || labelText(element) || inferredLabel(element) || placeholderText(element);
  return joinFieldText([label]);
}

function isPrivate(element: FieldElement, question: string): boolean {
  return classifyForCapture(element).kind === "sensitive" || isDemographic(question);
}

function selectAnswer(select: HTMLSelectElement): string {
  return [...select.selectedOptions]
    .filter((option) => !isPlaceholder({ text: option.text, value: option.value }))
    .map((option) => option.text.trim())
    .join(", ");
}

// A radio or checkbox group answers once, with the labels of the boxes the person checked.
function groupField(boxes: readonly HTMLInputElement[]): Field | undefined {
  const checked = boxes.filter((box) => box.checked);
  if (checked.length === 0) return undefined;
  const question = boxes.length === 1 ? questionFor(boxes[0] as HTMLInputElement) : questionOf([...boxes]);
  const answer = boxes.length === 1 && boxes[0]?.type === "checkbox" ? "Checked" : checked.map(labelText).join(", ");
  return { question: question.replace(HIDDEN, " "), answer };
}

function groupKey(box: HTMLInputElement): string {
  return box.name === "" ? `#${String(Math.random())}` : `${box.type}:${box.name}`;
}

function boxGroups(elements: readonly FieldElement[]): HTMLInputElement[][] {
  const groups = new Map<string, HTMLInputElement[]>();
  for (const element of elements) {
    const type = typeOf(element);
    if (type !== "radio" && type !== "checkbox") continue;
    const box = element as HTMLInputElement;
    const key = groupKey(box);
    groups.set(key, [...(groups.get(key) ?? []), box]);
  }
  return [...groups.values()];
}

function answerOf(element: FieldElement): string {
  if (element.localName === "select") return selectAnswer(element as HTMLSelectElement);
  if (isCombobox(element)) return comboboxChoice(element as HTMLInputElement);
  return element.value.trim();
}

// A select often hides behind the page's own dropdown, and a searchable dropdown's text box
// shrinks once something is chosen, so only plain typed fields must show.
function valueField(element: FieldElement): Field | undefined {
  const hidesItself = element.localName === "select" || isCombobox(element);
  if (!hidesItself && !isRendered(element)) return undefined;
  const answer = answerOf(element);
  return answer === "" ? undefined : { question: questionFor(element), answer };
}

const PRESSED = "button[aria-pressed=true], [role=radio][aria-checked=true], [role=checkbox][aria-checked=true]";

// Yes/No buttons a page draws instead of radios (Ashby's), answered by the pressed one.
function pressedFields(scope: ParentNode): Field[] {
  return [...scope.querySelectorAll(PRESSED)].flatMap((button) => {
    const answer = (button.getAttribute("aria-label") ?? button.textContent).trim();
    const question = nearbyText(button.parentElement ?? button);
    return answer === "" || question === "" || isDemographic(question) ? [] : [{ question, answer }];
  });
}

function fileNames(element: FieldElement): FileName[] {
  const files = (element as HTMLInputElement).files;
  if (files === null) return [];
  const question = questionFor(element) || "File";
  return [...files].map((file) => ({ question, name: clean(file.name, LIMITS.text) }));
}

function fitted(fields: readonly Field[]): Field[] {
  const seen = new Set<string>();
  let left = ANSWER_BUDGET;
  return fields.flatMap((field) => {
    const question = clean(field.question, LIMITS.fieldText) || "Untitled question";
    const answer = clean(field.answer, Math.min(LIMITS.applicationAnswer, left));
    const key = `${question}\n${answer}`;
    if (answer === "" || seen.has(key)) return [];
    seen.add(key);
    left -= answer.length;
    return [{ question, answer }];
  }).slice(0, LIMITS.applicationFields);
}

function boxField(box: HTMLInputElement, groups: ReadonlyMap<HTMLInputElement, HTMLInputElement[]>): Field | undefined {
  const group = groups.get(box);
  const field = group === undefined ? undefined : groupField(group);
  return field === undefined || group?.some((member) => isPrivate(member, field.question)) === true ? undefined : field;
}

function textField(element: FieldElement): Field | undefined {
  const field = valueField(element);
  return field === undefined || isPrivate(element, field.question) ? undefined : field;
}

function fieldOf(element: FieldElement, groups: ReadonlyMap<HTMLInputElement, HTMLInputElement[]>): Field | undefined {
  const type = typeOf(element);
  if (SKIPPED_TYPES.has(type) || type === "file") return undefined;
  return type === "radio" || type === "checkbox" ? boxField(element as HTMLInputElement, groups) : textField(element);
}

// The answers the person gave by clicking one of a question's buttons, by the buttons' row.
export type ButtonChoices = ReadonlyMap<Element, string>;

function chosenFields(scope: ParentNode, chosen: ButtonChoices): Field[] {
  return [...chosen].flatMap(([row, answer]) => {
    if (!row.isConnected || !(scope === row.ownerDocument || (scope as Node).contains(row))) return [];
    const question = nearbyText(row);
    return question === "" || isDemographic(question) ? [] : [{ question, answer }];
  });
}

function collectFields(
  scope: ParentNode,
  elements: readonly FieldElement[],
  chosen: ButtonChoices,
): { fields: Field[]; files: FileName[] } {
  const groups = new Map(boxGroups(elements).map((group) => [group[0] as HTMLInputElement, group]));
  const fields = [
    ...elements.flatMap((element) => fieldOf(element, groups) ?? []),
    ...pressedFields(scope),
    ...chosenFields(scope, chosen),
  ];
  const files = elements.filter((element) => typeOf(element) === "file").flatMap(fileNames);
  return { fields: fitted(fields), files: files.slice(0, LIMITS.applicationFiles) };
}

// A form counts as a job application on a job application host, or when it uploads a file
// or asks one of the questions applications ask (school, sponsorship and the like).
function isApplication(elements: readonly FieldElement[], hostname: string): boolean {
  if (elements.some((element) => isSignIn(element))) return false;
  if (isAtsHost(hostname)) return true;
  if (elements.some((element) => typeOf(element) === "file")) return true;
  return elements.some((element) => jobQuestion(questionFor(element)) !== undefined);
}

export function collectApplication(
  scope: ParentNode,
  doc: Document,
  host: string,
  id: string,
  chosen: ButtonChoices = new Map(),
): ApplicationRequest | undefined {
  const elements = fieldElements(scope, MAX_INSPECTED);
  if (!isApplication(elements, host)) return undefined;
  const { fields, files } = collectFields(scope, elements, chosen);
  if (fields.length === 0 && files.length === 0) return undefined;
  const title = clean(doc.title.replace(HIDDEN, " "), LIMITS.text) || host;
  const path = clean(doc.location.pathname, LIMITS.path) || "/";
  return { type: "application", id, host, path, title, fields, files };
}

export interface ApplicationOptions {
  host: () => string;
  send: (request: ApplicationRequest) => void;
  isUserEvent?: (event: Event) => boolean;
  newID?: () => string;
}

// The words on a button that sends the application, for forms that never fire a submit event.
const SEND_WORDS = /\b(?:submit|send|apply)\b/iu;
// After the click, so the page's own handler has run and the fields read as sent.
const CLICK_DELAY_MS = 300;
// A choice button says a word or two ("Yes", "No", "Remote"), never a sentence.
const MAX_CHOICE_LENGTH = 40;

function sendButton(target: EventTarget | null): Element | undefined {
  if (!(target instanceof Element)) return undefined;
  const button = target.closest("button, [role=button], input[type=submit]");
  if (button === null) return undefined;
  const words = button instanceof HTMLInputElement ? button.value : (button.getAttribute("aria-label") ?? button.textContent);
  return SEND_WORDS.test(words) ? button : undefined;
}

// The row of buttons a click picked an answer in, with the answer: a short button that
// doesn't send the form or upload a file. Ashby draws its questions outside its own form.
function choiceRow(target: EventTarget | null): [Element, Element] | undefined {
  const button = target instanceof Element ? target.closest("button, [role=button]") : null;
  const row = button?.parentElement ?? null;
  return button === null || row === null ? undefined : [button, row];
}

function choiceOf(target: EventTarget | null): [Element, string] | undefined {
  const found = choiceRow(target);
  if (found === undefined) return undefined;
  const [button, row] = found;
  const answer = button.textContent.trim();
  const isChoice = answer !== "" && answer.length <= MAX_CHOICE_LENGTH && !SEND_WORDS.test(answer);
  return isChoice && row.querySelector("input[type=file]") === null ? [row, answer] : undefined;
}

// Records what was sent, once per page: a later send from the same page (after the page
// turned an answer away, say) replaces the earlier record, since it carries the same id.
// `record` is also what the submit gate in learn.ts calls for a form's real submit event.
export function installApplications(doc: Document, win: Window, options: ApplicationOptions) {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const newID = options.newID ?? (() => win.crypto.randomUUID());
  let page = { path: doc.location.pathname, id: newID() };
  const idForPage = (): string => {
    if (page.path !== doc.location.pathname) {
      page = { path: doc.location.pathname, id: newID() };
      chosen.clear();
    }
    return page.id;
  };
  const record = (scope: ParentNode): void => {
    const application = collectApplication(scope, doc, options.host(), idForPage(), chosen);
    if (application !== undefined) options.send(application);
  };
  const chosen = new Map<Element, string>();
  const choose = (target: EventTarget | null): void => {
    const choice = choiceOf(target);
    if (choice !== undefined) chosen.set(...choice);
  };
  const click = (event: Event): void => {
    if (!isUserEvent(event)) return;
    choose(eventOrigin(event));
    const button = sendButton(eventOrigin(event));
    if (button === undefined) return;
    const scope = button.closest("form") ?? doc;
    win.setTimeout(() => {
      record(scope);
    }, CLICK_DELAY_MS);
  };
  doc.addEventListener("click", click, true);
  return {
    record,
    stop: () => {
      doc.removeEventListener("click", click, true);
    },
  };
}
