begin;
insert into public.arks_staff(email,name,role,scope,company_access,permissions,active,manager_email) values('chat-manager@example.com','Chat Manager','manager','all','{}',array['view_team','view_obligations'],true,null),('chat-member@example.com','Chat Member','employee','assigned','{}',array['view_obligations'],true,'chat-manager@example.com'),('chat-outsider@example.com','Outsider','employee','assigned','{}','{}',true,null);
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","email":"chat-member@example.com","role":"authenticated"}',true);
set local role authenticated;
select public.arks_chat_action('send','team:chat-manager@example.com',null,'Private team test',null);
do $$declare mid uuid;begin
select id into mid from public.arks_messages where room='team:chat-manager@example.com';
perform public.arks_chat_action('request_removal','team:chat-manager@example.com',mid,null,'Test removal approval');
begin perform public.arks_chat_action('approve_removal','team:chat-manager@example.com',mid);raise exception 'TEST FAILED: member approved deletion';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
begin update public.arks_messages set body='Tampered' where id=mid;if found then raise exception 'TEST FAILED: direct edit';end if;exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333","email":"chat-outsider@example.com","role":"authenticated"}',true);
do $$begin
if exists(select 1 from public.arks_messages where room='team:chat-manager@example.com') then raise exception 'TEST FAILED: team leak';end if;
begin perform public.arks_chat_action('send','team:chat-manager@example.com',null,'Intrusion');raise exception 'TEST FAILED: outsider sent';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","email":"chat-manager@example.com","role":"authenticated"}',true);
do $$declare mid uuid;begin
select id into mid from public.arks_messages where room='team:chat-manager@example.com';
perform public.arks_chat_action('approve_removal','team:chat-manager@example.com',mid);
if not exists(select 1 from public.arks_messages where id=mid and removed_at is not null) then raise exception 'TEST FAILED: approval';end if;
if (select count(*) from public.arks_message_history where message_id=mid)<>3 then raise exception 'TEST FAILED: audit history';end if;
begin delete from public.arks_message_history where message_id=mid;if found then raise exception 'TEST FAILED: history erased';end if;exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin if not exists(select 1 from arks_private.chat_retention where original_body='Private team test') then raise exception 'TEST FAILED: original audit retention';end if;end $$;
rollback;
