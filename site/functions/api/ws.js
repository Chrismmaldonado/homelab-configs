const HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

export async function onRequest(context) {
  if (context.request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: HEADERS });
  }
  if (context.request.method !== "GET") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: HEADERS,
    });
  }

  const url = context.env.WS_URL || "";
  const fallbacks = [];
  if (context.env.WS_FALLBACK_URL) {
    fallbacks.push(context.env.WS_FALLBACK_URL);
  }
  fallbacks.push("wss://terminal.christopher-lab.pages.dev");

  const body = {
    url,
    fallbacks: [...new Set(fallbacks.filter(Boolean))],
    source: "pages-api",
    updatedAt: context.env.WS_UPDATED_AT || null,
  };

  return new Response(JSON.stringify(body), { status: 200, headers: HEADERS });
}
