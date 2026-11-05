# ARKS Group

Live app: https://arks-group.vercel.app

## Implemented
React/Vite app on Vercel using the supplied ARKS logo. Supabase project izahgrueboaiagbwsalk is in Mumbai (ap-south-1). Imported 126 obligations and 17 company/group records from the 4 November 2026 sheet snapshot. Source sheet is unchanged; synchronization is not automatic.

Staff password sign-in, password recovery, private document uploads (PDF/JPG/PNG/DOCX/XLSX, 20 MB), short-lived download links, shared task updates, owner email assignment, staff allowlisting, company/register/calendar/workload views, and register export are implemented.

Administrator: ahmed@arks.ae. Authentication invitation sent. Set password through the invitation to complete account activation. Staff allowlisting and Authentication invitations are separate steps. Employees see their own obligations and documents for companies where they have assignments; Finance and Admin see all records. Finance/Admin approve closure. Uploaded files are not automatically treated as task evidence: reviewers enter the relevant evidence reference.

## Verification
Production build passed. Live sign-in screen visually verified. Anonymous queries returned no rows for staff, companies, obligations or documents; private storage listed no files. Authenticated editing, uploads and employee isolation still require signed-in end-to-end checks. Do not claim these checks have passed.

## Email delivery
api/reminders.js runs daily at 08:00 Asia/Dubai using Microsoft 365 from ahmed@arks.ae. It covers due in 30/14/7/1 days, due today and daily overdue alerts, with recipient/day deduplication and conservative recovery of uncertain sends. Recipients include the permitted responsible member, company managers and configured owners. Immediate assignment and returned-evidence emails remain follow-up work. See activation details below.

## Remaining product work
Automatic recurring-task generation, employee/vehicle subregisters and live sheet sync are not implemented. Editable deadlines and management/conversation audit history are implemented below. Original Tokyo project was not used for app data and has not been deleted.

## Development
npm install
npm run dev
npm run build

Public repository contains application code, logo, publishable Supabase key and schema only. Imported source JSON and seed SQL are ignored and were not pushed. Database policies are in supabase/schema.sql. The connected repository checkout lives under work/arks-repository; keep it synchronized when editing this deliverable copy.

## Members & access — 5 November 2026
Owners manage all members from Members & access; managers manage their assigned reports within their own access limits. Presets: Owner, Finance, Manager, Employee, Viewer and Custom. Non-admin capabilities are explicit and editable; scope is all companies, selected companies or assigned tasks. Permissions cover dashboard, company/task/document viewing, task updates/approval/assignment, document uploads, workload and the export button. Read access inherently permits copying readable information; the export setting controls the app export feature.

Membership changes go through a validated RPC, are audited, preserve an active administrator and block self-demotion/suspension. Direct authenticated writes to staff and obligation tables are revoked. Database and Storage policies enforce scope and read/write capabilities. Staff access changes take effect on subsequent database requests; cached/downloaded data cannot be recalled, and issued document links expire in 60 seconds.

Adding a member saves access then requests a Supabase email sign-in link through an isolated non-persistent Auth client. Delivery failures are reported separately from access saves; admins can resend links. No email is sent merely by opening or editing a member. Supabase SMTP restrictions may require sender configuration for new recipient addresses. This does not activate the separate compliance-reminder service.

Migration: supabase/migrations/20261104201523_member_access.sql (applied through the authenticated SQL console; baseline schema remains supabase/schema.sql). Transactional security checks in supabase/member-access-checks.sql passed for assigned/company scopes, employee updates, viewer write/upload denial, privilege escalation denial, scoped assignment, suspension, admin member changes and self-lockout prevention. Test records were rolled back. Frontend preset checks passed. Logo display size increased on login and sidebar.

## Command centre redesign — 5 November 2026
App branding is ARKS Holding LTD. Workspace location label is Dubai, UAE; database remains in Mumbai. Removed the setup banner. Persisted dark/light themes cover all routes and dialogs; CSS login motion honours reduced-motion preferences. Sidebar shows the signed-in member name and available Auth profile photo, otherwise the company logo.

Dashboard now has a clickable company/authority heatmap, grouped and detailed authority views, company filter, priority queue, date coverage and status composition. No recorded obligation is distinguished from compliance, and missing dates/evidence remain explicit. All data comes from existing permission-filtered reads; no new permissions or schema were introduced.

The assistant uses BytePlus ModelArk (dola-seed-2-1-turbo-260628). ARK_API_KEY is a sensitive Vercel server variable, never frontend code. Requests verify Supabase identity and fresh active membership and read register rows with the caller's RLS token. The assistant drafts changes but cannot execute them: a separate confirmation applies only the server-stored, validated proposal. A user-selected attachment is analysed by BytePlus; PDFs/images are sent as inline private content, while DOCX/XLSX yield bounded plain text. No storage access tokens, signed links or credentials are sent to the model. Ordinary questions send minimal authorised task summaries. Chat text remains in browser memory; proposals, approvals, files and action history persist separately.

Checks: six targeted dashboard/auth-context tests passed; BytePlus generic connectivity check succeeded; key absent from tracked source/browser bundle; production build passed. Dark and light login pages visually reviewed. Live signed-in heatmap and assistant are checked after deployment.

Live verification: the signed-in dashboard loaded under the new name with the member's identity and Dubai, UAE label. Dark/light toggle worked. The Globetrotter/free-zone heatmap cell opened exactly C011 and C068. The live BytePlus assistant identified overdue C011/C013, and clicking C011 opened its task drawer. No task was modified during these checks.

## Phone layout and PWA — 5 November 2026
Phones use a sticky 62px top bar and a hamburger drawer with all accessible routes, installation, sign-out and member identity. The drawer closes on navigation/Escape and traps keyboard focus while open. Phone register/member tables become labelled stacked entries; heatmaps use company status rows with an exact-authority selector. Desktop matrices remain available. The assistant becomes a small icon while closed and a viewport-bound panel while open, with independent conversation scrolling and background scroll locking. Layout respects safe-area insets and dynamic viewport height. Existing font sizes were retained.

Install metadata includes a standalone manifest, 192/512px icons, a maskable icon, Apple's 180px touch icon and favicon, all derived from the supplied ARKS logo on an opaque light background. Install app uses the browser prompt when available and provides Safari/Chrome instructions otherwise. Home-screen installation must be confirmed by the phone owner. Existing shortcuts may need to be removed/re-added for the new icon. The service worker caches only a public offline page and branding assets; compliance records, documents, chats and API responses are never put in its cache. Offline use shows a reconnect screen.

Checks: responsive preview at 390x844 and 320x640; hamburger and route selection, stacked register, viewport-bound assistant, 390px page width without horizontal overflow, background scroll lock and install guidance verified. Icon dimensions, manifest paths, service worker syntax/cache scope and the six existing dashboard/chat checks passed. The responsive preview used synthetic records and sent no emails or chat requests.

## Chat follow-up fix and Microsoft 365 alerts — 5 November 2026
Fixed the false 4,000-character error: the current user message alone is validated against that limit; prior assistant replies are bounded as context instead of rejected. Overall history remains limited. Reference chips show six initially and can expand. The assistant is instructed to summarise broad lists rather than produce long tables.

Email delivery adapter now targets Microsoft Graph instead of Resend. Recipients are the active responsible member who can read the obligation, active Manager-role members with permission/scope for that company, and explicitly configured company/group owners. Addresses are normalised and deduplicated. Unassigned obligations still alert management. ALERT_OWNER_EMAILS and MAIL_FROM are configured as ahmed@arks.ae, covering the group; APP_URL is configured. Per-company owner overrides are supported by ALERT_COMPANY_OWNER_EMAILS JSON. No bulk reminder run was triggered during setup.

Production connection configured on 5 November 2026. Exchange Application RBAC permits Application Mail.Send only from ahmed@arks.ae; positive scope and exclusion of another mailbox verified. All server credentials are stored as sensitive Vercel variables, with a 545-day Microsoft client secret. No tenant-wide Entra mail grant was added. The admin Members & access page reports readiness and offers a sender-only setup test. One user-approved test was accepted by Microsoft Graph; message tracing may lag and delivery is not yet confirmed.

Daily reminders remain scheduled at 08:00 Asia/Dubai for 30/14/7/1 days before, due today and overdue. Claim/log uniqueness prevents repeat sends for the same obligation/recipient/day. Microsoft 202 responses are logged as accepted, not proven delivered; uncertain network outcomes are held as unknown to avoid automatic duplicate delivery. Microsoft message tracing is needed to verify inbox delivery. Missing dates cannot generate deadline-based emails until a date is confirmed. One authorised setup test to ahmed@arks.ae was accepted; delivery verification remains pending.

Checks: long-reply follow-up, current-message length, bounded/role-validated history and permission-scoped API integration passed. Recipient scope/deduplication, unassigned-task routing, calendar-date calculations independent of server timezone, and accepted/uncertain Microsoft responses passed using mocked mail calls.

## Editable register, teams and conversations — 5 November 2026
Owners (the existing admin role) control companies, responsibility groups, obligations and member access. In Members & access, add a Manager with company access, then assign employees using Reporting manager. In Team & workload, assign the appropriate manager to each responsibility group. Managers can create and edit their own team members, with permissions and company access bounded by their own; only owners appoint managers or owners. Manager group and obligation mutations are enforced in database functions, including the existing task-update and assignment routes.

Companies and obligations can be added, edited and archived/restored. Missing dates and responsible members are flagged Needs information; additional missing details can be flagged manually. Group removal requires a replacement group when obligations remain; moved tasks clear individual assignments for review. Suspending a member with active work requires an active replacement member. Company archival requires moving or archiving active obligations first. Archived obligations are excluded from daily reminder emails and assistant summaries. Company renames preserve associated task, document and member-company references; storage downloads follow the document's authorised company metadata.

Conversations contains an Everyone room and private manager/team rooms. Each obligation also has threaded comments. Active participants can post messages; they cannot edit or directly delete messages. Authors or moderators request removal with a reason; a manager with room authority or owner must approve. Removal requests, approvals and rejections remain in immutable participant-visible history. Original message bodies are retained separately in a private, non-client-accessible audit table. Chat refreshes every eight seconds while the page is visible; the latest 200 messages and 100 room events are shown.

Activity history shows recent register/group changes, member-access changes and accessible conversation events. Owners see all management entries; managers see their own management entries. Audit tables have no client write/delete policies. Access changes continue to use the existing member audit.

Verification: transactional database checks for company create/rename/archive, invalid dates, manager scope and role escalation, member and group reassignment, private-room isolation, removal approval and immutable history all passed with rollback (no sample accounts/messages retained). Mobile owner/manager flows, permitted roles, group controls, new-obligation fields and private-room selector were checked at 388px without horizontal overflow. Production build passed.

## Approved login and phone navigation — 5 November 2026
The approved login keeps the existing composition, adds a once-only entrance sequence and replaces moving dots with label-free government, document, calendar and email symbols. Icons stay in open margins, pause while the page is hidden and respect reduced-motion preferences. The phone introduction is compact so the login form remains on the first screen. No example notifications or review controls are included in production.

Phone navigation uses a fixed bottom bar for Overview, Register, Calendar, Chat and More, filtered by the signed-in member's existing permissions. More opens an accessible bottom sheet containing permitted workspace sections, profile, installation and sign-out. The hamburger is removed; desktop navigation remains in the sidebar. The promotional dashboard banner is hidden on phones. Safe-area spacing keeps content and the assistant clear of the bottom bar.

Checks: production build, desktop login overflow, 393px/320px first-screen login fit, icon count/scaling, permission-filtered bottom tabs and More options, document-route selection, sheet close/body-scroll restoration passed. Navigation checks used synthetic local data; no real messages or invitations were sent.

## Confirmed assistant actions — implementation ready, awaiting deployment approval
Each member can ask about their permitted records and propose edits to existing obligations. Owners/managers may propose assignments within their current access; managers are limited to their own team. The assistant asks for clarification when an obligation, member or document date is unclear. Every proposal must be confirmed using its card; a conversational yes never auto-executes changes. Unknown fields, arbitrary companies and unauthorised task/member references are rejected. Proposals expire after 24 hours and are checked against a fresh task snapshot and current permissions on confirmation. Confirmation is idempotent.

PDF, PNG/JPG, DOCX and XLSX attachments up to 20 MB are staged in a private, user-isolated bucket. Original bytes are copied to the existing private document bucket only on confirmation and indexed atomically with the update or completion request. Saved documents link to the company and task and can be opened later in Documents, the task drawer and assistant action cards. Rejected completion evidence remains available. Office expansion is bounded before parsing and oversized extracted text asks for a smaller export. No HTML/macros are rendered. Failed file saves do not commit task changes; failed commits clean up unindexed copies without permitting deletion of indexed documents.

Completion changes are pending until an authorised manager or owner explicitly approves. Managers cannot approve their own requests; owners can. Rejections require a reason. Other edit/assignment routes cannot bypass a pending request. Approvals recheck snapshots; stale records must be reviewed again. For renewals with a confirmed future date, approval records completion of the old cycle and leaves the next cycle Not started with the new due date so reminders continue. Ordinary completion becomes Completed. Pending approvals appear as information/approval needed rather than on track. All confirmed and reviewed actions retain actor, fields, references and document links in Activity history.

Phone fix included: login theme control and top spacing now honour the standalone iPhone status-bar safe area; the introduction has no opaque background block and uses top alignment to avoid keyboard-induced centring.

Verification: transactional SQL tests passed for no-write drafts, confirmation idempotence, field/role/team isolation, cancellation, stale records, private document linking and retention, pending-review guards, renewal next-cycle handling, approval and rejection. All synthetic database rows rolled back. A live BytePlus probe using a synthetic PDF correctly distinguished issue and expiry dates and returned a strict structured proposal. Node tests cover server-fetched scope, draft-only model actions, archive/type validation, DOCX/XLSX extraction, unsigned requests, retries and file-save failure. Phone UI checks covered upload, confirmation, owner approval, employee restrictions and the 59px iPhone safe area. No real register records or documents were changed by these tests; no notification emails were sent.
