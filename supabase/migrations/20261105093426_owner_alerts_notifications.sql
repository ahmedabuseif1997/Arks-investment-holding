begin;
create table public.arks_alert_settings (
 id boolean primary key default true check(id), enabled boolean not null default false,
 lead_days integer not null default 30 check(lead_days in (7,15,30,45)),
 updated_by text, updated_at timestamptz not null default now()
);
insert into public.arks_alert_settings(id) values(true);
alter table public.arks_alert_settings enable row level security;
revoke all on public.arks_alert_settings from anon,authenticated;
grant select on public.arks_alert_settings to authenticated;
grant all on public.arks_alert_settings to service_role;
create policy owner_alert_settings on public.arks_alert_settings for select to authenticated using ((select (arks_private.member()).role)='admin');
create function arks_private.save_alert_settings(alert_enabled boolean,days_before integer) returns void language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;
begin
 m:=arks_private.member();if m.email is null or m.role<>'admin' then raise exception 'Only owners can manage reminders';end if;
 if alert_enabled is null or days_before is null or days_before not in (7,15,30,45) then raise exception 'Choose 7, 15, 30 or 45 days';end if;
 update public.arks_alert_settings set enabled=alert_enabled,lead_days=days_before,updated_by=m.email,updated_at=now() where id=true;
 insert into public.arks_data_audit(actor,action,payload) values(m.email,'alert_settings_updated',jsonb_build_object('enabled',alert_enabled,'lead_days',days_before));
end $$;
revoke all on function arks_private.save_alert_settings(boolean,integer) from public,anon,authenticated;
grant execute on function arks_private.save_alert_settings(boolean,integer) to authenticated;
create function public.arks_save_alert_settings(alert_enabled boolean,days_before integer) returns void language sql security invoker set search_path='' as $$select arks_private.save_alert_settings(alert_enabled,days_before)$$;
revoke all on function public.arks_save_alert_settings(boolean,integer) from public,anon;
grant execute on function public.arks_save_alert_settings(boolean,integer) to authenticated;

create table public.arks_notifications (
 id uuid primary key default gen_random_uuid(), recipient text not null references public.arks_staff(email),
 kind text not null check(kind in ('document','update','approval')), title text not null, message text not null,
 task_ref text references public.arks_obligations(ref), company text not null,
 document_id uuid references public.arks_documents(id), actor text, details jsonb not null default '{}',
 created_at timestamptz not null default now(), read_at timestamptz
);
create index arks_notifications_inbox on public.arks_notifications(recipient,created_at desc);
create index arks_notifications_unread on public.arks_notifications(recipient) where read_at is null;
alter table public.arks_notifications enable row level security;
revoke all on public.arks_notifications from anon,authenticated;
grant select on public.arks_notifications to authenticated;
grant all on public.arks_notifications to service_role;
create function arks_private.notification_visible(target_company text,target_ref text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.arks_staff;o public.arks_obligations;
begin
 m:=arks_private.member();if m.email is null then return false;end if;
 if m.role='admin' then return true;end if;
 if target_ref is not null then select * into o from public.arks_obligations where ref=target_ref;
 return o.ref is not null and arks_private.allowed('view_obligations',o.entity,o.owner_email,true) and (o.owner_email=m.email or (m.role='manager' and (exists(select 1 from public.arks_staff s where s.email=o.owner_email and s.manager_email=m.email and s.active) or exists(select 1 from public.arks_groups g where g.name=o.data->>'owner' and g.manager_email=m.email and not g.archived))));
 end if;
 return m.role='manager' and arks_private.allowed('view_documents',target_company);
end $$;
revoke all on function arks_private.notification_visible(text,text) from public,anon,authenticated;
grant execute on function arks_private.notification_visible(text,text) to authenticated;
create policy own_notification on public.arks_notifications for select to authenticated using (recipient=(select (arks_private.member()).email) and arks_private.notification_visible(company,task_ref));
create function arks_private.read_notifications(notification_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;
begin
 m:=arks_private.member();if m.email is null then raise exception 'Sign in required';end if;
 update public.arks_notifications n set read_at=coalesce(n.read_at,now()) where n.recipient=m.email and (notification_id is null or n.id=notification_id) and arks_private.notification_visible(n.company,n.task_ref);
end $$;
revoke all on function arks_private.read_notifications(uuid) from public,anon,authenticated;
grant execute on function arks_private.read_notifications(uuid) to authenticated;
create function public.arks_read_notifications(notification_id uuid default null) returns void language sql security invoker set search_path='' as $$select arks_private.read_notifications(notification_id)$$;
revoke all on function public.arks_read_notifications(uuid) from public,anon;
grant execute on function public.arks_read_notifications(uuid) to authenticated;

create function arks_private.notify_compliance(event_kind text,event_title text,event_message text,event_company text,event_ref text,event_document uuid,event_actor text,event_details jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
declare o public.arks_obligations;
begin
 if event_ref is not null then select * into o from public.arks_obligations where ref=event_ref;end if;
 insert into public.arks_notifications(recipient,kind,title,message,company,task_ref,document_id,actor,details)
 select s.email,event_kind,left(event_title,250),left(event_message,1000),event_company,event_ref,event_document,event_actor,event_details
 from public.arks_staff s where s.active and (s.role='admin' or
 (s.role='manager' and 'view_obligations'=any(s.permissions) and (s.scope='all' or (s.scope='selected' and event_company=any(s.company_access))) and
 (exists(select 1 from public.arks_staff responsible where responsible.email=o.owner_email and responsible.manager_email=s.email and responsible.active)
 or exists(select 1 from public.arks_groups g where g.name=o.data->>'owner' and g.manager_email=s.email and not g.archived)
 or (event_ref is null and exists(select 1 from public.arks_staff uploader where uploader.email=event_actor and uploader.manager_email=s.email and uploader.active)))));
end $$;
revoke all on function arks_private.notify_compliance(text,text,text,text,text,uuid,text,jsonb) from public,anon,authenticated;
create function arks_private.compliance_notification_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare who text;info jsonb;
begin
 who:=lower(auth.jwt()->>'email');
 if tg_table_name='arks_documents' then
 if who is null then select email into who from auth.users where id=new.uploaded_by;end if;
 perform arks_private.notify_compliance('document','Document uploaded',new.name,new.company,new.obligation_ref,new.id,who,jsonb_build_object('name',new.name));
 elsif tg_table_name='arks_obligations' then
 if (new.data-'updatedBy'-'updatedOn') is not distinct from (old.data-'updatedBy'-'updatedOn') then return new;end if;
 if new.data->>'status'='Awaiting manager approval' then return new;end if;
 info:=jsonb_build_object('previous_status',old.data->>'status','status',new.data->>'status','due',new.data->>'due');
 perform arks_private.notify_compliance('update','Obligation updated',new.data->>'title',new.entity,new.ref,null,coalesce(who,new.data->>'updatedBy'),info);
 elsif tg_table_name='arks_completion_requests' then
 if tg_op='INSERT' then
 perform arks_private.notify_compliance('approval','Completion awaiting approval','Evidence and a completion update are ready for review.',(select entity from public.arks_obligations where ref=new.task_ref),new.task_ref,new.document_id,new.requested_by,jsonb_build_object('request_id',new.id,'status',new.status));
 elsif new.status is distinct from old.status then
 perform arks_private.notify_compliance('approval','Completion '||new.status,coalesce(new.review_reason,''),(select entity from public.arks_obligations where ref=new.task_ref),new.task_ref,new.document_id,new.reviewed_by,jsonb_build_object('request_id',new.id,'status',new.status));
 end if;
 end if;
 return new;
end $$;
revoke all on function arks_private.compliance_notification_trigger() from public,anon,authenticated;
create trigger arks_document_notifications after insert on public.arks_documents for each row execute function arks_private.compliance_notification_trigger();
create trigger arks_obligation_notifications after update on public.arks_obligations for each row execute function arks_private.compliance_notification_trigger();
create trigger arks_completion_notifications after insert or update on public.arks_completion_requests for each row execute function arks_private.compliance_notification_trigger();
commit;
