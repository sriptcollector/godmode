// godmode.orion-jones.com: the GPS Spoofer download page for browsers, and install.sh for curl, served
// straight from GitHub main so the one-liner never goes stale.
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
    const browser = (req.headers.get("accept") || "").includes("text/html");
    // Browsers get the download page; `curl … | bash` (Accept: */*) gets the script.
    if ((pathname === "/" && browser) || (pathname !== "/" && pathname !== "/install.sh")) return env.ASSETS.fetch(req);
    let body;
    try {
      const r = await fetch(RAW, { cf: { cacheTtl: 60 } });
      if (r.ok) body = await r.text();
    } catch {}
    if (!body?.startsWith("#!")) body = await (await env.ASSETS.fetch(new URL("/install.sh", req.url))).text();
    return new Response(body, { headers: HEADERS });
  },
};
