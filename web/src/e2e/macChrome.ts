// Drives Playwright's Chrome for Testing with the built extension against a running test
// build of the Mac app (scripts/e2e-mac-chrome.sh sets it up). Run with node.
// usage: node macChrome.ts <extension dir> <profile dir> <page url> <screenshot path>
import { chromium, type BrowserContext, type Worker } from "playwright-core";

const [extension, profile, pageUrl, screenshot] = process.argv.slice(2);
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
    await page.waitForFunction(() => document.querySelector("#email")?.getAttribute("list") !== null, undefined, { timeout: 5_000 });
    const options = await page.$$eval("datalist option", (nodes) => nodes.map((node) => (node as HTMLOptionElement).value));
    check(EXPECTED.every((email) => options.includes(email)), `the email field offers the card's emails: ${options.join(", ")}`);

    await page.evaluate((shown) => {
      const readout = document.createElement("div");
      readout.id = "readout";
      readout.textContent = `Datalist Prefill attached to the focused email field:\n${shown.join("\n")}`;
      document.body.append(readout);
    }, options);
    await page.screenshot({ path: screenshot });

    await page.fill("#email", "");
    await page.locator("#email").pressSequentially(NEW_EMAIL);
    await page.click("button[type=submit]");
    await page.waitForTimeout(1_500);
  } finally {
    await context.close();
  }
}

await main();
