// Receives Prefill's applications and adds each to the first tab of the sheet it is bound to,
// newest at the top, under one header row:
// Date applied | Company | Role | Type | Status | Last update | Found in | Email
//
// Set up once, from the "Job Applications" sheet:
//   1. Extensions, Apps Script. Replace the editor's code with this file. Save.
//   2. Deploy, New deployment, type Web app. Execute as: Me. Who has access: Anyone. Deploy.
//   3. Allow access with your Google account when asked.
//   4. Copy the Web app URL (it ends in /exec) into Prefill's Google Sheet setting on the
//      iPhone and the Mac.
//
// The URL is the only key: keep it private. An application the sheet already lists (by
// Prefill's id, or the same company and role) is skipped, so both devices can send it.

const HEADER_ROWS = 1;
const COLUMNS = 8;
const MAX_ROWS = 200;

function doPost(e) {
  let body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (error) {
    return reply({ error: 'Not JSON' });
  }
  const rows = Array.isArray(body.rows) ? body.rows.slice(0, MAX_ROWS) : [];
  const lock = LockService.getDocumentLock();
  lock.waitLock(20000);
  try {
    return reply(add(SpreadsheetApp.getActiveSpreadsheet().getSheets()[0], rows));
  } finally {
    lock.releaseLock();
  }
}

function add(sheet, rows) {
  const count = Math.max(sheet.getLastRow() - HEADER_ROWS, 0);
  const listed = count ? sheet.getRange(HEADER_ROWS + 1, 1, count, 3).getValues() : [];
  const notes = count ? sheet.getRange(HEADER_ROWS + 1, 1, count, 1).getNotes() : [];
  const keys = new Set(listed.map((row) => key(row[1], row[2])));
  const ids = new Set(notes.map((row) => row[0]).filter(Boolean));
  const added = [];
  const skipped = [];
  for (const row of rows) {
    if (typeof row.id !== 'string' || !Array.isArray(row.cells) || row.cells.length !== COLUMNS) continue;
    const cells = row.cells.map((cell) => String(cell).slice(0, 2000));
    const note = 'Prefill ' + row.id;
    const rowKey = key(cells[1], cells[2]);
    if (ids.has(note) || keys.has(rowKey)) {
      skipped.push(row.id);
      continue;
    }
    sheet.insertRowBefore(HEADER_ROWS + 1);
    // Plain text, so a cell starting with = never runs as a formula.
    sheet.getRange(HEADER_ROWS + 1, 1, 1, COLUMNS).setNumberFormat('@').setValues([cells]);
    sheet.getRange(HEADER_ROWS + 1, 1).setNote(note);
    ids.add(note);
    keys.add(rowKey);
    added.push(row.id);
  }
  return { added, skipped };
}

function key(company, role) {
  return (String(company) + '|' + String(role)).toLowerCase().replace(/[^a-z0-9|]/g, '');
}

function reply(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
