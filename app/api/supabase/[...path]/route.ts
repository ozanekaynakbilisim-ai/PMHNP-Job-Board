import { NextRequest } from 'next/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const INTERNAL_SUPABASE_URL = (
  process.env.SUPABASE_INTERNAL_URL || 'http://api-gw:8000'
).replace(/\/$/, '');

const HOP_BY_HOP_REQUEST_HEADERS = new Set([
  'host',
  'connection',
  'content-length',
  'accept-encoding',
  'origin',
  'referer',
]);

const HOP_BY_HOP_RESPONSE_HEADERS = new Set([
  'connection',
  'content-length',
  'content-encoding',
  'transfer-encoding',
]);

async function proxySupabase(
  request: NextRequest,
  context: { params: Promise<{ path: string[] }> },
) {
  const { path } = await context.params;
  const cleanPath = (path || []).map(encodeURIComponent).join('/');
  const target = `${INTERNAL_SUPABASE_URL}/${cleanPath}${request.nextUrl.search}`;

  const headers = new Headers();
  request.headers.forEach((value, key) => {
    if (!HOP_BY_HOP_REQUEST_HEADERS.has(key.toLowerCase())) {
      headers.set(key, value);
    }
  });

  const method = request.method.toUpperCase();
  const body = method === 'GET' || method === 'HEAD'
    ? undefined
    : await request.arrayBuffer();

  try {
    const upstream = await fetch(target, {
      method,
      headers,
      body,
      redirect: 'manual',
      cache: 'no-store',
    });

    const responseHeaders = new Headers();
    upstream.headers.forEach((value, key) => {
      if (!HOP_BY_HOP_RESPONSE_HEADERS.has(key.toLowerCase())) {
        responseHeaders.set(key, value);
      }
    });

    // If an upstream Supabase endpoint returns an absolute internal redirect,
    // keep the browser on the same-origin proxy instead of leaking api-gw.
    const location = responseHeaders.get('location');
    if (location?.startsWith(INTERNAL_SUPABASE_URL)) {
      responseHeaders.set(
        'location',
        location.replace(INTERNAL_SUPABASE_URL, `${request.nextUrl.origin}/api/supabase`),
      );
    }

    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  } catch (error) {
    console.error('[supabase-proxy] upstream request failed', {
      method,
      path: cleanPath,
      error: error instanceof Error ? error.message : String(error),
    });
    return Response.json(
      { error: 'Supabase gateway unavailable' },
      { status: 502 },
    );
  }
}

export const GET = proxySupabase;
export const POST = proxySupabase;
export const PUT = proxySupabase;
export const PATCH = proxySupabase;
export const DELETE = proxySupabase;
export const OPTIONS = proxySupabase;
export const HEAD = proxySupabase;
