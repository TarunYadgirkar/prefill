// One-tap fill end to end in Chromium, with no Mac: the built Chrome extension, a stand-in
// for the native host and the Mac app (fakeHost.py), and the testbed application page.
// Runs on Linux and macOS. usage: node fillChrome.ts <screenshot dir>
import { spawn } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, type Page } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(here, "../..");
const extension = join(web, "dist-chrome");
const sites = resolve(web, "../testbed/sites");
const shots = resolve(process.argv[2] ?? join(tmpdir(), "prefill-e2e"));
const HOST = "com.tarunyadgirkar.prefill";
const EXTENSION_ID = "hnmpfjdamkhpfibdjpmdopohkcpfbfej";
const PORT = 8765;

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

// The pill sits in a closed shadow root, so it is pressed where a person would press it.
async function pressPill(page: Page, where: "start" | "end"): Promise<void> {
  const pill = page.locator("prefill-fill");
  await pill.waitFor({ state: "visible", timeout: 5_000 });
  await page.waitForTimeout(600);
  const box = await pill.boundingBox();
  if (box === null) throw new Error("the pill has no box");
  await page.mouse.click(where === "start" ? box.x + 30 : box.x + box.width - 25, box.y + box.height / 2);
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

async function main(): Promise<void> {
  mkdirSync(shots, { recursive: true });
  const server = spawn("python3", ["-m", "http.server", String(PORT), "--bind", "127.0.0.1", "--directory", sites], { stdio: "ignore" });
  const profile = mkdtempSync(join(tmpdir(), "prefill-profile-"));
  installFakeHost(profile);
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
  } finally {
    await context.close();
    server.kill();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
