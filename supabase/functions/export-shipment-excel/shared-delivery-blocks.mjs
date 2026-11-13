// Reserve existing customer blocks before assigning numbers. A new customer can
// reuse a vacated number without overwriting a different, still-present customer.
export function planDeliveryBlocks(profiles, blocks, {key, readKey, create}) {
  const assigned = new Map(), used = new Set();
  for (const profile of profiles) {
    const block = blocks.find(b => !used.has(b) && readKey(b) === key(profile));
    if (block) { assigned.set(profile, block); used.add(block); }
  }
  for (const profile of profiles) {
    if (assigned.has(profile)) continue;
    const number = deliveryNumber(profile);
    const block = blocks.find(b => !used.has(b) && b.number === number) || create(number);
    assigned.set(profile, block); used.add(block);
  }
  return {assigned, unused: blocks.filter(b => !used.has(b))};
}
export function deliveryNumber(profile) {
  return Number(profile.original_source_no || (Number(profile.source_no) >= 10000
    ? Number(profile.source_no) - 10000 : profile.source_no));
}
