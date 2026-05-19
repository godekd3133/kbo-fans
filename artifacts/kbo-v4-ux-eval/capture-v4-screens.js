const fs = require('node:fs/promises');
const { spawn } = require('node:child_process');
const WebSocket = require('ws');

const chromePath = '/Users/kimminkyu/.cache/puppeteer/chrome/mac_arm-131.0.6778.204/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const outDir = '/Users/kimminkyu/Bagelcode/Repository_Bagelcode/kbo_fans/artifacts/kbo-v4-ux-eval';
const base = 'http://localhost:7357/seed-v4.html?target=';

const cases = [
  {
    name: '03-home-state.png',
    waitMs: 14000,
    actions: [],
  },
  {
    name: '01-settings-playbook.png',
    waitMs: 14000,
    actions: [
      { type: 'tap', x: 348, y: 798, waitMs: 6000 },
    ],
  },
  {
    name: '04-settings-surfaces.png',
    waitMs: 14000,
    actions: [
      { type: 'tap', x: 348, y: 798, waitMs: 6000 },
      { type: 'wheel', x: 190, y: 520, deltaY: 520, waitMs: 2000 },
    ],
  },
  {
    name: '05-settings-delivery-picker.png',
    waitMs: 14000,
    actions: [
      { type: 'tap', x: 348, y: 798, waitMs: 6000 },
      { type: 'tap', x: 306, y: 501, waitMs: 2000 },
    ],
  },
  {
    name: '02-game-detail-relay.png',
    waitMs: 14000,
    actions: [
      { type: 'tap', x: 109, y: 374, waitMs: 10000 },
    ],
  },
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForJson(port, path) {
  const url = `http://127.0.0.1:${port}${path}`;
  const started = Date.now();
  while (Date.now() - started < 15000) {
    try {
      const response = await fetch(url);
      if (response.ok) return response.json();
    } catch (_) {
      // Chrome is still starting.
    }
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${url}`);
}

function createCdp(wsUrl) {
  let id = 0;
  const pending = new Map();
  const ws = new WebSocket(wsUrl);
  ws.on('message', (raw) => {
    const message = JSON.parse(raw.toString());
    if (!message.id) return;
    const handler = pending.get(message.id);
    if (!handler) return;
    pending.delete(message.id);
    if (message.error) handler.reject(new Error(JSON.stringify(message.error)));
    else handler.resolve(message.result);
  });

  return {
    open: () => new Promise((resolve, reject) => {
      ws.once('open', resolve);
      ws.once('error', reject);
    }),
    send: (method, params = {}) => new Promise((resolve, reject) => {
      const nextId = ++id;
      pending.set(nextId, { resolve, reject });
      ws.send(JSON.stringify({ id: nextId, method, params }));
    }),
    close: () => ws.close(),
  };
}

async function capture(testCase, index) {
  const port = 9229 + index;
  const profile = `/tmp/kbo-v4-cdp-${index}-${Date.now()}`;
  const url = `${base}${encodeURIComponent('/home')}`;
  const chrome = spawn(chromePath, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-first-run',
    '--no-default-browser-check',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    '--window-size=390,844',
    url,
  ], { stdio: 'ignore' });

  try {
    const tabs = await waitForJson(port, '/json/list');
    const page = tabs.find((item) => item.type === 'page') || tabs[0];
    const cdp = createCdp(page.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 390,
      height: 844,
      deviceScaleFactor: 1,
      mobile: true,
    });
    await sleep(testCase.waitMs);
    for (const action of testCase.actions) {
      if (action.type === 'tap') {
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mousePressed',
          x: action.x,
          y: action.y,
          button: 'left',
          clickCount: 1,
        });
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mouseReleased',
          x: action.x,
          y: action.y,
          button: 'left',
          clickCount: 1,
        });
      }
      if (action.type === 'wheel') {
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mouseWheel',
          x: action.x,
          y: action.y,
          deltaX: 0,
          deltaY: action.deltaY,
        });
      }
      await sleep(action.waitMs || 1000);
    }
    const screenshot = await cdp.send('Page.captureScreenshot', {
      format: 'png',
      fromSurface: true,
      captureBeyondViewport: false,
    });
    await fs.writeFile(`${outDir}/${testCase.name}`, Buffer.from(screenshot.data, 'base64'));
    cdp.close();
  } finally {
    chrome.kill('SIGTERM');
    await sleep(500);
    await fs.rm(profile, { recursive: true, force: true }).catch(() => {});
  }
}

(async () => {
  await fs.mkdir(outDir, { recursive: true });
  for (let i = 0; i < cases.length; i += 1) {
    await capture(cases[i], i);
  }
  console.log(cases.map(({ name }) => `${outDir}/${name}`).join('\n'));
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
