-- Only manager roles can read this compact catalog; route_definitions remains private.
alter function public.list_excel_file_batches() security definer;
