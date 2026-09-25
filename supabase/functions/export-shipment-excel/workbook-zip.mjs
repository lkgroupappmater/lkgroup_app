// Standard ZIP method 8, using the runtime's native DEFLATE compressor.
// fflate owns CRCs, local headers, data descriptors and the central directory.
// Inject its constructors so the same writer is testable without a Deno import.
export async function zipWorkbook(files, { Zip, ZipPassThrough }) {
  const chunks = [];
  let total = 0;
  let failure;
  let finished = false;
  const zip = new Zip((error, chunk, final) => {
    if (error) { failure = error; return; }
    chunks.push(chunk);
    total += chunk.byteLength;
    if (final) finished = true;
  });
  try {
    // Sequential compression bounds memory on the small Edge worker.
    for (const [name, data] of Object.entries(files)) {
      const stream = new Blob([data]).stream().pipeThrough(new CompressionStream('deflate-raw'));
      const compressed = new Uint8Array(await new Response(stream).arrayBuffer());
      const entry = new ZipPassThrough(name);
      entry.compression = 8;
      entry.process = (_source, final) => entry.ondata(null, compressed, final);
      zip.add(entry);
      // Always push original bytes: ZipPassThrough computes their CRC and size.
      entry.push(data, true);
      if (failure) throw failure;
    }
    zip.end();
    if (failure) throw failure;
    if (!finished) throw new Error('Excel ZIP finalization did not complete.');
    const result = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
    return result;
  } catch (error) {
    zip.terminate();
    throw error;
  }
}
