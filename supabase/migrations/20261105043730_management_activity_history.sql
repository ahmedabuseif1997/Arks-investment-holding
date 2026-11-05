create policy managers_data_history on public.arks_data_audit for select to authenticated using(actor=lower(auth.jwt()->>'email') and (arks_private.member()).role='manager');
create policy managers_member_history on public.arks_member_audit for select to authenticated using(actor=lower(auth.jwt()->>'email') and (arks_private.member()).role='manager');
