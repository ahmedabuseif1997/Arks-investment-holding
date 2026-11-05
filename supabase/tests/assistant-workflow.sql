begin;
insert into public.arks_staff(email,name,role,scope,company_access,permissions,active,manager_email) values
('assistant-manager@example.com','Assistant Manager','manager','selected',array['ARKS Holding (ADGM)'],array['view_obligations','edit_obligations','approve_obligations','assign_tasks','view_documents','upload_documents','view_team'],true,null),
('assistant-member@example.com','Assistant Member','employee','assigned','{}',array['view_obligations','edit_obligations','view_documents','upload_documents'],true,'assistant-manager@example.com'),
('assistant-other@example.com','Other Member','employee','assigned','{}',array['view_obligations','edit_obligations'],true,null);
insert into public.arks_groups(name,manager_email) values('Assistant test group','assistant-manager@example.com');
insert into public.arks_obligations(ref,entity,owner_email,data) values('ZA_ASSIST_TEST','ARKS Holding (ADGM)','assistant-member@example.com','{"ref":"ZA_ASSIST_TEST","entity":"ARKS Holding (ADGM)","title":"Test renewal","authority":"DET","owner":"Assistant test group","due":"10-Mar-2027","status":"Not started","evidence":"Original receipt","comments":""}');
select set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222","email":"assistant-member@example.com","role":"authenticated"}',true);
set local role authenticated;
do $$declare p public.arks_assistant_proposals;outcome jsonb;begin
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Updated through confirmation"}');
if (select data->>'comments' from public.arks_obligations where ref='ZA_ASSIST_TEST')<>'' then raise exception 'TEST FAILED: draft mutated task';end if;
outcome:=public.arks_assistant_confirm(p.id);perform public.arks_assistant_confirm(p.id);
if (select data->>'comments' from public.arks_obligations where ref='ZA_ASSIST_TEST')<>'Updated through confirmation' then raise exception 'TEST FAILED: confirmation did not apply';end if;
begin perform public.arks_assistant_propose('ZA_ASSIST_TEST','{}',true,'assistant-other@example.com');raise exception 'TEST FAILED: employee assignment';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
begin perform public.arks_assistant_propose('ZA_ASSIST_TEST','{"entity":"Injected company"}');raise exception 'TEST FAILED: field injection';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
begin perform public.arks_assistant_propose('ZA_ASSIST_TEST','{"status":"Completed"}');raise exception 'TEST FAILED: completion bypass';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"due":"10-Mar-2028"}',false,null,true,true);outcome:=public.arks_assistant_confirm(p.id);
if (select data->>'due' from public.arks_obligations where ref='ZA_ASSIST_TEST')<>'10-Mar-2027' then raise exception 'TEST FAILED: renewal applied before approval';end if;
if (select data->>'status' from public.arks_obligations where ref='ZA_ASSIST_TEST')<>'Awaiting manager approval' then raise exception 'TEST FAILED: missing pending status';end if;
begin perform public.arks_assistant_review((outcome->>'approval_id')::uuid,true);raise exception 'TEST FAILED: employee approval';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333","email":"assistant-other@example.com","role":"authenticated"}',true);
do $$begin
if exists(select 1 from public.arks_assistant_proposals) or exists(select 1 from public.arks_completion_requests) then raise exception 'TEST FAILED: cross-member actions leaked';end if;
begin perform public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Intrusion"}');raise exception 'TEST FAILED: task access escape';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","email":"assistant-manager@example.com","role":"authenticated"}',true);
do $$declare r public.arks_completion_requests;p public.arks_assistant_proposals;begin
select * into r from public.arks_completion_requests where task_ref='ZA_ASSIST_TEST' and status='pending';
if r.id is null then raise exception 'TEST FAILED: manager could not see own team review';end if;
begin perform public.arks_update_task('ZA_ASSIST_TEST','Completed','Receipt','');raise exception 'TEST FAILED: bypassed pending review';exception when others then if SQLERRM not like '%pending assistant%' then raise;end if;end;
begin perform public.arks_assign_task('ZA_ASSIST_TEST','assistant-member@example.com');raise exception 'TEST FAILED: reassigned pending review';exception when others then if SQLERRM not like '%pending assistant%' then raise;end if;end;
perform public.arks_assistant_review(r.id,true);perform public.arks_assistant_review(r.id,true);
if not exists(select 1 from public.arks_obligations where ref='ZA_ASSIST_TEST' and data->>'due'='10-Mar-2028' and data->>'status'='Not started') then raise exception 'TEST FAILED: next renewal cycle not open';end if;
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{}',false,null,true,false);
perform public.arks_assistant_confirm(p.id);
select * into r from public.arks_completion_requests where task_ref='ZA_ASSIST_TEST' and status='pending';
begin perform public.arks_assistant_review(r.id,true);raise exception 'TEST FAILED: manager self-approved';exception when others then if SQLERRM not like '%owner must approve%' then raise;end if;end;
perform public.arks_assistant_review(r.id,false,'Withdrawn for owner review');
begin perform public.arks_assistant_propose('ZA_ASSIST_TEST','{}',true,'assistant-other@example.com');raise exception 'TEST FAILED: manager assigned outside team';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Stale proposal"}');
perform public.arks_update_task('ZA_ASSIST_TEST','In progress','Original receipt','A newer change');
begin perform public.arks_assistant_confirm(p.id);raise exception 'TEST FAILED: stale proposal overwrote record';exception when others then if SQLERRM not like '%changed%' then raise;end if;end;
perform public.arks_assistant_cancel(p.id);
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Cancelled draft"}');perform public.arks_assistant_cancel(p.id);
begin perform public.arks_assistant_confirm(p.id);raise exception 'TEST FAILED: cancelled confirmation';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
reset role;
-- Document registration + final metadata confirmation, inside rollback only.
insert into storage.objects(bucket_id,name,metadata) values('arks-assistant-staging','082bea37-613b-4c76-a0e4-0d521399d5f8/assistant-test/renewal.pdf','{"size":12,"mimetype":"application/pdf"}');
select set_config('request.jwt.claims','{"sub":"082bea37-613b-4c76-a0e4-0d521399d5f8","email":"ahmed@arks.ae","role":"authenticated"}',true);
set local role authenticated;
do $$declare u public.arks_assistant_uploads;p public.arks_assistant_proposals;begin
u:=public.arks_assistant_stage('082bea37-613b-4c76-a0e4-0d521399d5f8/assistant-test/renewal.pdf','renewal.pdf');
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Document retained"}',false,null,false,false,u.id);
begin perform public.arks_assistant_confirm(p.id);raise exception 'TEST FAILED: confirmation without saved document';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
end $$;
reset role;
do $$declare p public.arks_assistant_proposals;u public.arks_assistant_uploads;begin
select * into p from public.arks_assistant_proposals where actor='ahmed@arks.ae';select * into u from public.arks_assistant_uploads where id=p.upload_id;
insert into storage.objects(bucket_id,name,metadata) values('arks-documents','082bea37-613b-4c76-a0e4-0d521399d5f8/ARKS Holding (ADGM)/'||u.id||'-renewal.pdf','{"size":12,"mimetype":"application/pdf"}');
end $$;
set local role authenticated;
do $$declare p public.arks_assistant_proposals;outcome jsonb;begin
select * into p from public.arks_assistant_proposals where actor='ahmed@arks.ae';outcome:=public.arks_assistant_confirm(p.id);perform public.arks_assistant_confirm(p.id);
if not exists(select 1 from public.arks_documents where id=(outcome->>'document_id')::uuid and obligation_ref='ZA_ASSIST_TEST') then raise exception 'TEST FAILED: document link not retained';end if;
if (select count(*) from public.arks_documents where obligation_ref='ZA_ASSIST_TEST')<>1 then raise exception 'TEST FAILED: duplicate saved document';end if;
-- Rejection preserves the saved evidence; a later explicit owner approval completes the task.
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{"comments":"Please approve completion"}',false,null,true,false);
outcome:=public.arks_assistant_confirm(p.id);
perform public.arks_assistant_review((outcome->>'approval_id')::uuid,false,'Please verify the evidence first');
if (select data->>'status' from public.arks_obligations where ref='ZA_ASSIST_TEST')='Completed' then raise exception 'TEST FAILED: rejected completion applied';end if;
if (select count(*) from public.arks_documents where obligation_ref='ZA_ASSIST_TEST')<>1 then raise exception 'TEST FAILED: rejection lost evidence';end if;
p:=public.arks_assistant_propose('ZA_ASSIST_TEST','{}',false,null,true,false);
outcome:=public.arks_assistant_confirm(p.id);perform public.arks_assistant_review((outcome->>'approval_id')::uuid,true);
if (select data->>'status' from public.arks_obligations where ref='ZA_ASSIST_TEST')<>'Completed' then raise exception 'TEST FAILED: approved ordinary completion';end if;
end $$;
rollback;
