-- 087_check_global_normalize_install.sql
-- 설치/기본 판정 검증. 데이터 전체 backfill은 하지 않습니다.
select
  public.lk_recipient_true_unknown('수신인불명','????') as both_bad_unknown,
  public.lk_recipient_needs_review('김요셉','????') as name_only_review,
  public.lk_recipient_needs_review('박*민','020-5555-1234') as masked_name_review,
  public.lk_recipient_true_unknown('박*민','????') as both_masked_unknown;

select
  p.proname,
  pg_get_function_identity_arguments(p.oid) args
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'normalize_shipment_batch',
    'shipments_auto_normalize_trigger',
    'lk_recipient_true_unknown',
    'lk_recipient_needs_review'
  )
order by p.proname;
