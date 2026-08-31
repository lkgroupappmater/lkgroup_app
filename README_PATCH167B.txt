Patch167B - Patch167 correction

Confirmed root causes:
1) Province and city sections both restart No. from 1.
   Patch166/167 used one route_key+source_no key, so city 1~15 overwrote/collided with province 1~15.
2) Some BASE delivery cells contain TWO phone numbers.
   Example Lee Kyung-hwa/Lee Kyung-hee row contains 020-9550-5260 and 020-9784-4110.
   The importer normalized both into one long digit string, so a shipment with only 020-9550-5260 did not match.
3) Patch167 finalizer call accidentally omitted p_resequence=true.
   Existing LKS receipt numbers therefore remained unchanged.

This correction:
- makes city internal source_no = 10000 + original No. so province/city cannot collide
- clears stale route delivery profiles before importing the current BASE list
- improves DB phone_matches for multi-phone cells
- runs finalizer with p_resequence=true

No Edge Function deploy required.
