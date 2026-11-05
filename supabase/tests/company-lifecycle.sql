begin;
select set_config('request.jwt.claims','{"sub":"082bea37-613b-4c76-a0e4-0d521399d5f8","email":"ahmed@arks.ae","role":"authenticated"}',true);
set local role authenticated;
do $$declare c jsonb;r jsonb;d jsonb;begin
c:=public.arks_manage_data('save_company','{"details":["","Test company","Test legal","Active","Dubai","DET","LIC-TEST","","Test activity","","","","","","",""]}');
perform public.arks_manage_data('save_group','{"name":"Company lifecycle test"}');
r:=public.arks_manage_data('save_task','{"data":{"title":"Test task","entity":"Test company","authority":"DET","owner":"Company lifecycle test","status":"Not started","due":"01-Dec-2026"}}');
d:=jsonb_set(c,'{16}','true');
begin perform public.arks_manage_data('save_company',jsonb_build_object('code',c->>0,'details',d));raise exception 'TEST FAILED: occupied company archived';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
begin perform public.arks_manage_data('save_task',jsonb_build_object('ref',r->>'ref','data',r||'{"due":"31-Feb-2027"}'::jsonb));raise exception 'TEST FAILED: invalid deadline accepted';exception when others then if SQLERRM like 'TEST FAILED%' then raise;end if;end;
c:=public.arks_manage_data('save_company',jsonb_build_object('code',c->>0,'details',jsonb_set(c,'{1}','"Renamed test company"')));
if not exists(select 1 from public.arks_obligations where ref=r->>'ref' and entity='Renamed test company' and data->>'entity'='Renamed test company') then raise exception 'TEST FAILED: rename propagation';end if;
perform public.arks_manage_data('save_task',jsonb_build_object('ref',r->>'ref','data',r||'{"entity":"Renamed test company","archived":true}'::jsonb));
perform public.arks_manage_data('save_company',jsonb_build_object('code',c->>0,'details',jsonb_set(c,'{16}','true')));
end $$;
rollback;
