// Dirige o build web do IaGo no Chrome headless (360 px) e tira capturas.
// Uso: node drive.js <url> <pasta-de-saida> [passos...]
// Bloqueia qualquer pedido fora do localhost para provar que roda offline.
const { chromium } = require('playwright-core');
const path = require('path');
const fs = require('fs');

const url = process.argv[2] || 'http://127.0.0.1:8765/';
const outDir = process.argv[3] || path.join(__dirname, 'shots');
const steps = process.argv.slice(4);
fs.mkdirSync(outDir, { recursive: true });

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const context = await browser.newContext({
    viewport: { width: 360, height: 780 },
    deviceScaleFactor: 2,
    locale: 'pt-BR',
  });
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(url).origin });
  const page = await context.newPage();
  const errors = [];
  const blocked = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await page.route('**/*', (route) => {
    const u = route.request().url();
    if (u.startsWith('http://127.0.0.1') || u.startsWith('http://localhost') || u.startsWith('data:') || u.startsWith('blob:')) {
      return route.continue();
    }
    blocked.push(u);
    return route.abort();
  });

  let n = 0;
  const shot = async (name) => {
    n += 1;
    const file = path.join(outDir, `${String(n).padStart(2, '0')}-${name}.png`);
    await page.screenshot({ path: file });
    console.log('captura:', file);
  };

  // Liga a árvore de acessibilidade do Flutter para achar botões por texto.
  const enableSemantics = async () => {
    await page.evaluate(() => {
      const p = document.querySelector('flt-semantics-placeholder');
      if (p) p.click();
    });
    await page.waitForTimeout(600);
  };

  const clickText = async (text) => {
    const loc = page.locator('flt-semantics').filter({ hasText: text }).last();
    const aria = page.locator(`[aria-label*="${text}"]`).last();
    if (await aria.count()) { await aria.click(); }
    else if (await loc.count()) { await loc.click(); }
    else { throw new Error('não achei: ' + text); }
    await page.waitForTimeout(900);
  };

  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 30000 });
  await page.waitForTimeout(2500);
  console.log('primeira tela em', Date.now() - t0, 'ms');
  await enableSemantics();

  for (const step of steps) {
    const [kind, ...rest] = step.split(':');
    const arg = rest.join(':');
    if (kind === 'shot') await shot(arg);
    else if (kind === 'click') await clickText(arg);
    else if (kind === 'tap') {
      // Toque por coordenada (em px CSS), útil para focar campos de texto.
      const [x, y] = arg.split(',').map(Number);
      await page.mouse.click(x, y);
      await page.waitForTimeout(700);
    }
    else if (kind === 'wait') await page.waitForTimeout(Number(arg));
    else if (kind === 'type') { await page.keyboard.type(arg, { delay: 5 }); await page.waitForTimeout(400); }
    else if (kind === 'paste') {
      // Cola de uma vez, como o usuário faria (\n vira quebra de linha).
      const text = arg.replace(/\\n/g, '\n');
      await page.evaluate((t) => navigator.clipboard.writeText(t), text);
      await page.keyboard.press('Control+V');
      await page.waitForTimeout(900);
    }
    else if (kind === 'press') { await page.keyboard.press(arg); await page.waitForTimeout(400); }
    else if (kind === 'scroll') { await page.mouse.move(180, 400); await page.mouse.wheel(0, Number(arg)); await page.waitForTimeout(700); }
    else if (kind === 'newtab') {
      // Toca e espera abrir uma aba nova (ex.: "Abrir PDF").
      const [popup] = await Promise.all([context.waitForEvent('page', { timeout: 10000 }), clickText(arg)]);
      await popup.waitForLoadState().catch(() => {});
      console.log('aba nova aberta:', popup.url().slice(0, 60));
      await popup.close();
    }
    else if (kind === 'download') {
      // Toca e salva o arquivo baixado: download:<texto do botão>|<arquivo>
      const [label, file] = arg.split('|');
      const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 10000 }), clickText(label)]);
      const target = path.join(outDir, file || dl.suggestedFilename());
      await dl.saveAs(target);
      console.log('baixado:', target, '(nome sugerido:', dl.suggestedFilename() + ')');
    }
    else if (kind === 'field') {
      // Foca o campo de texto pelo rótulo/dica (o input da semântica do Flutter).
      const sel = `input[aria-label*="${arg}"], textarea[aria-label*="${arg}"]`;
      const field = page.locator(sel).first();
      if (!(await field.count())) throw new Error('campo não encontrado: ' + arg);
      await field.focus();
      await page.waitForTimeout(500);
    }
    else if (kind === 'focus') {
      const info = await page.evaluate(() => {
        const a = document.activeElement;
        return a ? `${a.tagName} type=${a.getAttribute('type')} value=${JSON.stringify(a.value ?? null)} aria=${a.getAttribute('aria-label')}` : 'nenhum';
      });
      console.log('foco:', info);
      const inputs = await page.$$eval('input, textarea', (els) => els.map((e) => `${e.tagName}[${e.getAttribute('aria-label') || e.placeholder || ''}]`));
      console.log('campos no DOM:', JSON.stringify(inputs));
    }
    else if (kind === 'dump') {
      const labels = await page.$$eval('flt-semantics', (els) => els.map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim()).filter(Boolean));
      console.log('semântica:', JSON.stringify([...new Set(labels)].slice(0, 80)));
    }
  }

  console.log('erros no console:', errors.length ? errors : 'nenhum');
  console.log('pedidos externos bloqueados:', blocked.length ? blocked : 'nenhum');
  await browser.close();
})().catch((e) => { console.error('FALHOU:', e.message); process.exit(1); });
