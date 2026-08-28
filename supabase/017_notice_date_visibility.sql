-- LK Group: 공지/안내 등록 날짜 표시 여부
-- 기존 공지는 기본적으로 날짜를 표시합니다.

alter table public.notices
  add column if not exists show_published_date boolean not null default true;

comment on column public.notices.show_published_date
  is '홈 및 공지/안내 목록에서 등록 날짜를 표시할지 여부';

grant select on table public.notices to anon, authenticated;
grant insert, update on table public.notices to authenticated;
