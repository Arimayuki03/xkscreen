// Live DOM/style probe for the console page over CDP (WebView2 debugging port).
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

const expr = `(() => {
  const grid = document.querySelector('div[class*="lg:grid-cols-2"]');
  const cs = grid ? getComputedStyle(grid) : null;
  const sheetRules = (() => {
    let hits = [];
    for (const s of document.styleSheets) {
      let rules; try { rules = s.cssRules; } catch { continue; }
      for (const r of rules) {
        if (r.cssRules) {
          for (const r2 of r.cssRules) {
            if (r2.selectorText && r2.selectorText.includes('lg\\\\:grid-cols-2'))
              hits.push((r.conditionText || r.media?.mediaText || 'layer') + ' -> ' + r2.cssText);
          }
        } else if (r.selectorText && r.selectorText.includes('lg\\\\:grid-cols-2')) {
          hits.push(r.cssText);
        }
      }
    }
    return hits;
  })();
  return JSON.stringify({
    innerWidth: window.innerWidth,
    dpr: window.devicePixelRatio,
    rootFontSize: getComputedStyle(document.documentElement).fontSize,
    mq768: matchMedia('(min-width: 768px)').matches,
    mq1024: matchMedia('(min-width: 1024px)').matches,
    mq64rem: matchMedia('(min-width: 64rem)').matches,
    gridFound: !!grid,
    gridClass: grid ? grid.className : null,
    gridDisplay: cs ? cs.display : null,
    gridCols: cs ? cs.gridTemplateColumns : null,
    gridChildren: grid ? grid.children.length : 0,
    gridWidth: grid ? Math.round(grid.getBoundingClientRect().width) : 0,
    sheetHits: sheetRules
  }, null, 1);
})()`;

const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true });
console.log(r.result?.result?.value ?? JSON.stringify(r));
ws.close();
