// One-tap fill end to end in Chromium, with no Mac: the built Chrome extension, a stand-in
// for the native host and the Mac app (fakeHost.py), and the testbed application page.
// Runs on Linux and macOS. usage: node fillChrome.ts <screenshot dir>
import { spawn } from "node:child_process";
import { chmodSync, copyFileSync, cpSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";
import { chromium, type BrowserContext, type Page } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(here, "../..");
const extension = join(web, "dist-chrome");
const testbed = resolve(web, "../testbed");
const shots = resolve(process.argv[2] ?? join(tmpdir(), "prefill-e2e"));
const HOST = "com.tarunyadgirkar.prefill";
const EXTENSION_ID = "hnmpfjdamkhpfibdjpmdopohkcpfbfej";
// A fresh port each run, so a server left over from an interrupted run can't answer.
const PORT = 20_000 + Math.floor(Math.random() * 20_000);

function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(`FAIL ${message}`);
  console.log(`ok  ${message}`);
}

// Chrome looks for native hosts in the profile's own NativeMessagingHosts folder on Linux.
function installFakeHost(profile: string): void {
  const hostPath = join(here, "fakeHost.py");
  chmodSync(hostPath, 0o755);
  const folder = join(profile, "NativeMessagingHosts");
  mkdirSync(folder, { recursive: true });
  const manifest = { name: HOST, description: "Prefill test host", path: hostPath, type: "stdio", allowed_origins: [`chrome-extension://${EXTENSION_ID}/`] };
  writeFileSync(join(folder, `${HOST}.json`), JSON.stringify(manifest));
}

// The pill sits in a closed shadow root, so it is pressed where a person would press it:
// its first button, its last (Undo), or after a fill the "need you" button before Undo.
const PILL_SPOTS = { start: (x: number) => x + 30, end: (x: number, width: number) => x + width - 25, next: (x: number, width: number) => x + width - 100 };

async function pressPill(page: Page, where: keyof typeof PILL_SPOTS): Promise<void> {
  const pill = page.locator("prefill-fill");
  await pill.waitFor({ state: "visible", timeout: 5_000 });
  await page.waitForTimeout(600);
  const box = await pill.boundingBox();
  if (box === null) throw new Error("the pill has no box");
  await page.mouse.click(PILL_SPOTS[where](box.x, box.width), box.y + box.height / 2);
}

// After a fill the pill says how many fields need the person and moves to the first,
// whose own list opens: here the question only a guess answers.
async function checkNeedYou(page: Page): Promise<void> {
  await pressPill(page, "next");
  const focused = await page
    .waitForFunction(() => document.activeElement?.id === "why_us", null, { timeout: 5_000 })
    .then(() => true)
    .catch(() => false);
  await page.screenshot({ path: join(shots, "fill-chrome-need-you.png") });
  check(focused, "need you moves to the field the fill left empty");
  await page.locator("prefill-suggestions").waitFor({ state: "visible", timeout: 5_000 });
  check(true, "that field's list opens, with its guess");
  await page.emulateMedia({ colorScheme: "dark" });
  await page.screenshot({ path: join(shots, "fill-chrome-need-you-dark.png") });
  await page.emulateMedia({ colorScheme: "light" });
  check((await page.inputValue("#why_us")) === "", "a guess is never filled");
}

// What each field shows: a select's chosen text, an input's value, and the checked radio's label.
const values = (page: Page): Promise<Record<string, string>> =>
  page.evaluate(() => {
    const shown = (field: HTMLInputElement | HTMLSelectElement): string =>
      field instanceof HTMLSelectElement ? (field.selectedOptions[0]?.text ?? "") : field.value;
    const out = Object.fromEntries(
      [...document.querySelectorAll<HTMLInputElement | HTMLSelectElement>("input[id], select")].map((field) => [field.id, shown(field)]),
    );
    const radio = document.querySelector<HTMLInputElement>("input[type=radio]:checked");
    return { ...out, authorized: radio?.parentElement?.textContent.trim() ?? "" };
  });

// The testbed pages, plus the React-Select page bundled with the real library.
async function servedPages(): Promise<string> {
  const root = mkdtempSync(join(tmpdir(), "prefill-sites-"));
  cpSync(join(testbed, "sites"), root, { recursive: true });
  mkdirSync(join(root, "react-select"));
  copyFileSync(join(testbed, "react-select/index.html"), join(root, "react-select/index.html"));
  await build({
    entryPoints: [join(testbed, "react-select/page.mjs")],
    outfile: join(root, "react-select/page.js"),
    bundle: true,
    minify: true,
    nodePaths: [join(web, "node_modules")],
    define: { "process.env.NODE_ENV": '"production"' },
    logLevel: "error",
  });
  return root;
}

// Greenhouse's searchable dropdowns: one tap types or arrows into each and clicks the option.
async function checkReactSelect(context: BrowserContext): Promise<void> {
  const page = await context.newPage();
  await page.setViewportSize({ width: 900, height: 1000 });
  await page.goto(`http://127.0.0.1:${String(PORT)}/react-select/index.html`);
  await page.waitForTimeout(1_000);
  await page.click("#first_name");
  await pressPill(page, "start");
  await page.waitForFunction(() => document.querySelector('[data-answer="veteran_status"]')?.textContent !== "", null, { timeout: 15_000 });
  const answers: Record<string, string> = await page.evaluate(() =>
    Object.fromEntries(
      [...document.querySelectorAll("output[data-answer]")].map((node) => [node.getAttribute("data-answer") ?? "", node.textContent]),
    ),
  );
  await page.screenshot({ path: join(shots, "fill-chrome-react-select.png"), fullPage: true });
  check(answers.question_1 === "Yes", "one tap answers a React-Select yes/no question");
  check(answers.question_2 === "No", "one tap answers the sponsorship question");
  check(answers["school--0"] === "University of California, Berkeley", "one tap searches and picks the school");
  check(answers.gender === "Decline To Self Identify", "one tap declines gender in a React-Select");
  check(answers.veteran_status === "I don't wish to answer", "one tap declines veteran status in a React-Select");
  await page.close();
}

// Clicks a field and picks the list's row at `index` (0 is the first) from the keyboard.
async function pickRow(page: Page, selector: string, index: number): Promise<void> {
  await page.click(selector);
  await page.locator("prefill-suggestions").waitFor({ state: "visible", timeout: 5_000 });
  await page.waitForTimeout(600);
  for (let step = 0; step <= index; step += 1) await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
}

async function freshPage(page: Page): Promise<void> {
  await page.waitForTimeout(500);
  await page.goto(`http://127.0.0.1:${String(PORT)}/application.html`);
  await page.waitForTimeout(1_000);
}

// A value picked from a list comes first on the site from then on, a pick on a field Fill
// form filled included: the work email was picked there just before this.
async function checkPickRemembered(page: Page): Promise<void> {
  await freshPage(page);
  await pickRow(page, "#email", 0);
  check((await page.inputValue("#email")) === "alex@work.example.org", "a pick on a filled field is remembered too");
  await freshPage(page);
  await pickRow(page, "#email", 1);
  check((await page.inputValue("#email")) === "alex.rivera@example.com", "the second email can be picked");
  await freshPage(page);
  await pickRow(page, "#email", 0);
  check((await page.inputValue("#email")) === "alex.rivera@example.com", "the picked email comes first after a reload");
}

// A "Yes" that fits two options is left for the person and counted as need you, while the
// option that clearly says "No" is chosen.
async function checkTwoOptionsFit(context: BrowserContext): Promise<void> {
  const page = await context.newPage();
  await page.setViewportSize({ width: 900, height: 1000 });
  await page.waitForTimeout(500);
  await page.goto(`http://127.0.0.1:${String(PORT)}/questions.html`);
  await page.waitForTimeout(1_000);
  await page.click("#first_name");
  await pressPill(page, "start");
  await page.waitForFunction(() => (document.getElementById("email") as HTMLInputElement).value !== "", null, { timeout: 5_000 });
  await page.waitForTimeout(300);
  const shown = await values(page);
  check(shown.sponsorship === "No, I will not require sponsorship", "one tap chooses the one option that says No");
  check(shown.work_us === "Select ...", "a Yes two options fit is left for the person");
  const outlined = await page.evaluate(() => document.getElementById("work_us")?.style.getPropertyValue("outline") ?? "");
  check(outlined !== "", "the list two options fit is outlined");
  await page.screenshot({ path: join(shots, "fill-chrome-two-options.png") });
  await pressPill(page, "next");
  const moved = await page
    .waitForFunction(() => document.activeElement?.id === "work_us", null, { timeout: 5_000 })
    .then(() => true)
    .catch(() => false);
  check(moved, "need you moves to the list two options fit");
  await page.screenshot({ path: join(shots, "fill-chrome-two-options-note.png") });
  await page.close();
}

async function main(): Promise<void> {
  mkdirSync(shots, { recursive: true });
  const sites = await servedPages();
  const server = spawn("python3", ["-m", "http.server", String(PORT), "--bind", "127.0.0.1", "--directory", sites], { stdio: "ignore" });
  const profile = mkdtempSync(join(tmpdir(), "prefill-profile-"));
  installFakeHost(profile);
  process.env.PREFILL_FAKE_STATE = join(profile, "fake-host-state.json");
  // PREFILL_CHROMIUM points at a browser to use instead of Playwright's own download.
  const executablePath = process.env.PREFILL_CHROMIUM;
  const context = await chromium.launchPersistentContext(profile, {
    channel: "chromium",
    ...(executablePath === undefined ? {} : { executablePath }),
    headless: true,
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
  });
  try {
    const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
    check(worker.url().startsWith(`chrome-extension://${EXTENSION_ID}/`), "the extension loads with its fixed ID");
    const page = await context.newPage();
    await page.setViewportSize({ width: 900, height: 1100 });
    await page.waitForTimeout(500);
    await page.goto(`http://127.0.0.1:${String(PORT)}/application.html`);
    await page.waitForTimeout(1_000);

    await page.click("#first_name");
    await pressPill(page, "start");
    await page.waitForFunction(() => (document.getElementById("email") as HTMLInputElement).value !== "", null, { timeout: 5_000 });
    await page.waitForTimeout(300);
    const filled = await values(page);
    await page.screenshot({ path: join(shots, "fill-chrome-filled.png"), fullPage: true });
    check(filled.first_name === "Alex" && filled.last_name === "Rivera", "one tap fills the name");
    check(filled.email === "alex.rivera@example.com", "one tap fills the first email");
    check(filled.phone === "+1 (510) 555-0134", "one tap fills the phone");
    check(filled.question_1 === "www.linkedin.com/in/alexrivera", "one tap fills LinkedIn");
    check(filled.question_0 === "github.com/alexrivera - alexrivera.dev", "one tap fills GitHub/Portfolio with both links");
    check(filled.school === "University of California, Berkeley", "one tap fills a custom answer");
    check(filled.state === "California", "one tap picks the state in a select");
    check(filled.authorized === "Yes", "one tap answers a yes/no radio question");
    check(filled.gender === "Decline To Self Identify", "gender is declined");
    check(filled.hispanic === "Decline To Self Identify", "ethnicity is declined");
    check(filled.veteran === "I don't wish to answer", "veteran status is declined");
    check(filled.disability === "I do not want to answer", "disability is declined");
    await checkNeedYou(page);

    await pressPill(page, "end");
    await page.waitForTimeout(300);
    const undone = await values(page);
    check(undone.email === "" && undone.gender === "Please select" && undone.authorized === "", "Undo puts the form back");

    await page.click("#first_name");
    await pressPill(page, "start");
    await page.waitForFunction(() => (document.getElementById("email") as HTMLInputElement).value !== "", null, { timeout: 5_000 });
    await page.click("#email");
    await page.locator("prefill-suggestions").waitFor({ state: "visible", timeout: 5_000 });
    await page.screenshot({ path: join(shots, "fill-chrome-switch.png") });
    await page.waitForTimeout(600);
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("Enter");
    check((await page.inputValue("#email")) === "alex@work.example.org", "a tap on a filled field still offers the other email");
    await checkPickRemembered(page);
    await page.close();
    await checkReactSelect(context);
    await checkTwoOptionsFit(context);
  } finally {
    await context.close();
    server.kill();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
