// Keep DEFLATE outside JavaScript's small Edge CPU budget. fflate still parses
// ZIP headers (including streamed entries), and the native runtime inflates bytes.
export async function unzipWorkbook(data, { Unzip, filter = () => true }) {
  const files = Object.create(null);
  let sequence = Promise.resolve(), failure, pending = 0;
  class NativeInflate {
    static compression = 8;
    chunks = [];
    push(chunk, final) {
      this.chunks.push(chunk);
      if (!final) return;
      sequence = sequence.then(async () => {
        try {
          const stream = new Blob(this.chunks).stream().pipeThrough(new DecompressionStream('deflate-raw'));
          this.chunks = [];
          this.ondata(null, new Uint8Array(await new Response(stream).arrayBuffer()), true);
        } catch (error) { this.ondata(error, null, true); }
      });
    }
  }
  const unzip = new Unzip(file => {
    if (!filter(file)) return;
    pending++;
    const chunks = [];
    let length = 0;
    file.ondata = (error, chunk, final) => {
      if (error) { failure ??= error; return; }
      chunks.push(chunk); length += chunk.length;
      if (!final) return;
      const bytes = chunks.length === 1 ? chunks[0] : new Uint8Array(length);
      if (chunks.length !== 1) {
        let offset = 0;
        for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
      }
      if (file.originalSize !== undefined && length !== file.originalSize) {
        failure ??= new Error(`Incomplete Excel ZIP entry: ${file.name}`);
      }
      files[file.name] = bytes;
      pending--;
    };
    file.start();
  });
  unzip.register(NativeInflate);
  unzip.push(data, true);
  await sequence;
  if (failure) throw failure;
  if (pending) throw new Error('Incomplete Excel ZIP archive.');
  return files;
}

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
