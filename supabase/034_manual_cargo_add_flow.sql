create or replace function public.manager_next_box_number(
  p_route text,
  p_year integer,
  p_voyage text,
  p_prefix text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'), 2, '0');
  v_max integer := 0;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  select coalesce(max(
    nullif(
      regexp_replace(
        substring(s.box_number from char_length(p_prefix) + 1),
        '[^0-9]',
        '',
        'g'
      ),
      ''
    )::integer
  ), 0)
  into v_max
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
    and s.box_number like p_prefix || '%';

  return p_prefix || lpad((v_max + 1)::text, 3, '0');
end;
$$;

grant execute on function public.manager_next_box_number(text,integer,text,text)
to authenticated;
