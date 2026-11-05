alter table public.arks_staff add column if not exists manager_email text references public.arks_staff(email);
create table public.arks_groups(id uuid primary key default gen_random_uuid(),name text not null unique,notes text not null default '',manager_email text references public.arks_staff(email),archived boolean not null default false);
alter table public.arks_groups enable row level security;
insert into public.arks_groups(name) select distinct coalesce(nullif(trim(data->>'owner'),''),'Unassigned') from public.arks_obligations on conflict do nothing;
create policy groups_read on public.arks_groups for select to authenticated using(arks_private.allowed('view_team'));
grant select on public.arks_groups to authenticated;
create table public.arks_data_audit(id bigint generated always as identity primary key,actor text,action text,payload jsonb,created_at timestamptz default now());
alter table public.arks_data_audit enable row level security;
create policy audit_owner_read on public.arks_data_audit for select to authenticated using(arks_private.allowed('manage_members'));
grant select on public.arks_data_audit to authenticated;
create or replace function arks_private.manage_data(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.arks_staff; g public.arks_groups; target public.arks_groups; o public.arks_obligations; c public.arks_companies; d jsonb; k text; v text; result jsonb; admin boolean; active_count int;
begin
m:=arks_private.member();admin:=coalesce(m.role='admin',false);
if auth.uid() is null or m.email is null or not(admin or m.role='manager') then raise exception 'Owner or manager access required';end if;
perform pg_advisory_xact_lock(48273602);
if action in ('save_group','archive_group') then
 if nullif(payload->>'id','') is not null then select * into g from public.arks_groups where id=(payload->>'id')::uuid for update;if not found then raise exception 'Group not found';end if;if not admin and g.manager_email is distinct from m.email then raise exception 'This group is outside your team';end if;end if;
 if not admin and g.id is not null and exists(select 1 from public.arks_obligations scoped_task where scoped_task.data->>'owner'=g.name and not(m.scope='all' or (m.scope='selected' and scoped_task.entity=any(m.company_access)))) then raise exception 'Group includes companies outside your access';end if;
 if action='save_group' then
 v:=trim(payload->>'name');if coalesce(length(v),0)=0 or length(v)>150 then raise exception 'Enter a group name (up to 150 characters)';end if;
 if admin then k:=nullif(payload->>'manager_email','');else k:=m.email;end if;
 if k is not null and not exists(select 1 from public.arks_staff where email=k and active and role='manager') then raise exception 'Choose an active manager';end if;
 if g.id is null then insert into public.arks_groups(name,notes,manager_email) values(v,coalesce(payload->>'notes',''),k) returning * into g;
 else update public.arks_obligations set data=data||jsonb_build_object('owner',v),updated_at=now() where data->>'owner'=g.name;update public.arks_groups set name=v,notes=coalesce(payload->>'notes',''),manager_email=k,archived=coalesce((payload->>'archived')::boolean,false) where id=g.id returning * into g;end if;
 result:=to_jsonb(g);
 else
 select count(*) into active_count from public.arks_obligations where data->>'owner'=g.name and coalesce(data->>'archived','false')<>'true';
 if active_count>0 then
 select * into target from public.arks_groups where id=nullif(payload->>'replacement','')::uuid and not archived and id<>g.id;
 if target.id is null or (not admin and target.manager_email is distinct from m.email) then raise exception 'Choose an active replacement group in your team';end if;
 update public.arks_obligations set data=data||jsonb_build_object('owner',target.name),owner_email=null,updated_at=now() where data->>'owner'=g.name;
 end if;
 update public.arks_groups set archived=true where id=g.id;result:=jsonb_build_object('archived',true);
 end if;
elsif action='save_task' then
 select * into o from public.arks_obligations where ref=payload->>'ref' for update;
 if o.ref is null and nullif(payload->>'ref','') is not null then raise exception 'Obligation not found';end if;
 if not admin and not arks_private.allowed('edit_obligations') then raise exception 'Task editing not permitted';end if;
 d:=payload->'data';if jsonb_typeof(d)<>'object' then raise exception 'Invalid obligation';end if;
 if o.ref is not null and not admin and (not arks_private.allowed('edit_obligations',o.entity,o.owner_email,true) or not exists(select 1 from public.arks_groups where name=o.data->>'owner' and manager_email=m.email and not archived)) then raise exception 'Obligation outside your team';end if;
 v:=trim(d->>'entity');if not exists(select 1 from public.arks_companies where name=v and coalesce(details->>16,'false')<>'true') then raise exception 'Choose an active company';end if;
 if not admin and not(m.scope='all' or (m.scope='selected' and v=any(m.company_access))) then raise exception 'Company outside your access';end if;
 if coalesce(length(trim(d->>'title')),0)=0 or coalesce(length(trim(d->>'authority')),0)=0 then raise exception 'Enter title and authority';end if;
 select * into g from public.arks_groups where name=d->>'owner' and not archived;
 if g.id is null or (not admin and g.manager_email is distinct from m.email) then raise exception 'Choose a responsibility group in your team';end if;
 k:=nullif(payload->>'owner_email','');if k is not null and not exists(select 1 from public.arks_staff s where s.email=k and s.active and (admin or s.manager_email=m.email)) then raise exception 'Choose an active member in your team';end if;
 if coalesce(d->>'due','')<>'' and ((d->>'due') !~ '^\d{2}-[A-Z][a-z]{2}-\d{4}$' or to_char(to_date(d->>'due','DD-Mon-YYYY'),'DD-Mon-YYYY')<>d->>'due') then raise exception 'Invalid due date';end if;
 if d->>'status' not in ('Not started','In progress','Submitted to authority','Completed','Not applicable') or d->>'status' is null then raise exception 'Invalid status';end if;
 if d->>'status'='Completed' and coalesce(length(trim(d->>'evidence')),0)=0 then raise exception 'Evidence required to complete';end if;
 if not admin and d->>'status' in ('Completed','Not applicable') and not arks_private.allowed('approve_obligations',v,k,true) then raise exception 'Completion approval not permitted';end if;
 if o.ref is null then select 'C'||lpad((coalesce(max(substring(ref from 2)::int),0)+1)::text,3,'0') into k from public.arks_obligations where ref ~ '^C[0-9]+$';else k:=o.ref;end if;
 d:=coalesce(o.data,'{}')||d||jsonb_build_object('ref',k,'entity',v,'updatedBy',m.email,'updatedOn',now());
 insert into public.arks_obligations(ref,entity,owner_email,data) values(k,v,nullif(payload->>'owner_email',''),d) on conflict(ref) do update set entity=excluded.entity,owner_email=excluded.owner_email,data=excluded.data,updated_at=now();result:=d;
elsif action='save_company' then
 if not admin then raise exception 'Only owners manage companies';end if;
 d:=payload->'details';if jsonb_typeof(d)<>'array' or jsonb_array_length(d)<16 or coalesce(length(trim(d->>1)),0)=0 then raise exception 'Enter company details';end if;
 select * into c from public.arks_companies where code=payload->>'code' for update;
 if coalesce(d->>16,'false')='true' and exists(select 1 from public.arks_obligations where entity=c.name and coalesce(data->>'archived','false')<>'true') then raise exception 'Move or archive active obligations before archiving this company';end if;
 if c.code is null then select 'E'||lpad((coalesce(max(substring(code from 2)::int),0)+1)::text,2,'0') into k from public.arks_companies where code ~ '^E[0-9]+$';else k:=c.code;end if;
 d:=jsonb_set(d,'{0}',to_jsonb(k));v:=trim(d->>1);d:=jsonb_set(d,'{1}',to_jsonb(v));
 if c.code is not null and c.name<>v then
 update public.arks_obligations set entity=v,data=jsonb_set(data,'{entity}',to_jsonb(v)),updated_at=now() where entity=c.name;
 update public.arks_documents set company=v where company=c.name;
 update public.arks_staff set company_access=array_replace(company_access,c.name,v) where c.name=any(company_access);
 end if;
 insert into public.arks_companies(code,name,details) values(k,v,d) on conflict(code) do update set name=excluded.name,details=excluded.details;result:=d;
else raise exception 'Unknown management action';end if;
insert into public.arks_data_audit(actor,action,payload) values(m.email,action,jsonb_build_object('request',payload,'result',result));return result;
end $$;
revoke all on function arks_private.manage_data(text,jsonb) from public,anon;grant execute on function arks_private.manage_data(text,jsonb) to authenticated;
create or replace function public.arks_manage_data(action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select arks_private.manage_data(action,payload)$$;
revoke all on function public.arks_manage_data(text,jsonb) from public,anon;grant execute on function public.arks_manage_data(text,jsonb) to authenticated;
create or replace function arks_private.save_managed_member(member_email text,member_name text,member_role text,member_scope text,member_companies text[],member_permissions text[],member_active boolean,reporting_manager text,replacement_email text) returns void language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;t public.arks_staff;target text:=lower(trim(member_email));valid text[]:=array['view_dashboard','view_companies','view_obligations','edit_obligations','approve_obligations','assign_tasks','view_documents','upload_documents','view_team','export'];
begin
m:=arks_private.member();if auth.uid() is null or m.email is null then raise exception 'Sign in required';end if;
perform pg_advisory_xact_lock(48273601);
if member_active=false and exists(select 1 from public.arks_obligations where owner_email=target and coalesce(data->>'archived','false')<>'true') then
 if replacement_email is null or replacement_email=target or not exists(select 1 from public.arks_staff where email=replacement_email and active and (m.role='admin' or manager_email=m.email)) then raise exception 'Choose an active replacement member before removing access';end if;
 if m.role<>'admin' and not exists(select 1 from public.arks_staff where email=target and manager_email=m.email and role not in ('admin','manager')) then raise exception 'Member outside your team';end if;
 update public.arks_obligations set owner_email=replacement_email,updated_at=now() where owner_email=target;
 end if;
if m.role='admin' then
 perform arks_private.save_member(member_email,member_name,member_role,member_scope,member_companies,member_permissions,member_active);
 if reporting_manager is not null and not exists(select 1 from public.arks_staff where email=reporting_manager and role='manager' and active) then raise exception 'Choose an active manager';end if;
 if target=reporting_manager or (member_role in ('admin','manager') and reporting_manager is not null) then raise exception 'Only team members can report to a manager';end if;
 update public.arks_staff set manager_email=reporting_manager where email=target;
elsif m.role='manager' then
 select * into t from public.arks_staff where email=target for update;
 if target=m.email or (t.email is not null and (t.manager_email is distinct from m.email or t.role in ('admin','manager'))) then raise exception 'Member outside your team';end if;
 if member_role is null or member_role not in ('employee','viewer','custom') or member_scope is null or member_scope not in ('assigned','selected') or member_permissions is null or member_companies is null or member_active is null then raise exception 'Invalid team access';end if;
 if target !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or coalesce(length(trim(member_name)),0)=0 then raise exception 'Enter a valid name and email';end if;
 if not(member_permissions <@ valid) or not(member_permissions <@ m.permissions) then raise exception 'Team permissions cannot exceed your own';end if;
 if m.scope not in ('all','selected') or (m.scope='selected' and not(member_companies <@ m.company_access)) then raise exception 'Companies outside your access';end if;
 if exists(select 1 from unnest(member_companies) c where not exists(select 1 from public.arks_companies where name=c)) then raise exception 'Unknown company';end if;
 if member_permissions && array['edit_obligations','approve_obligations','assign_tasks','export'] and not('view_obligations'=any(member_permissions)) then raise exception 'Task actions require View obligations';end if;
 if 'approve_obligations'=any(member_permissions) and not('edit_obligations'=any(member_permissions)) then raise exception 'Approval requires Update tasks';end if;
 if 'upload_documents'=any(member_permissions) and not('view_documents'=any(member_permissions)) then raise exception 'Uploads require View documents';end if;
 insert into public.arks_staff(email,name,role,scope,company_access,permissions,active,manager_email) values(target,trim(member_name),member_role,member_scope,member_companies,member_permissions,member_active,m.email) on conflict(email) do update set name=excluded.name,role=excluded.role,scope=excluded.scope,company_access=excluded.company_access,permissions=excluded.permissions,active=excluded.active;
 insert into public.arks_member_audit(actor,member_email,settings) values(m.email,target,jsonb_build_object('role',member_role,'scope',member_scope,'companies',member_companies,'permissions',member_permissions,'active',member_active,'manager',m.email));
else raise exception 'Owner or manager access required';end if;
end $$;
revoke all on function arks_private.save_managed_member(text,text,text,text,text[],text[],boolean,text,text) from public,anon;grant execute on function arks_private.save_managed_member(text,text,text,text,text[],text[],boolean,text,text) to authenticated;
create or replace function public.arks_save_managed_member(member_email text,member_name text,member_role text,member_scope text,member_companies text[],member_permissions text[],member_active boolean,reporting_manager text,replacement_email text default null) returns void language sql security invoker set search_path='' as $$select arks_private.save_managed_member(member_email,member_name,member_role,member_scope,member_companies,member_permissions,member_active,reporting_manager,replacement_email)$$;
revoke all on function public.arks_save_managed_member(text,text,text,text,text[],text[],boolean,text,text) from public,anon;grant execute on function public.arks_save_managed_member(text,text,text,text,text[],text[],boolean,text,text) to authenticated;

create or replace function arks_private.assign_task(task_ref text,assignee_email text) returns void language plpgsql security definer set search_path='' as $$
declare task public.arks_obligations;assignee public.arks_staff;m public.arks_staff;
begin
m:=arks_private.member();if auth.uid() is null then raise exception 'Sign in required';end if;
select * into task from public.arks_obligations where ref=task_ref for update;
if not found or not arks_private.allowed('view_obligations',task.entity,task.owner_email,true) or not arks_private.allowed('assign_tasks',task.entity,task.owner_email,true) then raise exception 'Assignment not permitted';end if;
if m.role='manager' and not exists(select 1 from public.arks_groups where name=task.data->>'owner' and manager_email=m.email and not archived) then raise exception 'Obligation outside your team';end if;
if assignee_email is not null then select * into assignee from public.arks_staff where email=lower(assignee_email) and active;if not found or (m.role='manager' and assignee.manager_email is distinct from m.email) then raise exception 'Choose an active member in your team';end if;end if;
update public.arks_obligations set owner_email=lower(assignee_email),data=data||jsonb_build_object('updatedBy',auth.jwt()->>'email'),updated_at=now() where ref=task_ref;
insert into public.arks_data_audit(actor,action,payload) values(m.email,'task_assignment',jsonb_build_object('ref',task_ref,'from',task.owner_email,'to',assignee_email));
end $$;
create or replace function arks_private.update_task(task_ref text,task_status text,evidence text,comments text) returns void language plpgsql security definer set search_path='' as $$
declare task public.arks_obligations;m public.arks_staff;
begin
m:=arks_private.member();if auth.uid() is null then raise exception 'Sign in required';end if;
select * into task from public.arks_obligations where ref=task_ref for update;
if not found or not arks_private.allowed('view_obligations',task.entity,task.owner_email,true) or not arks_private.allowed('edit_obligations',task.entity,task.owner_email,true) then raise exception 'Task update not permitted';end if;
if m.role='manager' and not exists(select 1 from public.arks_groups where name=task.data->>'owner' and manager_email=m.email and not archived) then raise exception 'Obligation outside your team';end if;
if task_status is null or task_status not in ('Not started','In progress','Submitted to authority','Completed','Not applicable') then raise exception 'Invalid status';end if;
if task_status in ('Completed','Not applicable') and not arks_private.allowed('approve_obligations',task.entity,task.owner_email,true) then raise exception 'Completion approval not permitted';end if;
if task_status='Completed' and coalesce(length(trim(evidence)),0)=0 then raise exception 'Evidence required';end if;
update public.arks_obligations set data=data||jsonb_build_object('status',task_status,'evidence',coalesce(evidence,''),'comments',coalesce(comments,''),'updatedBy',auth.jwt()->>'email','updatedOn',now()),updated_at=now() where ref=task_ref;
insert into public.arks_data_audit(actor,action,payload) values(m.email,'task_status_update',jsonb_build_object('ref',task_ref,'from',task.data,'status',task_status,'evidence',evidence,'comments',comments));
end $$;
