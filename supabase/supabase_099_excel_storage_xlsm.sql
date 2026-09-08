-- Keep the shared Excel template bucket aligned with the app and website.
-- Both clients accept XLSX/XLSM files up to 50 MB.

update storage.buckets
set allowed_mime_types = array[
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel.sheet.macroEnabled.12'
    ]::text[],
    file_size_limit = 52428800
where id = 'shipment-excel-templates';

do $$
begin
  if not exists (
    select 1
    from storage.buckets
    where id = 'shipment-excel-templates'
      and file_size_limit = 52428800
      and allowed_mime_types @> array[
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-excel.sheet.macroEnabled.12'
      ]::text[]
  ) then
    raise exception 'shipment-excel-templates XLSX/XLSM configuration failed';
  end if;
end;
$$;
