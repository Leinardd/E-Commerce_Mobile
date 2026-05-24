const PAYMONGO_BASE = 'https://api.paymongo.com/v1';
const SECRET_KEY = Deno.env.get('PAYMONGO_SECRET_KEY') ?? '';
const AUTH_HEADER = 'Basic ' + btoa(SECRET_KEY + ':');

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }

  try {
    const { action, payload } = await req.json();

    if (action === 'create_session') {
      const res = await fetch(`${PAYMONGO_BASE}/checkout_sessions`, {
        method: 'POST',
        headers: {
          Authorization: AUTH_HEADER,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok) {
        console.error('[paymongo] create_session error:', JSON.stringify(data));
        return new Response(JSON.stringify({ error: data }), {
          status: res.status,
          headers: { ...cors, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify(data), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    if (action === 'get_session') {
      const { session_id } = payload as { session_id: string };
      const res = await fetch(`${PAYMONGO_BASE}/checkout_sessions/${session_id}`, {
        headers: { Authorization: AUTH_HEADER },
      });
      const data = await res.json();
      if (!res.ok) {
        return new Response(JSON.stringify({ error: data }), {
          status: res.status,
          headers: { ...cors, 'Content-Type': 'application/json' },
        });
      }
      return new Response(JSON.stringify(data), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ error: 'Unknown action' }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[paymongo] unhandled error:', e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
