# ARKS Group

React/Vite working preview using the ARKS logo and the 4 November 2026 compliance-register snapshot.

Run: npm install, then npm run dev. Production check: npm run build.
Vercel settings are in vercel.json.

## Current state
Overview, companies, searchable register, calendar, owner workload, evidence references, browser-local edits and JSON export work. Data is a dated import, not live Google Sheets synchronization. Document uploads, authentication, approvals, recurring generation and notifications are not activated. Do not deploy the current seed data publicly; it contains internal compliance information. Move seed records into an authenticated database before production publication.

## Agreed production architecture
Vercel hosts the app. Supabase provides invite-only staff authentication, Postgres shared records and private Storage for company/obligation documents. Apply row-level security to all tables and storage objects. Staff access must derive from company memberships, with group administrators explicitly assigned. Use short-lived signed download URLs. Never put a service-role key in browser code.

## Employee email alerts
Send to the assigned employee's verified account email; never infer an email from a name. Several imported owners are placeholders and need real staff accounts and email addresses before delivery.

Events: assignment/reassignment, configurable pre-deadline reminders (suggested 30/14/7/1 days), overdue daily digest, returned evidence, and manager escalation after configurable overdue age. UAE time: Asia/Dubai. A scheduled server job selects eligible reminders. Use an email provider with a verified sending domain; record provider message IDs and send status. A unique obligation/period/recipient/reminder-key prevents duplicates. Check completion and current assignment immediately before sending. Include a signed-in task link, company, deadline and action; do not attach private documents. Log failures and support bounded retries. No mail credentials in frontend code.

## Setup dependencies
Create Supabase project named ARKS Group, retain database password privately, and supply only project URL plus publishable key. Configure staff invitations, production redirect URL, schema and storage policies. Connect Vercel account and configure server-side environment variables. Select email provider and verify ARKS sender domain. Test with authorized staff accounts before enabling scheduled delivery.
