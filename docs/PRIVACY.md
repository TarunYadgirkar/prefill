# Prefill privacy

Prefill keeps your details on your own devices and in your own Apple and Google accounts. It has no server and sends nothing to its developer.

- **What it stores:** the emails, phone numbers, addresses, links and answers you save, the job applications you send through it, and which ones you used where. They live on your iPhone and Mac, in your contact card and Prefill's own contact in iCloud Contacts, and in your private iCloud database (CloudKit), which only your Apple Account can read.
- **Google Sheets:** if you choose Connect Google Sheets on the Mac, Prefill asks Google for access only to files it creates (the `drive.file` scope). It creates one "Job Applications" sheet and adds a row for each application you send: date, company, role, type, status and the page you applied on. It can't read your other files. Its Google sign-in stays in your Mac's Keychain. Disconnect ends it, and the sheet stays in your Drive.
- **The keyboard and AutoFill:** they read only the values the app shares with them, and have no network code.
- **Deleting:** "Delete Prefill data" removes everything Prefill stored on that device and in iCloud. Your contact card is left as it is.

Questions: tyadgirkar@gmail.com
