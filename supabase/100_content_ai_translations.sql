-- Persist AI-generated public translations so anonymous clients do not need
-- direct access to the paid AI Edge Function.

alter table public.notices
  add column if not exists title_en text,
  add column if not exists content_en text,
  add column if not exists title_lo text,
  add column if not exists content_lo text;

alter table public.shipping_schedules
  add column if not exists route_en text,
  add column if not exists origin_en text,
  add column if not exists destination_en text,
  add column if not exists status_en text,
  add column if not exists detail_en text,
  add column if not exists route_lo text,
  add column if not exists origin_lo text,
  add column if not exists destination_lo text,
  add column if not exists status_lo text,
  add column if not exists detail_lo text;

comment on column public.notices.title_en is
  'English translation generated when an administrator saves the notice.';
comment on column public.notices.title_lo is
  'Lao translation generated when an administrator saves the notice.';
comment on column public.shipping_schedules.route_en is
  'English translation generated when an administrator saves the schedule.';
comment on column public.shipping_schedules.route_lo is
  'Lao translation generated when an administrator saves the schedule.';
