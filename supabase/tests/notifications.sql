begin;
insert into public.arks_staff(email,name,role,scope,company_access,permissions,active,manager_email) values
('notify-manager@example.com','Notify Manager','manager','selected',array['ARKS Holding (ADGM)'],array['view_obligations','edit_obligations','view_documents'],true,null),
('notify-member@example.com','Notify Member','employee','assigned','{}',array['view_obligations','edit_obligations','view_documents'],true,'notify-manager@example.com'),
('notify-other@example.com','Other Manager','manager','all','{}',array['view_obligations','view_documents'],true,null);
insert into public.arks_groups(name,manager_email) values('Notify test group','notify-manager@example.com');
insert into public.arks_obligations(ref,entity,owner_email,data) values('ZA_NOTIFY_TEST','ARKS Holding (ADGM)','notify-member@example.com','{"ref":"ZA_NOTIFY_TEST","entity":"ARKS Holding (ADGM)","title":"Test renewal","authority":"DET","owner":"Notify test group","due":"10-Mar-2027","status":"Not started","evidence":"","comments":""}');
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","email":"notify-member@example.com","role":"authenticated"}',true);
update public.arks_obligations set data=data||'{"status":"In progress","comments":"Working on renewal"}' where ref='ZA_NOTIFY_TEST';
insert into public.arks_documents(company,obligation_ref,name,storage_path,mime_type,size_bytes,uploaded_by) values('ARKS Holding (ADGM)','ZA_NOTIFY_TEST','Notification test.pdf','test-notify/fixture.pdf','application/pdf',12,'082bea37-613b-4c76-a0e4-0d521399d5f8');
do $$begin
 if (select count(*) from public.arks_notifications where task_ref='ZA_NOTIFY_TEST' and recipient='notify-manager@example.com')<>2 then raise exception 'TEST FAILED: direct manager did not receive upload and update';end if;
 if not exists(select 1 from public.arks_notifications where task_ref='ZA_NOTIFY_TEST' and recipient='ahmed@arks.ae' and kind='document') then raise exception 'TEST FAILED: owner missing document notification';end if;
 if exists(select 1 from public.arks_notifications where task_ref='ZA_NOTIFY_TEST' and recipient='notify-other@example.com') then raise exception 'TEST FAILED: unrelated manager notified';end if;
end $$;
set local role authenticated;
do $$begin
 if exists(select 1 from public.arks_notifications where task_ref='ZA_NOTIFY_TEST') then raise exception 'TEST FAILED: employee sees management inbox';end if;
 begin perform public.arks_save_alert_settings(true,7);raise exception 'TEST FAILED: employee changed alert settings';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","email":"notify-manager@example.com","role":"authenticated"}',true);
do $$begin
 if (select count(*) from public.arks_notifications where task_ref='ZA_NOTIFY_TEST')<>2 then raise exception 'TEST FAILED: manager inbox scope';end if;
 perform public.arks_read_notifications();
 if exists(select 1 from public.arks_notifications where task_ref='ZA_NOTIFY_TEST' and read_at is null) then raise exception 'TEST FAILED: unread state not retained';end if;
 begin perform public.arks_save_alert_settings(true,15);raise exception 'TEST FAILED: manager changed owner settings';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"082bea37-613b-4c76-a0e4-0d521399d5f8","email":"ahmed@arks.ae","role":"authenticated"}',true);
do $$begin
 if not exists(select 1 from public.arks_notifications where task_ref='ZA_NOTIFY_TEST' and read_at is null) then raise exception 'TEST FAILED: manager marked owner inbox read';end if;
 perform public.arks_save_alert_settings(true,45);
 if not exists(select 1 from public.arks_alert_settings where enabled and lead_days=45) then raise exception 'TEST FAILED: owner settings not saved';end if;
 begin perform public.arks_save_alert_settings(true,9);raise exception 'TEST FAILED: invalid lead day accepted';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
 begin update public.arks_notifications set read_at=now();raise exception 'TEST FAILED: direct writes allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.arks_staff set active=false where email='notify-manager@example.com';
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","email":"notify-manager@example.com","role":"authenticated"}',true);
set local role authenticated;
do $$begin if exists(select 1 from public.arks_notifications) then raise exception 'TEST FAILED: inactive membership retained access';end if;end $$;
reset role;
rollback;
