-- Patch167B
-- Fixes multi-phone delivery matching and makes the current BASE delivery list usable
-- when a cell contains two phone numbers (e.g. 020-9550-5260 / 020-9784-4110).

create or replace function public.phone_matches(
  p_left text,
  p_right text
)
returns boolean
language plpgsql
immutable
as $$
declare
  a text := regexp_replace(coalesce(p_left,''), '[^0-9]', '', 'g');
  b text := regexp_replace(coalesce(p_right,''), '[^0-9]', '', 'g');
begin
  if a = '' or b = '' then
    return false;
  end if;

  if a = b then
    return true;
  end if;

  -- Normal single-phone match.
  if length(a) >= 8 and length(b) >= 8 and right(a,8) = right(b,8) then
    return true;
  end if;

  -- BASE cells can contain multiple phone numbers. The importer historically
  -- normalized the entire cell into one digit string, so allow a complete
  -- 8+ digit phone to be contained inside that normalized string.
  if length(a) >= 8 and position(a in b) > 0 then
    return true;
  end if;
  if length(b) >= 8 and position(b in a) > 0 then
    return true;
  end if;

  return false;
end
$$;

revoke all on function public.phone_matches(text,text) from public;
grant execute on function public.phone_matches(text,text) to authenticated,service_role;
