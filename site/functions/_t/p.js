const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export async function onRequest(context) {
  const { request, env } = context;

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: CORS });
  }

  let body = {};
  try {
    body = await request.json();
  } catch {
    body = {};
  }

  const envelope = {
    path: body.path || "/",
    ref: body.ref || request.headers.get("Referer") || "",
    sw: body.sw,
    sh: body.sh,
    tz: body.tz,
    lang: body.lang,
    plat: body.plat,
    dpr: body.dpr,
    conn: body.conn,
    cf_ip: request.headers.get("CF-Connecting-IP"),
    cf_country: request.headers.get("CF-IPCountry"),
    ua: request.headers.get("User-Agent"),
    accept_language: request.headers.get("Accept-Language"),
  };

  if (env.INGEST_URL) {
    context.waitUntil(
      fetch(env.INGEST_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "User-Agent": envelope.ua || "pages-forward",
          "X-Forwarded-For": envelope.cf_ip || "",
          "X-Original-Referer": envelope.ref || "",
        },
        body: JSON.stringify(envelope),
      }).catch(() => {})
    );
  }

  return new Response(null, { status: 204, headers: CORS });
}
