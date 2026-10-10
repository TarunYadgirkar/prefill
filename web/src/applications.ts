import { isAtsHost } from "./atsFrames";
import { isPlaceholder } from "./choices";
import { classifyForCapture, isSignIn } from "./classify";
import { joinFieldText } from "./custom";
import { isDemographic } from "./demographics";
import { fieldElements, inferredLabel, isRendered, labelText, placeholderText } from "./dom";
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

function questionFor(element: FieldElement): string {
  const label = labelText(element) || inferredLabel(element) || placeholderText(element);
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

// A select often hides behind the page's own dropdown, so only typed fields must show.
function valueField(element: FieldElement): Field | undefined {
  if (element.localName !== "select" && !isRendered(element)) return undefined;
  const answer = element.localName === "select" ? selectAnswer(element as HTMLSelectElement) : element.value.trim();
  return answer === "" ? undefined : { question: questionFor(element), answer };
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

function collectFields(elements: readonly FieldElement[]): { fields: Field[]; files: FileName[] } {
  const groups = new Map(boxGroups(elements).map((group) => [group[0] as HTMLInputElement, group]));
  const fields = elements.flatMap((element) => fieldOf(element, groups) ?? []);
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

export function collectApplication(form: HTMLFormElement, doc: Document, host: string): ApplicationRequest | undefined {
  const elements = fieldElements(form, MAX_INSPECTED);
  if (!isApplication(elements, host)) return undefined;
  const { fields, files } = collectFields(elements);
  if (fields.length === 0 && files.length === 0) return undefined;
  const title = clean(doc.title.replace(HIDDEN, " "), LIMITS.text) || host;
  const path = clean(doc.location.pathname, LIMITS.path) || "/";
  return { type: "application", host, path, title, fields, files };
}
