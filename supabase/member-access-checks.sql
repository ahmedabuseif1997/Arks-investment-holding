begin;
insert into public.arks_staff(email,name,role,scope,company_access,permissions,active) values
('arks-access-employee@example.invalid','Permission test employee','employee','assigned','{}',array['view_companies','view_obligations','edit_obligations','view_documents','upload_documents'],true),
('arks-access-viewer@example.invalid','Permission test viewer','viewer','selected',array['Ecosine Transports'],array['view_companies','view_obligations','view_documents'],true),
('arks-access-manager@example.invalid','Permission test manager','manager','selected',array['Ecosine Transports'],array['view_companies','view_obligations','edit_obligations','assign_tasks','view_documents'],true);
insert into public.arks_obligations(ref,entity,owner_email,data) values
('ACCESS_TEST_OWN','Ecosine Transports','arks-access-employee@example.invalid','{"status":"Not started","title":"Permission test"}'),
('ACCESS_TEST_SIBLING','Ecosine Transports',null,'{"status":"Not started"}'),
('ACCESS_TEST_OTHER','PowerDrive',null,'{"status":"Not started"}');
set local role authenticated;
set local request.jwt.claims='{"sub":"11111111-1111-4111-8111-111111111111","email":"arks-access-employee@example.invalid","role":"authenticated"}';
do $$ declare denied boolean:=false;begin
if (select count(*) from public.arks_obligations where ref like 'ACCESS_TEST_%')<>1 then raise exception 'FAIL assigned task isolation';end if;
perform public.arks_update_task('ACCESS_TEST_OWN','In progress','','test update');
if not exists(select 1 from public.arks_obligations where ref='ACCESS_TEST_OWN' and data->>'status'='In progress') then raise exception 'FAIL employee update';end if;
begin perform public.arks_update_task('ACCESS_TEST_OWN','Completed','test evidence','');exception when raise_exception then denied:=true;end;
if not denied then raise exception 'FAIL employee approved closure';end if;
denied:=false;
begin perform public.arks_save_member('escalation@example.invalid','Escalation','admin','all','{}','{}',true);exception when raise_exception then denied:=true;end;
if not denied then raise exception 'FAIL employee escalated privileges';end if;
denied:=false;
begin update public.arks_staff set role='admin' where email='arks-access-employee@example.invalid';exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'FAIL direct member modification permitted';end if;
if not arks_private.allowed('upload_documents','Ecosine Transports') or arks_private.allowed('view_documents','PowerDrive') then raise exception 'FAIL document company isolation';end if;
end $$;
set local request.jwt.claims='{"sub":"22222222-2222-4222-8222-222222222222","email":"arks-access-viewer@example.invalid","role":"authenticated"}';
do $$ declare denied boolean:=false;begin
if (select count(*) from public.arks_obligations where ref like 'ACCESS_TEST_%')<>2 then raise exception 'FAIL selected company visibility';end if;
begin perform public.arks_update_task('ACCESS_TEST_SIBLING','In progress','','');exception when raise_exception then denied:=true;end;
if not denied then raise exception 'FAIL viewer updated task';end if;
if arks_private.allowed('upload_documents','Ecosine Transports') then raise exception 'FAIL viewer upload allowed';end if;
end $$;
set local request.jwt.claims='{"sub":"33333333-3333-4333-8333-333333333333","email":"arks-access-manager@example.invalid","role":"authenticated"}';
do $$ declare denied boolean:=false;begin
perform public.arks_assign_task('ACCESS_TEST_SIBLING','arks-access-employee@example.invalid');
begin perform public.arks_assign_task('ACCESS_TEST_OTHER','arks-access-employee@example.invalid');exception when raise_exception then denied:=true;end;
if not denied then raise exception 'FAIL cross company task assignment';end if;
end $$;
reset role;
update public.arks_staff set active=false where email='arks-access-employee@example.invalid';
set local role authenticated;
set local request.jwt.claims='{"sub":"11111111-1111-4111-8111-111111111111","email":"arks-access-employee@example.invalid","role":"authenticated"}';
do $$ begin if exists(select 1 from public.arks_obligations) or arks_private.allowed('view_documents','Ecosine Transports') then raise exception 'FAIL suspended member retained access';end if;end $$;
set local request.jwt.claims='{"sub":"082bea37-613b-4c76-a0e4-0d521399d5f8","email":"ahmed@arks.ae","role":"authenticated"}';
do $$ declare denied boolean:=false;begin
perform public.arks_save_member('arks-access-viewer@example.invalid','Updated permission test','viewer','selected',array['PowerDrive'],array['view_obligations'],true);
if not exists(select 1 from public.arks_staff where email='arks-access-viewer@example.invalid' and company_access=array['PowerDrive']) then raise exception 'FAIL admin member update';end if;
begin perform public.arks_save_member('ahmed@arks.ae','Ahmed','viewer','all','{}','{}',false);exception when raise_exception then denied:=true;end;
if not denied then raise exception 'FAIL own admin removal';end if;
end $$;
reset role;
rollback;
select 'PASS: assigned and company scopes, employee updates, viewer restrictions, document permissions, blocked escalation, scoped assignment, suspension and admin protections' as access_checks;
