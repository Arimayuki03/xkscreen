// Generic CDP evaluate helper: node .tools/cdp_eval.mjs "<expression>"
const expression = process.argv.slice(2).join(" ");
const targets = await (await fetch("http://127.0.0.1:9222/json")).json();
const page = targets.find((t) => t.type === "page");
if (!page) throw new Error("no page target");
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    pending.get(m.id)(m);
    pending.delete(m.id);
  }
});
await new Promise((r) => ws.addEventListener("open", r));
const send = (method, params) =>
  new Promise((res) => {
    const i = ++id;
    pending.set(i, res);
    ws.send(JSON.stringify({ id: i, method, params }));
  });
const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
const v = r.result?.result?.value;
console.log(typeof v === "string" ? v : JSON.stringify(v, null, 1));
ws.close();
