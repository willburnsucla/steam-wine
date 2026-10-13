// Screenshot a Steam CEF page through Chrome DevTools (Steam launched with -cef-enable-debugging).
// Usage: node tools/cdp-shot.mjs "<page title substring>" out.png [port]
import { writeFileSync } from "node:fs";

const [title, out, port = "8080"] = process.argv.slice(2);
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const t = targets.find((x) => x.type === "page" && x.title.includes(title));
if (!t) {
  console.error("no page matching", title, targets.map((x) => x.title));
  process.exit(1);
}
const ws = new WebSocket(t.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((resolve) => {
    pending.set(++id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) pending.get(m.id)(m);
};
await new Promise((r) => (ws.onopen = r));
const res = await send("Page.captureScreenshot", { format: "png" });
if (!res.result) {
  console.error("capture failed", JSON.stringify(res.error));
  process.exit(1);
}
writeFileSync(out, Buffer.from(res.result.data, "base64"));
console.log("saved", out);
ws.close();
