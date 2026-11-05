# Owner reminders and notifications

- Owner means active staff role `admin`; managers cannot change reminder settings.
- One group schedule: choose 7, 15, 30 or 45 days. Disabled until an owner explicitly enables/saves. Cron remains 08:00 Asia/Dubai daily.
- Send once per obligation/period/deadline/recipient/Dubai date using existing delivery ledger. Responsible member and direct/group manager must be active and have task access. Configured group/company owners receive copies.
- Attach a generated PDF obligation summary; never email private uploaded source documents. Microsoft acceptance is not proof of final mailbox delivery.
- Pause during pending completion approval; approved closed tasks stop. Rejections resume. Approved renewals use their future due date. Ordinary progress edits or uploads alone do not stop reminders.
- Document indexing, substantive obligation changes and completion review create durable notifications for owners and the responsible team manager. Both manual and assistant paths use database triggers. Staged/unconfirmed chatbot attachments are not indexed evidence.
- Inbox polls every 30 seconds and on focus/open, latest50 with independent unread count. Mark-read RPC changes only caller-owned notifications; no client delete/write grant. Fresh membership, task scope and current team relationships filter reads. Document links use existing private storage permissions and 60-second signed links.
- Migration: 20261105093426_owner_alerts_notifications.sql. SQL tests use rollback and leave no records. No live email sent during validation.

## Plain English and assistant task choices
- UI labels use Home, Tasks, Teams, Members & roles, Chat and Change history; internal page IDs and saved statuses stay unchanged.
- Structured assistant `choices` contains only refs. Server filters against the caller's current authorised non-archived records, deduplicates and caps at8. Any valid choices suppress draft creation.
- Cards show current company/title/period/due/status from the member's visible rows. Clicking sends a selection with its task ref into the same chat, keeping the staged file. Old choice cards become inactive after the next message.
- Picking a task never saves an update. File/evidence checks, explicit confirmation and manager/owner approval remain in place. Existing completed tasks are not automatically replaced.
