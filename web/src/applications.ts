import { isAtsHost } from "./atsFrames";
import { isPlaceholder } from "./choices";
import { comboboxChoice, isCombobox } from "./combobox";
import { classifyForCapture, isSignIn } from "./classify";
import { joinFieldText } from "./custom";
import { eventOrigin, fieldElements, inferredLabel, isRendered, labelForName, labelText, nearbyText, placeholderText } from "./dom";
import type { FieldElement } from "./fieldTypes";
import { questionOf } from "./fill";
import { jobQuestion } from "./learn";
import { LIMITS, type ApplicationRequest } from "./messages";

// The record of a job application the person sent: every question on the form with what
// went in, and the names of the files uploaded, so they can look up later which resume,
// graduation date or essay went where. Sensitive fields (passwords, card, ID, codes,
// signatures) are never read. Demographic answers are kept: the record is the person's own.
// Only the page's path is kept, never its query, which can carry tokens.

type Field = ApplicationRequest["fields"][number];
// A field as read, with the element it came from, for the checks that look around it.
type Read = Field & { source: Element };
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
  const label =
    joinFieldText([own]) || labelText(element) || joinFieldText([labelForName(element)]) || inferredLabel(element) ||
    placeholderText(element) || nearbyText(element);
  return joinFieldText([label]);
}

// Sensitive fields (passwords, card, ID, codes, signatures) never go in. Demographic answers
// do: the record is the person's own, and they want it to show how they answered.
function isPrivate(read: Read): boolean {
  const source = read.source;
  const isField = source instanceof HTMLInputElement || source instanceof HTMLSelectElement || source instanceof HTMLTextAreaElement;
  return isField && classifyForCapture(source).kind === "sensitive";
}

function selectAnswer(select: HTMLSelectElement): string {
  return [...select.selectedOptions]
    .filter((option) => !isPlaceholder({ text: option.text, value: option.value }))
    .map((option) => option.text.trim())
    .join(", ");
}

// A radio or checkbox group answers once, with the labels of the boxes the person checked.
// A group the page hides entirely (Ashby keeps one under its Yes and No buttons) says
// nothing the buttons don't.
function groupField(boxes: readonly HTMLInputElement[]): Read | undefined {
  const checked = boxes.filter((box) => box.checked);
  const first = boxes[0];
  if (checked.length === 0 || first === undefined || !boxes.some(isShown)) return undefined;
  const question = boxes.length === 1 ? questionFor(first) : questionOf([...boxes]) || questionFor(first);
  const answer = boxes.length === 1 && first.type === "checkbox" ? "Checked" : checked.map(labelText).join(", ");
  return { question: question.replace(HIDDEN, " "), answer, source: first };
}

// A custom radio hides its input but shows its label.
function isShown(box: HTMLInputElement): boolean {
  return isRendered(box) || [...(box.labels ?? [])].some(isRendered);
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
function valueField(element: FieldElement): Read | undefined {
  const hidesItself = element.localName === "select" || isCombobox(element);
  if (!hidesItself && !isRendered(element)) return undefined;
  const answer = answerOf(element);
  return answer === "" ? undefined : { question: questionFor(element), answer, source: element };
}

const PRESSED = "button[aria-pressed=true], [role=radio][aria-checked=true], [role=checkbox][aria-checked=true]";

// Yes/No buttons a page draws instead of radios (Ashby's), answered by the pressed one.
function pressedFields(scope: ParentNode): Read[] {
  return [...scope.querySelectorAll(PRESSED)].flatMap((button) => {
    const answer = (button.getAttribute("aria-label") ?? button.textContent).trim();
    const question = nearbyText(button.parentElement ?? button);
    return answer === "" || question === "" ? [] : [{ question, answer, source: button }];
  });
}

function fileNames(element: FieldElement): FileName[] {
  const files = (element as HTMLInputElement).files;
  if (files === null) return [];
  const question = questionFor(element) || "File";
  return [...files].map((file) => ({ question, name: clean(file.name, LIMITS.text) }));
}

// Without its question an answer can't be looked up, so it isn't kept.
function fitted(fields: readonly Read[]): Field[] {
  const seen = new Set<string>();
  let left = ANSWER_BUDGET;
  return fields.flatMap((field) => {
    if (isPrivate(field)) return [];
    const question = clean(field.question, LIMITS.fieldText);
    if (question === "") return [];
    const answer = clean(field.answer, Math.min(LIMITS.applicationAnswer, left));
    const key = `${question}\n${answer}`;
    if (answer === "" || seen.has(key)) return [];
    seen.add(key);
    left -= answer.length;
    return [{ question, answer }];
  }).slice(0, LIMITS.applicationFields);
}

function boxField(box: HTMLInputElement, groups: ReadonlyMap<HTMLInputElement, HTMLInputElement[]>): Read | undefined {
  const group = groups.get(box);
  const field = group === undefined ? undefined : groupField(group);
  return field === undefined || group?.some((member) => isPrivate({ ...field, source: member })) === true ? undefined : field;
}

function fieldOf(element: FieldElement, groups: ReadonlyMap<HTMLInputElement, HTMLInputElement[]>): Read | undefined {
  const type = typeOf(element);
  if (SKIPPED_TYPES.has(type) || type === "file") return undefined;
  return type === "radio" || type === "checkbox" ? boxField(element as HTMLInputElement, groups) : valueField(element);
}

// The answers the person gave by clicking one of a question's buttons, by the buttons' row.
export type ButtonChoices = ReadonlyMap<Element, string>;

function chosenFields(scope: ParentNode, chosen: ButtonChoices): Read[] {
  return [...chosen].flatMap(([row, answer]) => {
    if (!row.isConnected || !(scope === row.ownerDocument || (scope as Node).contains(row))) return [];
    const question = nearbyText(row);
    return question === "" ? [] : [{ question, answer, source: row }];
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
// A careers site's own application (amazon.jobs, careers.example.com/apply) says so in its address.
const APPLICATION_PAGE = /(?:^|[./-])(?:jobs?|careers?|apply|application|recruit\w*|talent|hiring)(?:$|[./-])/iu;

// A sign-in step never counts, even one that asks only for an email (iCIMS's /login).
const SIGN_IN_PAGE = /\/(?:log-?in|log-?on|sign-?in)\/?$/iu;

// A sign-in form never counts. On an application's own site (amazon.jobs) every step counts,
// whatever it asks; the page's session storage can't make any other page count.
function isApplication(elements: readonly FieldElement[], hostname: string, path: string): boolean {
  if (SIGN_IN_PAGE.test(path) || elements.some((element) => isSignIn(element))) return false;
  if (isAtsHost(hostname) || APPLICATION_PAGE.test(hostname) || APPLICATION_PAGE.test(path)) return true;
  if (elements.some((element) => typeOf(element) === "file")) return true;
  return elements.some((element) => jobQuestion(questionFor(element)) !== undefined);
}

function pageOf(doc: Document, host: string): { path: string; title: string } {
  return {
    path: clean(doc.location.pathname, LIMITS.path) || "/",
    title: clean(doc.title.replace(HIDDEN, " "), LIMITS.text) || host,
  };
}

export function collectApplication(
  scope: ParentNode,
  doc: Document,
  host: string,
  id: string,
  chosen: ButtonChoices = new Map(),
): ApplicationRequest | undefined {
  const elements = fieldElements(scope, MAX_INSPECTED);
  if (!isApplication(elements, host, doc.location.pathname)) return undefined;
  const { fields, files } = collectFields(scope, elements, chosen);
  if (fields.length === 0 && files.length === 0) return undefined;
  return { type: "application", id, host, ...pageOf(doc, host), fields, files };
}

export interface ApplicationOptions {
  host: () => string;
  send: (request: ApplicationRequest) => void;
  isUserEvent?: (event: Event) => boolean;
  newID?: () => string;
  now?: () => number;
}

// The words on a button that sends the application, for forms that never fire a submit event.
const SEND_WORDS = /\b(?:submit|send|apply)\b/iu;
// After the click, so the page's own handler has run and the fields read as sent.
const CLICK_DELAY_MS = 300;
// Buttons that pick, take back or show a file, which answer nothing.
const FILE_WORDS = /upload|attach|browse|choose file|drag|remove|replace|delete|clear|view|download/iu;
// A choice button says a word or two ("Yes", "No", "Remote"), never a sentence.
const MAX_CHOICE_LENGTH = 40;

// The words on a button that moves a multi-step application on (Amazon's, Workday's).
const STEP_WORDS = /\b(?:continue|next|save|review|proceed)\b/iu;

type Press = { button: Element; sends: boolean };

// A press on a button that sends the application or moves it to its next step.
function pressOf(target: EventTarget | null): Press | undefined {
  if (!(target instanceof Element)) return undefined;
  const button = target.closest("button, [role=button], input[type=submit]");
  if (button === null) return undefined;
  const words = button instanceof HTMLInputElement ? button.value : (button.getAttribute("aria-label") ?? button.textContent);
  if (SEND_WORDS.test(words)) return { button, sends: true };
  return STEP_WORDS.test(words) ? { button, sends: false } : undefined;
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
  const isAction = SEND_WORDS.test(answer) || STEP_WORDS.test(answer) || FILE_WORDS.test(answer);
  const isChoice = answer !== "" && answer.length <= MAX_CHOICE_LENGTH && !isAction;
  return isChoice && row.querySelector("input[type=file]") === null ? [row, answer] : undefined;
}

// One application can span several pages of a tab (Amazon's steps), so its id lives in the
// tab's session storage under this key until the person sends it. Storage can be off; then
// each page gets its own id.
const SESSION_KEY = "prefill.application";

// An application left this long between steps is over: the next one starts fresh.
const SESSION_MS = 30 * 60_000;
const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/iu;

interface Session {
  id: string;
  // Whether a step of it was recorded, so that a press on Submit ends it.
  recorded: boolean;
  host: string;
  // When its last step was recorded.
  at: number;
}

// The page can write its own session storage, so a stored session counts only for the same
// host, within the time, and (in collectApplication) only on a page that looks like an
// application by its address.
function storedSession(win: Window): Partial<Session> | undefined {
  try {
    const parsed: unknown = JSON.parse(win.sessionStorage.getItem(SESSION_KEY) ?? "null");
    return typeof parsed === "object" && parsed !== null ? (parsed) : undefined;
  } catch {
    return undefined;
  }
}

const isSession = (value: Partial<Session>): value is Session =>
  typeof value.id === "string" && UUID.test(value.id) && typeof value.recorded === "boolean" && typeof value.at === "number";

function readSession(win: Window, host: string, now: number): Session | undefined {
  const stored = storedSession(win);
  if (stored === undefined || !isSession(stored)) return undefined;
  return stored.host === host && now - stored.at >= 0 && now - stored.at < SESSION_MS ? stored : undefined;
}

function writeSession(win: Window, session: Session | undefined): void {
  try {
    if (session === undefined) win.sessionStorage.removeItem(SESSION_KEY);
    else win.sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch {
    // Storage off: this page's record stands alone.
  }
}

// Records what was sent. Every step and send of one application carries the same id, and the
// app combines them, so a resend after the page turned an answer away replaces the earlier
// answers instead of adding a second record. `record` is also what the submit gate in
// learn.ts calls for a form's real submit event.
export function installApplications(doc: Document, win: Window, options: ApplicationOptions) {
  const isUserEvent = options.isUserEvent ?? ((event: Event) => event.isTrusted);
  const newID = options.newID ?? (() => win.crypto.randomUUID());
  const now = options.now ?? (() => Date.now());
  const fresh = (): Session => ({ id: newID(), recorded: false, host: options.host(), at: now() });
  let session = readSession(win, options.host(), now()) ?? fresh();
  const chosen = new Map<Element, string>();
  // `sends` is a press on a Submit, Send or Apply button: after it the next application in
  // this tab starts fresh. A form's own submit event may be one step of several, so it doesn't.
  const record = (scope: ParentNode, sends: boolean): void => {
    if (readSession(win, options.host(), now())?.id !== session.id && session.recorded) session = fresh();
    const application = collectApplication(scope, doc, options.host(), session.id, chosen);
    if (application !== undefined) {
      options.send(application);
      session = { ...session, recorded: true, at: now() };
    }
    if (sends && session.recorded) {
      session = fresh();
      chosen.clear();
    }
    writeSession(win, session.recorded ? session : undefined);
  };
  const click = (event: Event): void => {
    if (!isUserEvent(event)) return;
    const choice = choiceOf(eventOrigin(event));
    if (choice !== undefined) chosen.set(...choice);
    const press = pressOf(eventOrigin(event));
    if (press === undefined) return;
    const scope = press.button.closest("form") ?? doc;
    win.setTimeout(() => {
      record(scope, press.sends);
    }, CLICK_DELAY_MS);
  };
  doc.addEventListener("click", click, true);
  return {
    record: (scope: ParentNode) => {
      record(scope, false);
    },
    stop: () => {
      doc.removeEventListener("click", click, true);
    },
  };
}
