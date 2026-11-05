drop policy arks_download on storage.objects;
create policy arks_download on storage.objects for select to authenticated using(bucket_id='arks-documents' and exists(select 1 from public.arks_documents d where d.storage_path=objects.name and arks_private.allowed('view_documents',d.company)));
