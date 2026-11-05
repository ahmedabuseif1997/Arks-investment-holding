create table public.arks_assistant_uploads(id uuid primary key default gen_random_uuid(),created_by uuid not null,actor text not null,storage_path text not null unique,file_name text not null,mime_type text not null,size_bytes bigint not null,state text not null default 'staged' check(state in ('staged','committed')),document_id uuid references public.arks_documents(id),created_at timestamptz not null default now());
create table public.arks_assistant_proposals(id uuid primary key default gen_random_uuid(),created_by uuid not null,actor text not null,task_ref text not null references public.arks_obligations(ref),snapshot text not null,before_data jsonb not null,changes jsonb not null,assignment boolean not null default false,assignee_email text,completion boolean not null default false,renewal boolean not null default false,upload_id uuid references public.arks_assistant_uploads(id),status text not null default 'pending' check(status in ('pending','applied','cancelled')),result jsonb,created_at timestamptz not null default now(),expires_at timestamptz not null default(now()+interval '24 hours'));
create table public.arks_completion_requests(id uuid primary key default gen_random_uuid(),proposal_id uuid not null unique references public.arks_assistant_proposals(id),task_ref text not null references public.arks_obligations(ref),requested_by text not null,requested_uid uuid not null,document_id uuid references public.arks_documents(id),changes jsonb not null,renewal boolean not null,prior_status text not null,expected_snapshot text not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),reviewed_by text,review_reason text,created_at timestamptz not null default now(),reviewed_at timestamptz);
create unique index arks_one_pending_completion on public.arks_completion_requests(task_ref) where status='pending';
create index arks_assistant_proposals_owner on public.arks_assistant_proposals(created_by,created_at desc);
create index arks_assistant_uploads_owner on public.arks_assistant_uploads(created_by,created_at desc);
create index arks_completion_task on public.arks_completion_requests(task_ref,created_at desc);
create or replace function arks_private.assistant_review_allowed(task_reference text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.arks_staff;t public.arks_obligations;
begin
m:=arks_private.member();if auth.uid() is null or m.email is null then return false;end if;
select * into t from public.arks_obligations where ref=task_reference;if not found or not arks_private.allowed('view_obligations',t.entity,t.owner_email,true) then return false;end if;
if m.role='admin' then return true;end if;
return m.role='manager' and arks_private.allowed('approve_obligations',t.entity,t.owner_email,true) and (exists(select 1 from public.arks_groups g where g.name=t.data->>'owner' and g.manager_email=m.email and not g.archived) or exists(select 1 from public.arks_staff s where s.email=t.owner_email and s.manager_email=m.email));
end $$;
alter table public.arks_assistant_uploads enable row level security;alter table public.arks_assistant_proposals enable row level security;alter table public.arks_completion_requests enable row level security;
create policy assistant_upload_read on public.arks_assistant_uploads for select to authenticated using(created_by=(select auth.uid()) and (arks_private.member()).email is not null);
create policy assistant_proposal_read on public.arks_assistant_proposals for select to authenticated using(created_by=(select auth.uid()) and (arks_private.member()).email is not null and exists(select 1 from public.arks_obligations o where o.ref=task_ref));
create policy assistant_completion_read on public.arks_completion_requests for select to authenticated using(((requested_uid=(select auth.uid())) and (arks_private.member()).email is not null and exists(select 1 from public.arks_obligations o where o.ref=task_ref)) or arks_private.assistant_review_allowed(task_ref));
revoke all on public.arks_assistant_uploads,public.arks_assistant_proposals,public.arks_completion_requests from anon,authenticated;grant select on public.arks_assistant_uploads,public.arks_assistant_proposals,public.arks_completion_requests to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('arks-assistant-staging','arks-assistant-staging',false,20971520,array['application/pdf','image/jpeg','image/png','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy assistant_stage_insert on storage.objects for insert to authenticated with check(bucket_id='arks-assistant-staging' and (storage.foldername(name))[1]=(select auth.uid())::text and arks_private.allowed('upload_documents') and arks_private.allowed('view_documents'));
create policy assistant_stage_read on storage.objects for select to authenticated using(bucket_id='arks-assistant-staging' and (storage.foldername(name))[1]=(select auth.uid())::text and (arks_private.member()).email is not null);
create policy assistant_stage_delete on storage.objects for delete to authenticated using(bucket_id='arks-assistant-staging' and (storage.foldername(name))[1]=(select auth.uid())::text and (arks_private.member()).email is not null);
create or replace function arks_private.assistant_stage(object_path text,display_name text) returns public.arks_assistant_uploads language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;o storage.objects;u public.arks_assistant_uploads;
begin
m:=arks_private.member();if auth.uid() is null or m.email is null or not arks_private.allowed('upload_documents') or not arks_private.allowed('view_documents') then raise exception 'Document uploads are not permitted';end if;
if (storage.foldername(object_path))[1]<>auth.uid()::text or coalesce(length(trim(display_name)),0) not between 1 and 240 then raise exception 'Invalid attachment';end if;
select * into o from storage.objects where bucket_id='arks-assistant-staging' and name=object_path;if not found then raise exception 'Upload the attachment first';end if;
if coalesce((o.metadata->>'size')::bigint,0) not between 1 and 20971520 then raise exception 'Attachment must be between 1 byte and 20 MB';end if;
insert into public.arks_assistant_uploads(created_by,actor,storage_path,file_name,mime_type,size_bytes) values(auth.uid(),m.email,object_path,trim(display_name),o.metadata->>'mimetype',(o.metadata->>'size')::bigint) on conflict(storage_path) do nothing;
select * into u from public.arks_assistant_uploads where storage_path=object_path and created_by=auth.uid();return u;
end $$;
create or replace function arks_private.assistant_validate(task_reference text,patch jsonb,assign_member boolean,target_email text,wants_completion boolean,is_renewal boolean,attachment uuid) returns public.arks_obligations language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;t public.arks_obligations;s public.arks_staff;v record;u public.arks_assistant_uploads;
begin
m:=arks_private.member();if auth.uid() is null or m.email is null then raise exception 'Active membership required';end if;
select * into t from public.arks_obligations where ref=task_reference;
if not found or coalesce(t.data->>'archived','false')='true' or not arks_private.allowed('view_obligations',t.entity,t.owner_email,true) or not arks_private.allowed('edit_obligations',t.entity,t.owner_email,true) then raise exception 'You cannot update this obligation';end if;
if m.role='manager' and not(exists(select 1 from public.arks_groups g where g.name=t.data->>'owner' and g.manager_email=m.email and not g.archived) or exists(select 1 from public.arks_staff x where x.email=t.owner_email and x.manager_email=m.email)) then raise exception 'This obligation is outside your team';end if;
if wants_completion and assign_member then raise exception 'Assign the task separately before requesting completion';end if;
if jsonb_typeof(patch) is distinct from 'object' or assign_member is null or wants_completion is null or is_renewal is null then raise exception 'Invalid proposal';end if;
for v in select * from jsonb_each(patch) loop
 if v.key not in ('title','authority','due','period','frequency','comments','evidence','status','information_status') or jsonb_typeof(v.value)<>'string' or length(v.value#>>'{}')> (case when v.key='comments' then 8000 else 1500 end) then raise exception 'Unsupported or oversized change';end if;
end loop;
if patch?'status' and patch->>'status' not in ('Not started','In progress','Submitted to authority') then raise exception 'Completion requires a separate approval request';end if;
if patch?'title' and length(trim(patch->>'title'))=0 or patch?'authority' and length(trim(patch->>'authority'))=0 then raise exception 'Title and authority cannot be empty';end if;
if patch?'due' and patch->>'due'<>'' and ((patch->>'due') !~ '^\d{2}-[A-Z][a-z]{2}-\d{4}$' or to_char(to_date(patch->>'due','DD-Mon-YYYY'),'DD-Mon-YYYY')<>patch->>'due') then raise exception 'Invalid due date';end if;
if is_renewal and (not wants_completion or coalesce(patch->>'due','')='' or to_date(patch->>'due','DD-Mon-YYYY')<=(now() at time zone 'Asia/Dubai')::date) then raise exception 'A renewal needs its confirmed next future due date';end if;
if patch?'information_status' and patch->>'information_status' not in ('','Needs information') then raise exception 'Invalid information status';end if;
if assign_member then
 if m.role not in ('admin','manager') or not arks_private.allowed('assign_tasks',t.entity,t.owner_email,true) then raise exception 'Only owners and permitted managers can assign tasks';end if;
 if target_email is not null then
 select * into s from public.arks_staff where email=lower(target_email) and active;if not found or (m.role='manager' and s.manager_email is distinct from m.email and s.email<>m.email) then raise exception 'Choose an active member in your team';end if;
 if not('view_obligations'=any(s.permissions) or s.role='admin') or not(s.role='admin' or s.scope in ('all','assigned') or (s.scope='selected' and t.entity=any(s.company_access))) then raise exception 'The selected member cannot access this company';end if;
 end if;
end if;
if attachment is not null then
 select * into u from public.arks_assistant_uploads where id=attachment and created_by=auth.uid() and state='staged';if not found then raise exception 'Attachment is not available';end if;
 if not arks_private.allowed('upload_documents',t.entity) or not arks_private.allowed('view_documents',t.entity) then raise exception 'Document access is not permitted for this company';end if;
end if;
if wants_completion and attachment is null and coalesce(length(trim(coalesce(patch->>'evidence',t.data->>'evidence'))),0)=0 then raise exception 'Upload supporting evidence before requesting completion';end if;
return t;
end $$;
create or replace function arks_private.assistant_propose(task_reference text,patch jsonb,assign_member boolean default false,target_email text default null,wants_completion boolean default false,is_renewal boolean default false,attachment uuid default null) returns public.arks_assistant_proposals language plpgsql security definer set search_path='' as $$
declare t public.arks_obligations;p public.arks_assistant_proposals;
begin
t:=arks_private.assistant_validate(task_reference,patch,assign_member,target_email,wants_completion,is_renewal,attachment);
if exists(select 1 from public.arks_completion_requests where task_ref=task_reference and status='pending') then raise exception 'This obligation already awaits manager approval';end if;
if patch='{}'::jsonb and not assign_member and not wants_completion and attachment is null then raise exception 'No change proposed';end if;
insert into public.arks_assistant_proposals(created_by,actor,task_ref,snapshot,before_data,changes,assignment,assignee_email,completion,renewal,upload_id) values(auth.uid(),(arks_private.member()).email,t.ref,md5(t.data::text||coalesce(t.owner_email,'')),t.data||jsonb_build_object('owner_email',t.owner_email),patch,assign_member,lower(target_email),wants_completion,is_renewal,attachment) returning * into p;return p;
end $$;
create or replace function arks_private.assistant_prepare(proposal_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.arks_assistant_proposals;t public.arks_obligations;u public.arks_assistant_uploads;dest text;
begin
if auth.uid() is null or (arks_private.member()).email is null then raise exception 'Sign in required';end if;
select * into p from public.arks_assistant_proposals where id=proposal_id and created_by=auth.uid();if not found or p.status='cancelled' then raise exception 'Proposal not available';end if;
if not exists(select 1 from public.arks_obligations o where o.ref=p.task_ref and arks_private.allowed('view_obligations',o.entity,o.owner_email,true)) then raise exception 'This obligation is no longer accessible';end if;
if p.status='applied' then return jsonb_build_object('applied',true,'result',p.result);end if;
if p.expires_at<now() then raise exception 'Proposal expired. Ask the assistant to review it again';end if;
t:=arks_private.assistant_validate(p.task_ref,p.changes,p.assignment,p.assignee_email,p.completion,p.renewal,p.upload_id);
if p.snapshot<>md5(t.data::text||coalesce(t.owner_email,'')) then raise exception 'This obligation changed. Ask for a fresh proposal';end if;
if p.upload_id is not null then
 select * into u from public.arks_assistant_uploads where id=p.upload_id and created_by=auth.uid();dest:=auth.uid()::text||'/'||t.entity||'/'||u.id::text||'-'||regexp_replace(u.file_name,'[^a-zA-Z0-9._-]','_','g');
end if;
return jsonb_build_object('applied',false,'upload',case when u.id is not null then to_jsonb(u) else null end,'destination',dest,'company',t.entity);
end $$;
create or replace function arks_private.assistant_confirm(proposal_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.arks_assistant_proposals;t public.arks_obligations;u public.arks_assistant_uploads;d public.arks_documents;plan jsonb;patch jsonb;newdata jsonb;rid uuid;outcome jsonb;
begin
select * into p from public.arks_assistant_proposals where id=proposal_id and created_by=auth.uid() for update;if not found then raise exception 'Proposal not available';end if;
plan:=arks_private.assistant_prepare(proposal_id);if (plan->>'applied')::boolean then return plan->'result';end if;
select * into t from public.arks_obligations where ref=p.task_ref for update;
if p.snapshot<>md5(t.data::text||coalesce(t.owner_email,'')) then raise exception 'This obligation changed. Ask for a fresh proposal';end if;
if exists(select 1 from public.arks_completion_requests where task_ref=t.ref and status='pending') then raise exception 'This obligation already awaits manager approval';end if;
patch:=p.changes;
if p.upload_id is not null then
 select * into u from public.arks_assistant_uploads where id=p.upload_id for update;
 if not exists(select 1 from storage.objects where bucket_id='arks-documents' and name=plan->>'destination' and (metadata->>'size')::bigint=u.size_bytes) then raise exception 'The document has not finished saving. Please retry';end if;
 insert into public.arks_documents(company,obligation_ref,name,storage_path,mime_type,size_bytes,uploaded_by) values(t.entity,t.ref,u.file_name,plan->>'destination',u.mime_type,u.size_bytes,auth.uid()) returning * into d;
 update public.arks_assistant_uploads set state='committed',document_id=d.id where id=u.id;
 patch:=patch||jsonb_build_object('evidence',concat_ws(E'\n',nullif(coalesce(patch->>'evidence',t.data->>'evidence'),''),'Document: '||d.name||' ['||d.id::text||']'));
end if;
if p.completion then
 newdata:=t.data||jsonb_build_object('status','Awaiting manager approval','updatedBy',p.actor,'updatedOn',now());
 update public.arks_obligations set data=newdata,updated_at=now() where ref=t.ref;
 insert into public.arks_completion_requests(proposal_id,task_ref,requested_by,requested_uid,document_id,changes,renewal,prior_status,expected_snapshot) values(p.id,t.ref,p.actor,auth.uid(),d.id,patch,p.renewal,coalesce(t.data->>'status','Not started'),md5(newdata::text||coalesce(t.owner_email,''))) returning id into rid;
else
 newdata:=t.data||patch||jsonb_build_object('updatedBy',p.actor,'updatedOn',now());
 update public.arks_obligations set data=newdata,owner_email=case when p.assignment then p.assignee_email else t.owner_email end,updated_at=now() where ref=t.ref;
end if;
if p.completion and p.assignment then raise exception 'Assign the task separately before requesting completion';end if;
outcome:=jsonb_build_object('task_ref',t.ref,'document_id',d.id,'document_name',d.name,'approval_id',rid,'status',case when p.completion then 'Awaiting manager approval' else 'Saved' end);
update public.arks_assistant_proposals set status='applied',result=outcome where id=p.id;
insert into public.arks_data_audit(actor,action,payload) values(p.actor,case when p.completion then 'assistant_completion_requested' else 'assistant_update_confirmed' end,jsonb_build_object('proposal_id',p.id,'ref',t.ref,'before',t.data,'changes',patch,'document_id',d.id,'assignment',p.assignment,'assignee',p.assignee_email));return outcome;
end $$;
create or replace function arks_private.assistant_review(request_id uuid,approve boolean,reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.arks_completion_requests;t public.arks_obligations;m public.arks_staff;nextdata jsonb;result jsonb;
begin
m:=arks_private.member();select * into r from public.arks_completion_requests where id=request_id for update;
if not found or not arks_private.assistant_review_allowed(r.task_ref) then raise exception 'Manager or owner approval required';end if;
if r.status<>'pending' then return jsonb_build_object('status',r.status,'task_ref',r.task_ref);end if;
if approve is null or length(reason)>1500 then raise exception 'Invalid review';end if;
if approve and r.requested_by=m.email and m.role<>'admin' then raise exception 'An owner must approve your own completion request';end if;
select * into t from public.arks_obligations where ref=r.task_ref for update;
if approve then
 if r.expected_snapshot<>md5(t.data::text||coalesce(t.owner_email,'')) or coalesce(t.data->>'archived','false')='true' then raise exception 'The record changed after submission. Reject and request a fresh update';end if;
 if r.renewal and (coalesce(r.changes->>'due','')='' or to_date(r.changes->>'due','DD-Mon-YYYY')<=(now() at time zone 'Asia/Dubai')::date) then raise exception 'The next renewal date must still be in the future';end if;
 nextdata:=t.data||r.changes||jsonb_build_object('status',case when r.renewal then 'Not started' else 'Completed' end,'last_completed',now(),'completed',now(),'updatedBy',m.email,'updatedOn',now());
 update public.arks_obligations set data=nextdata,updated_at=now() where ref=t.ref;
else
 if coalesce(length(trim(reason)),0)=0 then raise exception 'Give a reason so the member knows what to correct';end if;
 if r.expected_snapshot=md5(t.data::text||coalesce(t.owner_email,'')) then update public.arks_obligations set data=t.data||jsonb_build_object('status',r.prior_status,'updatedBy',m.email,'updatedOn',now()),updated_at=now() where ref=t.ref;end if;
end if;
update public.arks_completion_requests set status=case when approve then 'approved' else 'rejected' end,reviewed_by=m.email,review_reason=trim(reason),reviewed_at=now() where id=r.id;
insert into public.arks_data_audit(actor,action,payload) values(m.email,case when approve then 'assistant_completion_approved' else 'assistant_completion_rejected' end,jsonb_build_object('request_id',r.id,'ref',t.ref,'before',t.data,'changes',r.changes,'document_id',r.document_id,'renewal',r.renewal,'reason',reason));
result:=jsonb_build_object('status',case when approve then 'approved' else 'rejected' end,'task_ref',t.ref);return result;
end $$;
create or replace function arks_private.assistant_cancel(proposal_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if auth.uid() is null or (arks_private.member()).email is null then raise exception 'Sign in required';end if;
update public.arks_assistant_proposals set status='cancelled' where id=proposal_id and created_by=auth.uid() and status='pending';
end $$;

revoke all on function arks_private.assistant_review_allowed(text) from public,anon;grant execute on function arks_private.assistant_review_allowed(text) to authenticated;

revoke all on function arks_private.assistant_stage(text,text) from public,anon;grant execute on function arks_private.assistant_stage(text,text) to authenticated;
create or replace function public.arks_assistant_stage(object_path text,display_name text) returns public.arks_assistant_uploads language sql security invoker set search_path='' as $$select arks_private.assistant_stage(object_path,display_name)$$;
revoke all on function public.arks_assistant_stage(text,text) from public,anon;grant execute on function public.arks_assistant_stage(text,text) to authenticated;

revoke all on function arks_private.assistant_validate(text,jsonb,boolean,text,boolean,boolean,uuid) from public,anon;grant execute on function arks_private.assistant_validate(text,jsonb,boolean,text,boolean,boolean,uuid) to authenticated;

revoke all on function arks_private.assistant_propose(text,jsonb,boolean,text,boolean,boolean,uuid) from public,anon;grant execute on function arks_private.assistant_propose(text,jsonb,boolean,text,boolean,boolean,uuid) to authenticated;
create or replace function public.arks_assistant_propose(task_reference text,patch jsonb,assign_member boolean default false,target_email text default null,wants_completion boolean default false,is_renewal boolean default false,attachment uuid default null) returns public.arks_assistant_proposals language sql security invoker set search_path='' as $$select arks_private.assistant_propose(task_reference,patch,assign_member,target_email,wants_completion,is_renewal,attachment)$$;
revoke all on function public.arks_assistant_propose(text,jsonb,boolean,text,boolean,boolean,uuid) from public,anon;grant execute on function public.arks_assistant_propose(text,jsonb,boolean,text,boolean,boolean,uuid) to authenticated;

revoke all on function arks_private.assistant_prepare(uuid) from public,anon;grant execute on function arks_private.assistant_prepare(uuid) to authenticated;
create or replace function public.arks_assistant_prepare(proposal_id uuid) returns jsonb language sql security invoker set search_path='' as $$select arks_private.assistant_prepare(proposal_id)$$;
revoke all on function public.arks_assistant_prepare(uuid) from public,anon;grant execute on function public.arks_assistant_prepare(uuid) to authenticated;

revoke all on function arks_private.assistant_confirm(uuid) from public,anon;grant execute on function arks_private.assistant_confirm(uuid) to authenticated;
create or replace function public.arks_assistant_confirm(proposal_id uuid) returns jsonb language sql security invoker set search_path='' as $$select arks_private.assistant_confirm(proposal_id)$$;
revoke all on function public.arks_assistant_confirm(uuid) from public,anon;grant execute on function public.arks_assistant_confirm(uuid) to authenticated;

revoke all on function arks_private.assistant_review(uuid,boolean,text) from public,anon;grant execute on function arks_private.assistant_review(uuid,boolean,text) to authenticated;
create or replace function public.arks_assistant_review(request_id uuid,approve boolean,reason text default '') returns jsonb language sql security invoker set search_path='' as $$select arks_private.assistant_review(request_id,approve,reason)$$;
revoke all on function public.arks_assistant_review(uuid,boolean,text) from public,anon;grant execute on function public.arks_assistant_review(uuid,boolean,text) to authenticated;

revoke all on function arks_private.assistant_cancel(uuid) from public,anon;grant execute on function arks_private.assistant_cancel(uuid) to authenticated;
create or replace function public.arks_assistant_cancel(proposal_id uuid) returns void language sql security invoker set search_path='' as $$select arks_private.assistant_cancel(proposal_id)$$;
revoke all on function public.arks_assistant_cancel(uuid) from public,anon;grant execute on function public.arks_assistant_cancel(uuid) to authenticated;
