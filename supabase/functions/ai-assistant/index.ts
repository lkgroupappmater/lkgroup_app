const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function outputText(data: Record<string, unknown>): string {
  if (typeof data.output_text === 'string') return data.output_text;
  const output = Array.isArray(data.output)
    ? data.output as Record<string, unknown>[]
    : [];
  for (const item of output) {
    const content = Array.isArray(item.content)
      ? item.content as Record<string, unknown>[]
      : [];
    for (const block of content) {
      if (block.type === 'output_text' && typeof block.text === 'string') {
        return block.text;
      }
    }
  }
  return '';
}

function languageLabel(code: string): string {
  switch (code.toLowerCase()) {
    case 'en':
      return 'English';
    case 'lo':
      return 'Lao (ພາສາລາວ)';
    default:
      return 'Korean';
  }
}

async function callOpenAi(body: Record<string, unknown>) {
  const apiKey = Deno.env.get('OPENAI_API_KEY') ?? '';
  const model = Deno.env.get('OPENAI_MODEL') ?? 'gpt-5-mini';
  if (!apiKey) throw new Error('OPENAI_API_KEY is not configured.');
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model, ...body }),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(String(data?.error?.message ?? `OpenAI ${response.status}`));
  }
  return data as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json(405, { error: 'POST only' });
  if (!(req.headers.get('authorization') ?? '').trim()) {
    return json(401, { error: 'Authorization required' });
  }

  try {
    const body = await req.json() as Record<string, unknown>;
    const mode = String(body.mode ?? '');
    const target = String(body.target_language ?? 'ko');
    const targetLabel = languageLabel(target);

    if (mode === 'translate') {
      const texts = Array.isArray(body.texts)
        ? (body.texts as unknown[]).slice(0, 30).map(String)
        : [];
      if (!texts.length) return json(200, { translations: [] });
      const response = await callOpenAi({
        instructions:
          'You are LK Group Trading\'s translation engine. Translate every '
          + `item to ${targetLabel}. Preserve names, numbers, dates, route `
          + `codes and line breaks. Return exactly ${texts.length} translated `
          + 'items in the same order. Never merge items or move text from one '
          + 'item into another. Do not add explanations. Return only the '
          + 'required JSON.',
        input: JSON.stringify({ texts }),
        text: {
          format: {
            type: 'json_schema',
            name: 'translations',
            strict: true,
            schema: {
              type: 'object',
              properties: {
                translations: {
                  type: 'array',
                  minItems: texts.length,
                  maxItems: texts.length,
                  items: { type: 'string' },
                },
              },
              required: ['translations'],
              additionalProperties: false,
            },
          },
        },
      });
      const parsed = JSON.parse(outputText(response));
      return json(200, { translations: parsed.translations ?? texts });
    }

    if (mode === 'consult') {
      const question = String(body.question ?? '').trim().slice(0, 4000);
      if (!question) return json(400, { error: 'Question is required.' });
      const response = await callOpenAi({
        instructions:
          `Reply in ${targetLabel}. You are LK Group Trading's Korean-English-`
          + 'Lao shipping assistant. Answer only general guidance from the '
          + 'customer question. Never invent or infer an LK Group price, '
          + 'schedule, customs rule, customer record or delivery promise. For '
          + 'any company-specific fact, clearly say that staff confirmation is '
          + 'required. Do not expose or request personal data.',
        input: `CUSTOMER_QUESTION:\n${question}`,
      });
      return json(200, { answer: outputText(response) });
    }
    return json(400, { error: 'Unsupported mode.' });
  } catch (error) {
    return json(500, {
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
