// Drives Playwright's Chrome for Testing with the built extension against a running test
// build of the Mac app (scripts/e2e-mac-chrome.sh sets it up). Run with node.
// usage: node macChrome.ts <extension dir> <profile dir> <page url> <screenshot path> [<airtable screenshot path>]
import { chromium, type BrowserContext, type Page, type Worker } from "playwright-core";

const [extension, profile, pageUrl, screenshot, airtableShot] = process.argv.slice(2);
// A real React form (Pear Prime's application) with names and emails in text areas. Only
// filled, never submitted.
const AIRTABLE = "https://airtable.com/appb7Nlzw1t0e8zq1/pagR9cksnxP2SINET/form";
const HOST = "com.tarunyadgirkar.prefill";
const EXPECTED = ["alex.rivera@example.com", "alex@work.example.org"];
const NEW_EMAIL = "alex.new@example.net";

function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
  console.log(`ok  ${message}`);
}

async function serviceWorker(context: BrowserContext): Promise<Worker> {
  return context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
}

// Picks the first row of Prefill's dropdown from the keyboard, as a person would.
async function pickFirst(page: Page, field: string): Promise<string> {
  const locator = page.getByLabel(field, { exact: true });
  await locator.click();
  await page.waitForTimeout(1_000);
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  return locator.inputValue();
}

async function checkAirtable(context: BrowserContext, shot: string): Promise<void> {
  const page = await context.newPage();
  await page.setViewportSize({ width: 1100, height: 760 });
  await page.goto(AIRTABLE, { waitUntil: "networkidle" });
  check((await pickFirst(page, "Phone")) === "+1 (510) 555-0134", "Airtable's tel field takes the card's phone");
  check((await pickFirst(page, "Github")) === "https://github.com/alexrivera", "Airtable's Github field takes the card's GitHub link");
  check((await pickFirst(page, "Full Name")) === "Alex Rivera", "Airtable's Full Name text area takes the card's name");
  await page.getByLabel("Resume Link", { exact: true }).click();
  await page.waitForTimeout(1_000);
  check(!(await page.locator("prefill-suggestions").isVisible()), "the Resume Link field offers no profile link");
  await page.getByLabel("Personal Email", { exact: true }).click();
  await page.waitForTimeout(1_000);
  check(await page.locator("prefill-suggestions").isVisible(), "the Personal Email text area shows Prefill's list");
  check((await page.getByLabel("Full Name", { exact: true }).inputValue()) === "Alex Rivera", "Airtable keeps the picked name after focus moves on");
  await page.screenshot({ path: shot });
  await page.close();
}

async function main(): Promise<void> {
  if (extension === undefined || profile === undefined || pageUrl === undefined || screenshot === undefined) {
    throw new Error("usage: macChrome.ts <extension> <profile> <page> <screenshot>");
  }
  const context = await chromium.launchPersistentContext(profile, {
    channel: "chromium",
    headless: true,
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
  });
  try {
    const worker = await serviceWorker(context);
    check(worker.url().startsWith("chrome-extension://hnmpfjdamkhpfibdjpmdopohkcpfbfej/"), "the extension loads with its fixed ID");
    const pong: unknown = await worker.evaluate(
      async (host) => (globalThis as unknown as { chrome: { runtime: { sendNativeMessage(h: string, m: unknown): Promise<unknown> } } }).chrome.runtime.sendNativeMessage(host, { type: "ping" }),
      HOST,
    );
    check(JSON.stringify(pong) === '{"type":"pong"}', "the native host relays a ping to the app and back");

    const page = await context.newPage();
    await page.goto(pageUrl);
    await page.waitForTimeout(1_500);
    await page.click("#email");
    await page.locator("prefill-suggestions").waitFor({ timeout: 5_000 });
    await page.screenshot({ path: screenshot });
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("Enter");
    const picked = await page.inputValue("#email");
    check(EXPECTED.includes(picked), `the email field takes one of the card's emails: ${picked}`);

    await page.fill("#email", "");
    await page.locator("#email").pressSequentially(NEW_EMAIL);
    await page.click("button[type=submit]");
    await page.waitForTimeout(1_500);
    if (airtableShot !== undefined) await checkAirtable(context, airtableShot);
  } finally {
    await context.close();
  }
}

await main();
