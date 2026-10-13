# Ember — interactive front-end prototype

This is a mobile-first, single-file web prototype based on `Ember_dating_app_prompt_revised.txt`.

## Run it
- Open `index.html` in a modern browser, or upload the file to a static host.
- On first load, enter a date of birth showing age 18+.
- Navigate with the bottom bar on mobile or left navigation on desktop.

## What works in this prototype
- Adult DOB gate (local check only; not identity verification)
- Sample discovery cards, like/pass, mock mutual-match modal, filters UI
- Matches and chat UI, 15 free outgoing messages per sample conversation
- Basic contact-detail/link/social-handle blocking in the front end
- Mock token spending and mock rewarded ad credits (+3 messages)
- Wallet mock bundles with explicit test confirmation; no charges
- Mock call screen, report/block, profile editing, preferences, guidelines and privacy explainer

## Important limitations
This is **not production-ready** and has no backend, real accounts, persistent database, realtime sync, private media storage, server-side contact filter, authoritative token ledger, genuine rewarded ads, actual calling, or admin moderation service. State is in browser memory and resets on refresh. Do not enter real personal data. All profiles are fictional sample data. Payments, ads, and calls are mock-only.

## Production next steps
1. Connect Lovable Cloud or another backend for auth, Postgres, private storage and realtime.
2. Enforce age gate, match membership, blocks, contact filter and message allowances server-side.
3. Implement token balances and spending via atomic server-side SQL functions; never trust client balances.
4. Add private media uploads, server-side file-size/duration validation, moderation and retention controls.
5. Add real provider integrations only after legal/privacy review and clear user disclosures.
6. Test account deletion, report triage, abuse handling, and the 15-message limit thoroughly.
