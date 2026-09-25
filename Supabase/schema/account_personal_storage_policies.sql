-- account_personal_storage_policies.sql
-- Políticas RLS de objeto para los buckets `avatars` y `catches` (spec account-personal).
-- Prerrequisito: crear los buckets `avatars` y `catches` desde el dashboard
-- (Storage > New bucket) o el CLI de Supabase. Este script NO crea los buckets,
-- solo las políticas de acceso a nivel de objeto.
--
-- Convención de path: cada objeto vive bajo `{user_id}/...`, p.ej.
-- `avatars/3fa2.../foto.jpg` o `catches/3fa2.../captura.jpg`. Las políticas
-- comparan ese primer segmento del path con auth.uid() (storage.foldername
-- devuelve un array de segmentos del path del objeto).

-- ===========================================================================
-- Bucket: avatars
-- ===========================================================================
drop policy if exists avatars_own_select on storage.objects;
create policy avatars_own_select on storage.objects
  for select using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists avatars_own_insert on storage.objects;
create policy avatars_own_insert on storage.objects
  for insert with check (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists avatars_own_update on storage.objects;
create policy avatars_own_update on storage.objects
  for update using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  ) with check (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists avatars_own_delete on storage.objects;
create policy avatars_own_delete on storage.objects
  for delete using (
    bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ===========================================================================
-- Bucket: catches
-- ===========================================================================
drop policy if exists catches_own_select on storage.objects;
create policy catches_own_select on storage.objects
  for select using (
    bucket_id = 'catches' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists catches_own_insert on storage.objects;
create policy catches_own_insert on storage.objects
  for insert with check (
    bucket_id = 'catches' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists catches_own_update on storage.objects;
create policy catches_own_update on storage.objects
  for update using (
    bucket_id = 'catches' and auth.uid()::text = (storage.foldername(name))[1]
  ) with check (
    bucket_id = 'catches' and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists catches_own_delete on storage.objects;
create policy catches_own_delete on storage.objects
  for delete using (
    bucket_id = 'catches' and auth.uid()::text = (storage.foldername(name))[1]
  );
