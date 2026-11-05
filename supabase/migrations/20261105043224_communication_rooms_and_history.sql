create table public.arks_messages(id uuid primary key default gen_random_uuid(),room text not null,author text not null,author_name text not null,body text not null check(length(body) between 1 and 4000),created_at timestamptz not null default now(),removed_at timestamptz,removal_requested_by text,removal_reason text);
create index arks_messages_room_time on public.arks_messages(room,created_at);
create table public.arks_message_history(id bigint generated always as identity primary key,message_id uuid not null references public.arks_messages(id),room text not null,actor text not null,action text not null,reason text,created_at timestamptz not null default now());
create index arks_message_history_room_time on public.arks_message_history(room,created_at);
create table arks_private.chat_retention(message_id uuid primary key references public.arks_messages(id),original_body text not null);
revoke all on arks_private.chat_retention from public,anon,authenticated;
create or replace function arks_private.can_chat(chat_room text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.arks_staff;o public.arks_obligations;
begin
m:=arks_private.member();if auth.uid() is null or m.email is null then return false;end if;
if chat_room='all' then return true;end if;
if left(chat_room,5)='team:' then return exists(select 1 from public.arks_staff s where s.email=substring(chat_room from 6) and s.role='manager' and (m.role='admin' or m.email=s.email or m.manager_email=s.email));end if;
if left(chat_room,5)='task:' then select * into o from public.arks_obligations where ref=substring(chat_room from 6);return o.ref is not null and arks_private.allowed('view_obligations',o.entity,o.owner_email,true);end if;
return false;end $$;
revoke all on function arks_private.can_chat(text) from public,anon;grant execute on function arks_private.can_chat(text) to authenticated;
create or replace function arks_private.can_moderate_chat(chat_room text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare m public.arks_staff;
begin
m:=arks_private.member();if auth.uid() is null or m.email is null then return false;end if;
if m.role='admin' then return true;end if;
if m.role<>'manager' or not arks_private.can_chat(chat_room) then return false;end if;
if chat_room='all' or chat_room='team:'||m.email then return true;end if;
return exists(select 1 from public.arks_obligations o join public.arks_groups g on g.name=o.data->>'owner' where 'task:'||o.ref=chat_room and g.manager_email=m.email);
end $$;
revoke all on function arks_private.can_moderate_chat(text) from public,anon;grant execute on function arks_private.can_moderate_chat(text) to authenticated;
alter table public.arks_messages enable row level security;
alter table public.arks_message_history enable row level security;
create policy messages_read on public.arks_messages for select to authenticated using(arks_private.can_chat(room));
create policy history_read on public.arks_message_history for select to authenticated using(arks_private.can_chat(room));
grant select on public.arks_messages,public.arks_message_history to authenticated;
create or replace function arks_private.chat_action(action text,chat_room text,message_id uuid default null,message_body text default null,reason text default null) returns void language plpgsql security definer set search_path='' as $$
declare m public.arks_staff;msg public.arks_messages;mid uuid;label text;
begin
m:=arks_private.member();if not arks_private.can_chat(chat_room) then raise exception 'Chat access not permitted';end if;
perform pg_advisory_xact_lock(hashtextextended(m.email,0));
if action='send' then
 if coalesce(length(trim(message_body)),0) not between 1 and 4000 then raise exception 'Enter a message up to 4,000 characters';end if;
 if (select count(*) from public.arks_messages where author=m.email and created_at>now()-interval '1 minute')>=20 then raise exception 'Please wait before sending more messages';end if;
 insert into public.arks_messages(room,author,author_name,body) values(chat_room,m.email,m.name,trim(message_body)) returning id into mid;insert into arks_private.chat_retention(message_id,original_body) values(mid,trim(message_body));label:='sent';
else
 select * into msg from public.arks_messages x where x.id=message_id and x.room=chat_room for update;
 if not found or msg.removed_at is not null then raise exception 'Message not available';end if;mid:=msg.id;
 if action='request_removal' then
 if msg.author<>m.email and not arks_private.can_moderate_chat(chat_room) then raise exception 'Only the author or moderator can request removal';end if;
 if msg.removal_requested_by is not null then raise exception 'Removal already awaiting approval';end if;
 if coalesce(length(trim(reason)),0)=0 then raise exception 'Give a reason for removal';end if;
 update public.arks_messages set removal_requested_by=m.email,removal_reason=trim(reason) where id=mid;label:='removal_requested';
 elsif action in ('approve_removal','reject_removal') then
 if not arks_private.can_moderate_chat(chat_room) then raise exception 'Manager or owner approval required';end if;
 if msg.removal_requested_by is null then raise exception 'No removal request';end if;
 if action='approve_removal' then update public.arks_messages set removed_at=now(),body='[Message removed with approval]',removal_requested_by=null where id=mid;label:='removal_approved';else update public.arks_messages set removal_requested_by=null,removal_reason=null where id=mid;label:='removal_rejected';end if;
 else raise exception 'Unknown chat action';end if;
end if;
insert into public.arks_message_history(message_id,room,actor,action,reason) values(mid,chat_room,m.email,label,coalesce(reason,msg.removal_reason));
end $$;
revoke all on function arks_private.chat_action(text,text,uuid,text,text) from public,anon;grant execute on function arks_private.chat_action(text,text,uuid,text,text) to authenticated;
create or replace function public.arks_chat_action(action text,chat_room text,message_id uuid default null,message_body text default null,reason text default null) returns void language sql security invoker set search_path='' as $$select arks_private.chat_action(action,chat_room,message_id,message_body,reason)$$;
revoke all on function public.arks_chat_action(text,text,uuid,text,text) from public,anon;grant execute on function public.arks_chat_action(text,text,uuid,text,text) to authenticated;
