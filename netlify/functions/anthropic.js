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

    // If a scorecardUrl is provided, fetch the page here in the function
    // and inject the text into the prompt — no AI web search needed
    let messages = body.messages || [];
    if (body.scorecardUrl) {
      const pageRes = await fetch(body.scorecardUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
        }
      });

      if (!pageRes.ok) {
        return { statusCode: 502, body: JSON.stringify({ error: { message: `Could not fetch scorecard page: ${pageRes.status}` } }) };
      }

      let html = await pageRes.text();

      // Strip scripts, styles, nav noise — keep just text content
      html = html
        .replace(/<script[\s\S]*?<\/script>/gi, '')
        .replace(/<style[\s\S]*?<\/style>/gi, '')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s{3,}/g, '\n')
        .slice(0, 30000); // cap at 30k chars — plenty for a scorecard

      // Inject the fetched content into the user message
      messages = messages.map(m => {
        if (m.role === 'user') {
          return { ...m, content: m.content + '\n\nHere is the raw scorecard page text:\n\n' + html };
        }
        return m;
      });
    }

    // Call Anthropic — no web_search tool needed since we fetched the page ourselves
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: body.model || 'claude-haiku-4-5-20251001',
        max_tokens: body.max_tokens || 2000,
        messages
      })
    });

    const data = await response.json();
    return {
      statusCode: response.status,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    };

  } catch (err) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: { message: err.message } })
    };
  }
};
