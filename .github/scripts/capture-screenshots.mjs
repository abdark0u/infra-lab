// Saca las capturas del README (la web y el dashboard de Grafana) con Playwright.
// Espera a que todo esté dibujado de verdad y, si algo no carga, falla: prefiero
// ver el workflow en rojo a subir una captura rota. Además enseña los errores del
// navegador para poder depurar.
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const BASE_URL = process.env.BASE_URL ?? "http://localhost:8080";
const OUT_DIR = process.env.OUT_DIR ?? "screenshots";

const TARGETS = [
  {
    name: "web",
    url: `${BASE_URL}/`,
    viewport: { width: 1100, height: 560 },
    readySelector: "#visits",
  },
  {
    name: "grafana-dashboard",
    url: `${BASE_URL}/grafana/d/infra-lab-overview/infra-lab-overview?orgId=1&from=now-3m&to=now&kiosk`,
    viewport: { width: 1600, height: 960 },
    // Grafana pinta las gráficas en <canvas>, así que espero a que haya uno
    readySelector: "canvas",
    settleMs: 5000,
  },
];

async function capture(browser, target) {
  // Ojo: sin locale, Chromium coge el del runner ("en-US@posix"), que
  // Intl.NumberFormat no acepta, y Grafana ni llega a arrancar. Por eso lo fijo.
  const page = await browser.newPage({
    viewport: target.viewport,
    locale: "es-ES",
    timezoneId: "Europe/Madrid",
  });
  const problems = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") problems.push(`console: ${msg.text()}`);
  });
  page.on("pageerror", (error) => problems.push(`pageerror: ${error.message}`));
  page.on("requestfailed", (request) =>
    problems.push(`requestfailed: ${request.url()} (${request.failure()?.errorText})`),
  );
  page.on("response", (response) => {
    if (response.status() >= 400) problems.push(`HTTP ${response.status()}: ${response.url()}`);
  });

  let ok = true;
  try {
    await page.goto(target.url, { waitUntil: "load" });
    await page.waitForSelector(target.readySelector, { state: "visible", timeout: 60_000 });
    await page.waitForTimeout(target.settleMs ?? 1000);
  } catch (error) {
    ok = false;
    problems.push(`no se pudo cargar: ${error.message.split("\n")[0]}`);
  }

  const file = `${OUT_DIR}/${target.name}${ok ? "" : "-FALLO"}.png`;
  await page.screenshot({ path: file });
  await page.close();

  console.log(`${ok ? "OK   " : "FALLO"} ${target.name} -> ${file}`);
  for (const problem of problems) console.log(`      ${problem}`);
  return ok;
}

await mkdir(OUT_DIR, { recursive: true });
const browser = await chromium.launch();
let allOk = true;
for (const target of TARGETS) {
  allOk = (await capture(browser, target)) && allOk;
}
await browser.close();
process.exit(allOk ? 0 : 1);
