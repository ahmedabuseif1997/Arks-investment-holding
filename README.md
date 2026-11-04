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

## Members & access — 5 November 2026
Administrators now manage members directly from a dedicated sidebar page. Presets: Administrator, Finance, Manager, Employee, Viewer and Custom. Non-admin capabilities are explicit and editable; scope is all companies, selected companies or assigned tasks. Permissions cover dashboard, company/task/document viewing, task updates/approval/assignment, document uploads, workload and the export button. Read access inherently permits copying readable information; the export setting controls the app export feature.

Membership changes go through a validated RPC, are audited, preserve an active administrator and block self-demotion/suspension. Direct authenticated writes to staff and obligation tables are revoked. Database and Storage policies enforce scope and read/write capabilities. Staff access changes take effect on subsequent database requests; cached/downloaded data cannot be recalled, and issued document links expire in 60 seconds.

Adding a member saves access then requests a Supabase email sign-in link through an isolated non-persistent Auth client. Delivery failures are reported separately from access saves; admins can resend links. No email is sent merely by opening or editing a member. Supabase SMTP restrictions may require sender configuration for new recipient addresses. This does not activate the separate compliance-reminder service.

Migration: supabase/migrations/20261104201523_member_access.sql (applied through the authenticated SQL console; baseline schema remains supabase/schema.sql). Transactional security checks in supabase/member-access-checks.sql passed for assigned/company scopes, employee updates, viewer write/upload denial, privilege escalation denial, scoped assignment, suspension, admin member changes and self-lockout prevention. Test records were rolled back. Frontend preset checks passed. Logo display size increased on login and sidebar.

## Command centre redesign — 5 November 2026
App branding is ARKS Holding LTD. Workspace location label is Dubai, UAE; database remains in Mumbai. Removed the setup banner. Persisted dark/light themes cover all routes and dialogs; CSS login motion honours reduced-motion preferences. Sidebar shows the signed-in member name and available Auth profile photo, otherwise the company logo.

Dashboard now has a clickable company/authority heatmap, grouped and detailed authority views, company filter, priority queue, date coverage and status composition. No recorded obligation is distinguished from compliance, and missing dates/evidence remain explicit. All data comes from existing permission-filtered reads; no new permissions or schema were introduced.

The read-only assistant uses BytePlus ModelArk (dola-seed-2-1-turbo-260628). ARK_API_KEY is stored as a sensitive Vercel production variable, never in source. /api/chat verifies Supabase identity and active membership, reads register rows under the caller's RLS token, and sends only minimal summaries to BytePlus (no private document contents, evidence links, TRNs, source paths or comments). Chat messages stay in browser memory. Source reference buttons only resolve authorised rows. Short request limits, per-instance throttling and an upstream timeout are applied. Compliance reminder email remains separately pending sender setup.

Checks: six targeted dashboard/auth-context tests passed; BytePlus generic connectivity check succeeded; key absent from tracked source/browser bundle; production build passed. Dark and light login pages visually reviewed. Live signed-in heatmap and assistant are checked after deployment.

Live verification: the signed-in dashboard loaded under the new name with the member's identity and Dubai, UAE label. Dark/light toggle worked. The Globetrotter/free-zone heatmap cell opened exactly C011 and C068. The live BytePlus assistant identified overdue C011/C013, and clicking C011 opened its task drawer. No task was modified during these checks.

## Phone layout and PWA — 5 November 2026
Phones use a sticky 62px top bar and a hamburger drawer with all accessible routes, installation, sign-out and member identity. The drawer closes on navigation/Escape and traps keyboard focus while open. Phone register/member tables become labelled stacked entries; heatmaps use company status rows with an exact-authority selector. Desktop matrices remain available. The assistant becomes a small icon while closed and a viewport-bound panel while open, with independent conversation scrolling and background scroll locking. Layout respects safe-area insets and dynamic viewport height. Existing font sizes were retained.

Install metadata includes a standalone manifest, 192/512px icons, a maskable icon, Apple's 180px touch icon and favicon, all derived from the supplied ARKS logo on an opaque light background. Install app uses the browser prompt when available and provides Safari/Chrome instructions otherwise. Home-screen installation must be confirmed by the phone owner. Existing shortcuts may need to be removed/re-added for the new icon. The service worker caches only a public offline page and branding assets; compliance records, documents, chats and API responses are never put in its cache. Offline use shows a reconnect screen.

Checks: responsive preview at 390x844 and 320x640; hamburger and route selection, stacked register, viewport-bound assistant, 390px page width without horizontal overflow, background scroll lock and install guidance verified. Icon dimensions, manifest paths, service worker syntax/cache scope and the six existing dashboard/chat checks passed. The responsive preview used synthetic records and sent no emails or chat requests.
