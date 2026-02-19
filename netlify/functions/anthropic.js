exports.handler = async function(event) {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  const ANTHROPIC_KEY = process.env.ANTHROPIC_KEY;
  if (!ANTHROPIC_KEY) {
    return { statusCode: 500, body: JSON.stringify({ error: { message: 'ANTHROPIC_KEY not set' } }) };
  }

  try {
    const body = JSON.parse(event.body);
    let messages = [...(body.messages || [])];
    let finalData = null;

    // Loop to handle pause_turn (Anthropic pauses long web search turns)
    for (let i = 0; i < 5; i++) {
      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': ANTHROPIC_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({ ...body, messages })
      });

      const data = await response.json();

      if (!response.ok) {
        return { statusCode: response.status, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) };
      }

      finalData = data;

      // Done
      if (data.stop_reason === 'end_turn') break;

      // Paused mid-search — send response back as-is to let Claude continue
      if (data.stop_reason === 'pause_turn') {
        messages = [
          ...messages,
          { role: 'assistant', content: data.content }
        ];
        continue;
      }

      // Any other stop reason — return what we have
      break;
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(finalData)
    };

  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: { message: err.message } })
    };
  }
};
