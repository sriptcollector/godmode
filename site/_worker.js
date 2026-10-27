// godmode.orion-jones.com: serves install.sh straight from GitHub main, so the one-liner never goes stale.
// Falls back to the copy bundled at deploy time if GitHub is unreachable.
const RAW = "https://raw.githubusercontent.com/sriptcollector/godmode/main/install.sh";
const HEADERS = {
  "content-type": "text/plain; charset=utf-8",
  "cache-control": "no-cache",
  "access-control-allow-origin": "*",
  "x-content-type-options": "nosniff",
  "x-robots-tag": "noindex",
};

export default {
  async fetch(req, env) {
    const { pathname } = new URL(req.url);
    if (pathname !== "/" && pathname !== "/install.sh") return env.ASSETS.fetch(req);
    let body;
    try {
      const r = await fetch(RAW, { cf: { cacheTtl: 60 } });
      if (r.ok) body = await r.text();
    } catch {}
    if (!body?.startsWith("#!")) body = await (await env.ASSETS.fetch(new URL("/install.sh", req.url))).text();
    return new Response(body, { headers: HEADERS });
  },
};
