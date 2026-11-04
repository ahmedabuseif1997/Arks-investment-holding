begin;
create schema if not exists arks_private;
revoke all on schema arks_private from public,anon;
grant usage on schema arks_private to authenticated;
alter table public.arks_staff drop constraint if exists arks_staff_role_check;
alter table public.arks_staff add constraint arks_staff_role_check check(role in ('admin','finance','manager','employee','viewer','custom'));
alter table public.arks_staff add column if not exists scope text;
alter table public.arks_staff add column if not exists company_access text[] not null default '{}';
alter table public.arks_staff add column if not exists permissions text[];
update public.arks_staff set scope=case when role in ('admin','finance') then 'all' else 'assigned' end where scope is null;
update public.arks_staff set permissions=case when role in ('admin','finance') then array['view_dashboard','view_companies','view_obligations','edit_obligations','approve_obligations','assign_tasks','view_documents','upload_documents','view_team','export'] else array['view_dashboard','view_companies','view_obligations','edit_obligations','view_documents','upload_documents'] end where permissions is null;
alter table public.arks_staff alter column scope set default 'assigned',alter column scope set not null,alter column permissions set default '{}',alter column permissions set not null;
alter table public.arks_staff add constraint arks_staff_scope_check check(scope in ('all','selected','assigned'));
create index if not exists arks_obligations_owner_entity_idx on public.arks_obligations(owner_email,entity);
create function arks_private.member() returns public.arks_staff language sql stable security definer set search_path='' as $$
select s from public.arks_staff s where auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) and s.email=lower(auth.jwt()->>'email') and s.active
$$;
create function arks_private.allowed(action text,company text default null,owner_email text default null,task_specific boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.arks_staff;
begin
if auth.uid() is null then return false; end if;
m:=arks_private.member();
if m.email is null then return false; end if;
if m.role='admin' then return true; end if;
if action='manage_members' or not(action=any(m.permissions)) then return false; end if;
if company is null then return true; end if;
if m.scope='all' then return true; end if;
if m.scope='selected' then return company=any(m.company_access); end if;
if task_specific then return coalesce(owner_email=m.email,false); end if;
return exists(select 1 from public.arks_obligations o where o.entity=company and o.owner_email=m.email);
end $$;
revoke all on all functions in schema arks_private from public,anon;
grant execute on all functions in schema arks_private to authenticated;
create or replace function public.arks_role() returns text language sql stable security invoker set search_path='' as $$ select (arks_private.member()).role $$;
create or replace function public.arks_can_read_company(c text) returns boolean language sql stable security invoker set search_path='' as $$ select arks_private.allowed('view_companies',c) $$;
-- Replace permissive legacy policies; clients cannot bypass permission checks through direct writes.
drop policy staff_read on public.arks_staff;
drop policy staff_manage on public.arks_staff;
create policy staff_read on public.arks_staff for select to authenticated using ((email=lower(auth.jwt()->>'email') and active) or arks_private.allowed('view_team') or arks_private.allowed('manage_members'));
drop policy company_read on public.arks_companies;
drop policy company_manage on public.arks_companies;
create policy company_read on public.arks_companies for select to authenticated using(arks_private.allowed('view_companies',name) or arks_private.allowed('view_obligations',name) or arks_private.allowed('view_documents',name));
drop policy obligation_read on public.arks_obligations;
drop policy obligation_manage on public.arks_obligations;
create policy obligation_read on public.arks_obligations for select to authenticated using(arks_private.allowed('view_obligations',entity,owner_email,true));
drop policy doc_read on public.arks_documents;
drop policy doc_insert on public.arks_documents;
create policy doc_read on public.arks_documents for select to authenticated using(arks_private.allowed('view_documents',company));
create policy doc_insert on public.arks_documents for insert to authenticated with check(arks_private.allowed('upload_documents',company) and arks_private.allowed('view_documents',company) and uploaded_by=(select auth.uid()) and (storage.foldername(storage_path))[1]=auth.uid()::text and (storage.foldername(storage_path))[2]=company and (obligation_ref is null or exists(select 1 from public.arks_obligations o where o.ref=obligation_ref and o.entity=company)));
drop policy arks_upload on storage.objects;
drop policy arks_download on storage.objects;
create policy arks_upload on storage.objects for insert to authenticated with check(bucket_id='arks-documents' and (storage.foldername(name))[1]=auth.uid()::text and arks_private.allowed('upload_documents',(storage.foldername(name))[2]) and arks_private.allowed('view_documents',(storage.foldername(name))[2]));
create policy arks_download on storage.objects for select to authenticated using(bucket_id='arks-documents' and arks_private.allowed('view_documents',(storage.foldername(name))[2]));
revoke insert,update,delete on public.arks_staff,public.arks_companies,public.arks_obligations from authenticated;
create table public.arks_member_audit(id bigint generated always as identity primary key,actor text not null,member_email text not null,settings jsonb not null,created_at timestamptz not null default now());
alter table public.arks_member_audit enable row level security;
grant select on public.arks_member_audit to authenticated;
create policy audit_read on public.arks_member_audit for select to authenticated using(arks_private.allowed('manage_members'));
create function public.arks_save_member(member_email text,member_name text,member_role text,member_scope text,member_companies text[],member_permissions text[],member_active boolean) returns void language plpgsql security invoker set search_path='' as $$ begin perform arks_private.save_member(member_email,member_name,member_role,member_scope,member_companies,member_permissions,member_active); end $$;
create function arks_private.save_member(member_email text,member_name text,member_role text,member_scope text,member_companies text[],member_permissions text[],member_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare target text:=lower(trim(member_email));m public.arks_staff;valid text[]:=array['view_dashboard','view_companies','view_obligations','edit_obligations','approve_obligations','assign_tasks','view_documents','upload_documents','view_team','export'];
begin
if auth.uid() is null or not arks_private.allowed('manage_members') then raise exception 'Administrator access required'; end if;
if target is null or target !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(trim(member_name))=0 then raise exception 'Enter a valid name and email'; end if;
if member_role is null or member_role not in ('admin','finance','manager','employee','viewer','custom') or member_scope is null or member_scope not in ('assigned','selected','all') or member_active is null or member_permissions is null or member_companies is null then raise exception 'Invalid access settings'; end if;
if not(member_permissions <@ valid) then raise exception 'Unknown permission'; end if;
if exists(select 1 from unnest(member_companies) c where not exists(select 1 from public.arks_companies e where e.name=c)) then raise exception 'Unknown company'; end if;
if (member_permissions && array['edit_obligations','approve_obligations','assign_tasks','export']) and not('view_obligations'=any(member_permissions)) then raise exception 'Task actions require View obligations'; end if;
if 'approve_obligations'=any(member_permissions) and not('edit_obligations'=any(member_permissions)) then raise exception 'Approval requires Update tasks'; end if;
if 'upload_documents'=any(member_permissions) and not('view_documents'=any(member_permissions)) then raise exception 'Uploads require View documents'; end if;
perform pg_advisory_xact_lock(48273601);
select * into m from public.arks_staff where email=target for update;
if target=lower(auth.jwt()->>'email') and (member_role<>'admin' or not member_active) then raise exception 'You cannot remove your own administrator access'; end if;
if m.role='admin' and m.active and (member_role<>'admin' or not member_active) and (select count(*) from public.arks_staff where role='admin' and active)<=1 then raise exception 'Keep at least one active administrator'; end if;
insert into public.arks_staff(email,name,role,scope,company_access,permissions,active) values(target,trim(member_name),member_role,case when member_role='admin' then 'all' else member_scope end,member_companies,case when member_role='admin' then valid else member_permissions end,member_active) on conflict(email) do update set name=excluded.name,role=excluded.role,scope=excluded.scope,company_access=excluded.company_access,permissions=excluded.permissions,active=excluded.active;
insert into public.arks_member_audit(actor,member_email,settings) values(lower(auth.jwt()->>'email'),target,jsonb_build_object('role',member_role,'scope',member_scope,'companies',member_companies,'permissions',member_permissions,'active',member_active));
end $$;
create or replace function public.arks_update_task(task_ref text,task_status text,evidence text,comments text) returns void language plpgsql security invoker set search_path='' as $$ begin perform arks_private.update_task(task_ref,task_status,evidence,comments); end $$;
create function arks_private.update_task(task_ref text,task_status text,evidence text,comments text) returns void language plpgsql security definer set search_path='' as $$
declare task public.arks_obligations;
begin
if auth.uid() is null then raise exception 'Sign in required'; end if;
select * into task from public.arks_obligations where ref=task_ref for update;
if not found or not arks_private.allowed('view_obligations',task.entity,task.owner_email,true) or not arks_private.allowed('edit_obligations',task.entity,task.owner_email,true) then raise exception 'Task update not permitted'; end if;
if task_status is null or task_status not in ('Not started','In progress','Submitted to authority','Completed','Not applicable') then raise exception 'Invalid status'; end if;
if task_status in ('Completed','Not applicable') and not arks_private.allowed('approve_obligations',task.entity,task.owner_email,true) then raise exception 'Completion approval not permitted'; end if;
if task_status='Completed' and coalesce(length(trim(evidence)),0)=0 then raise exception 'Evidence required'; end if;
update public.arks_obligations set data=data||jsonb_build_object('status',task_status,'evidence',coalesce(evidence,''),'comments',coalesce(comments,''),'updatedBy',auth.jwt()->>'email','updatedOn',now()),updated_at=now() where ref=task_ref;
end $$;
create function public.arks_assign_task(task_ref text,assignee_email text) returns void language plpgsql security invoker set search_path='' as $$ begin perform arks_private.assign_task(task_ref,assignee_email); end $$;
create function arks_private.assign_task(task_ref text,assignee_email text) returns void language plpgsql security definer set search_path='' as $$
declare task public.arks_obligations;assignee public.arks_staff;
begin
if auth.uid() is null then raise exception 'Sign in required'; end if;
select * into task from public.arks_obligations where ref=task_ref for update;
if not found or not arks_private.allowed('view_obligations',task.entity,task.owner_email,true) or not arks_private.allowed('assign_tasks',task.entity,task.owner_email,true) then raise exception 'Assignment not permitted'; end if;
if assignee_email is not null then select * into assignee from public.arks_staff where email=lower(assignee_email) and active;if not found then raise exception 'Choose an active member';end if;end if;
update public.arks_obligations set owner_email=lower(assignee_email),data=data||jsonb_build_object('owner',coalesce(nullif(assignee.name,''),assignee.email,'Unassigned'),'updatedBy',auth.jwt()->>'email'),updated_at=now() where ref=task_ref;
end $$;
revoke all on function public.arks_save_member(text,text,text,text,text[],text[],boolean),public.arks_assign_task(text,text) from public,anon;
grant execute on function public.arks_save_member(text,text,text,text,text[],text[],boolean),public.arks_assign_task(text,text) to authenticated;
revoke all on all functions in schema arks_private from public,anon;
grant execute on all functions in schema arks_private to authenticated;
commit;
select count(*) as obligations_preserved,(select count(*) from public.arks_staff where role='admin' and active) as active_admins from public.arks_obligations;
