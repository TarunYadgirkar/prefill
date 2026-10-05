// Drives a visible Chrome for Testing, without the extension, against a running test copy
// of the Mac app with Accessibility (scripts/e2e-mac-ax.sh sets it up). Focus moves from
// Playwright, never from the person's mouse or keyboard; the test copy picks the first row
// itself. Run with node.
// The extension is loaded too, and has to stand down while the app's panel shows.
// usage: node macAx.ts <extension dir> <profile dir> <page url> <screenshot path> [airtable]
import { execFileSync, spawn } from "node:child_process";
import { chromium, type Locator, type Page } from "playwright-core";

const [extension, profile, pageUrl, screenshot, airtable] = process.argv.slice(2);
// A real React form with names and emails in text areas. Only filled, never submitted.
const AIRTABLE = "https://airtable.com/appb7Nlzw1t0e8zq1/pagR9cksnxP2SINET/form";
const EMAILS = ["alex.rivera@example.com", "alex@work.example.org", "alex.school@example.edu"];
// The test app picks after PREFILL_E2E_AX_AUTOPICK seconds.
const PICK_WAIT_MS = 4_000;
// Chrome builds its web content's Accessibility tree a few seconds after the app asks.
const TREE_WAIT_MS = 5_000;
const DEBUG_PORT = "9334";

function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
  console.log(`ok  ${message}`);
}

function bringToFront(): void {
  execFileSync("osascript", ["-e", 'tell application id "com.google.chrome.for.testing" to activate']);
}

// The element's box on screen in points, for screencapture -R.
async function screenBox(page: Page, locator: Locator): Promise<{ x: number; y: number; width: number; height: number }> {
  const box = await locator.boundingBox();
  if (box === null) throw new Error("field not on screen");
  const offset = await page.evaluate(() => ({
    x: window.screenX + (window.outerWidth - window.innerWidth),
    y: window.screenY + (window.outerHeight - window.innerHeight),
  }));
  return { x: offset.x + box.x, y: offset.y + box.y, width: box.width, height: box.height };
}

async function pickInto(page: Page, locator: Locator): Promise<string> {
  await locator.focus();
  await page.waitForTimeout(PICK_WAIT_MS);
  return locator.inputValue();
}

async function checkAirtable(page: Page): Promise<void> {
  await page.goto(AIRTABLE, { waitUntil: "networkidle" });
  bringToFront();
  const name = page.getByLabel("Full Name", { exact: true });
  check((await pickInto(page, name)) === "Alex Rivera", "Airtable's Full Name text area takes the card's name");
  const phone = page.getByLabel("Phone", { exact: true });
  check((await pickInto(page, phone)) !== "", "Airtable's Phone field takes a phone number");
  await page.getByLabel("Personal Email", { exact: true }).focus();
  await page.waitForTimeout(PICK_WAIT_MS);
  check((await name.inputValue()) === "Alex Rivera", "Airtable keeps the picked name after React re-renders the form");
}

// Started directly with the page, as from the Dock, so the page has the window's focus;
// Playwright then attaches over the debugging port.
async function openChrome(extensionDir: string, dir: string, url: string): Promise<{ page: Page; close: () => void }> {
  const chrome = spawn(
    chromium.executablePath(),
    [
      `--user-data-dir=${dir}`,
      `--remote-debugging-port=${DEBUG_PORT}`,
      `--disable-extensions-except=${extensionDir}`,
      `--load-extension=${extensionDir}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--window-size=900,700",
      url,
    ],
    { stdio: "ignore" },
  );
  await new Promise((resolve) => setTimeout(resolve, 3_000));
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${DEBUG_PORT}`);
  const page = browser.contexts()[0]?.pages()[0];
  if (page === undefined) throw new Error("Chrome opened no page");
  return { page, close: () => chrome.kill() };
}

async function main(): Promise<void> {
  if (extension === undefined || profile === undefined || pageUrl === undefined || screenshot === undefined) {
    throw new Error("usage: macAx.ts <extension> <profile> <page> <screenshot> [airtable]");
  }
  const { page, close } = await openChrome(extension, profile, pageUrl);
  try {
    bringToFront();
    await page.waitForTimeout(TREE_WAIT_MS);
    const email = page.locator("#email");
    // A click the page sees as the person's, so the extension would show its list if it didn't stand down.
    await email.click();
    await page.waitForTimeout(1_500);
    const box = await screenBox(page, email);
    const region = [box.x - 24, box.y - 24, Math.max(box.width, 420) + 48, 300].map(Math.round).join(",");
    // The picture is a record, not a check: a locked screen can't be captured, and the fill still runs.
    try {
      execFileSync("screencapture", ["-x", `-R${region}`, screenshot], { stdio: "pipe" });
    } catch {
      console.log("no screenshot: the screen can't be captured right now (locked or asleep)");
    }
    check(!(await page.locator("prefill-suggestions").isVisible()), "the extension shows no list of its own beside the app's panel");
    await page.waitForTimeout(PICK_WAIT_MS);
    const picked = await email.inputValue();
    check(EMAILS.includes(picked), `the email field takes one of the card's emails: ${picked}`);
    // Fill form: with the email emptied again, the test copy presses it from the phone field.
    await email.fill("");
    await page.locator("#phone").click();
    await page.waitForTimeout(TREE_WAIT_MS / 2 + PICK_WAIT_MS);
    const phone = await page.locator("#phone").inputValue();
    check(phone !== "" && EMAILS.includes(await email.inputValue()), `Fill form fills the phone and the email: ${phone}`);
    if (airtable === "airtable") await checkAirtable(page);
  } finally {
    close();
  }
}

await main();
