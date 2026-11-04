# ARKS Group

Live app: https://arks-group.vercel.app

## Implemented
React/Vite app on Vercel using the supplied ARKS logo. Supabase project izahgrueboaiagbwsalk is in Mumbai (ap-south-1). Imported 126 obligations and 17 company/group records from the 4 November 2026 sheet snapshot. Source sheet is unchanged; synchronization is not automatic.

Staff password sign-in, password recovery, private document uploads (PDF/JPG/PNG/DOCX/XLSX, 20 MB), short-lived download links, shared task updates, owner email assignment, staff allowlisting, company/register/calendar/workload views, and register export are implemented.

Administrator: ahmed@arks.ae. Authentication invitation sent. Set password through the invitation to complete account activation. Staff allowlisting and Authentication invitations are separate steps. Employees see their own obligations and documents for companies where they have assignments; Finance and Admin see all records. Finance/Admin approve closure. Uploaded files are not automatically treated as task evidence: reviewers enter the relevant evidence reference.

## Verification
Production build passed. Live sign-in screen visually verified. Anonymous queries returned no rows for staff, companies, obligations or documents; private storage listed no files. Authenticated editing, uploads and employee isolation still require signed-in end-to-end checks. Do not claim these checks have passed.

## Email delivery pending
api/reminders.js and the daily 08:00 Asia/Dubai Vercel schedule are prepared. Sender: ARKS Group <ahmed@arks.ae>. Activate only after configuring a verified arks.ae sending domain and server-only RESEND_API_KEY, SUPABASE_SERVICE_ROLE_KEY, CRON_SECRET and APP_URL=https://arks-group.vercel.app in Vercel. Never place privileged keys in frontend source. The endpoint rejects unauthenticated requests and returns a configuration error while credentials are absent.

Current reminder code covers due in 30/14/7/1 days, due today and daily overdue alerts to active assigned staff, with a send log and idempotency keys. Assignment alerts, manager escalation and returned-evidence emails remain follow-up work. Pending send recovery and delivery tests must be completed before enabling real mail.

## Remaining product work
Automatic recurring-task generation, detailed approval/audit history, editable deadlines, employee/vehicle subregisters, and live sheet sync are not implemented. Original Tokyo project was not used for app data and has not been deleted.

## Development
npm install
npm run dev
npm run build

Public repository contains application code, logo, publishable Supabase key and schema only. Imported source JSON and seed SQL are ignored and were not pushed. Database policies are in supabase/schema.sql. The connected repository checkout lives under work/arks-repository; keep it synchronized when editing this deliverable copy.
