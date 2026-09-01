Patch180
- Discount group title lookup is now local to each side-by-side discount table.
  It no longer steals the neighboring group's title.
- FreightService name matching now uses phone mandatory + rough name tokens:
  '/', ',', ';', '|', parentheses, with or without spaces.
- Full multi-name match wins over loose token matches.
- Right discount percentage uses FreightService first, then Remark xx% as display-only fallback.
- Dollar discount/final calculation is still only FreightService actual math.
- Existing delivery default remains:
  normal city/province -> 카톡 명세서 선공유
  prepaid -> 한국 카톡 명세서 선공유 및 온라인 결제
- SQL none / Edge deploy none.
- Upload V00 once again after applying so corrected group names overwrite DB.
