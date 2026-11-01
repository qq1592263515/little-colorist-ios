import { createServer } from "node:http";
import { createRequire } from "node:module";
import { readFile, stat } from "node:fs/promises";
import { dirname, extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputDirectory = join(root, "AppStore", "Screenshots");
const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const playwrightPath =
  process.env.PLAYWRIGHT_CORE_PATH ??
  "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/playwright-core";
const { chromium } = require(playwrightPath);

const mimeTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml"
};

const server = createServer(async (request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
  const relativePath = normalize(pathname).replace(/^([/\\])+/, "");
  const filePath = resolve(root, relativePath);

  if (!filePath.startsWith(`${root}/`)) {
    response.writeHead(403).end();
    return;
  }

  try {
    const fileInfo = await stat(filePath);
    if (!fileInfo.isFile()) throw new Error("Not a file");
    const body = await readFile(filePath);
    response.writeHead(200, {
      "Content-Type": mimeTypes[extname(filePath)] ?? "application/octet-stream"
    });
    response.end(body);
  } catch {
    response.writeHead(404).end("Not found");
  }
});

await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();

const captures = [
  ["macOS-01-画册首页", 1440, 900, 2, "home"],
  ["macOS-02-自由涂色", 1440, 900, 2, "paint"],
  ["macOS-03-照样闯关", 1440, 900, 2, "match"],
  ["iPhone-6.9-01-画册首页", 440, 956, 3, "home"],
  ["iPhone-6.9-02-自由涂色", 440, 956, 3, "paint"],
  ["iPhone-6.9-03-照样闯关", 440, 956, 3, "match"],
  ["iPhone-6.5-01-画册首页", 414, 896, 3, "home"],
  ["iPhone-6.5-02-自由涂色", 414, 896, 3, "paint"],
  ["iPhone-6.5-03-照样闯关", 414, 896, 3, "match"],
  ["iPad-13-01-画册首页", 1032, 1376, 2, "home"],
  ["iPad-13-02-自由涂色", 1032, 1376, 2, "paint"],
  ["iPad-12.9-01-画册首页", 1024, 1366, 2, "home"],
  ["iPad-12.9-02-自由涂色", 1024, 1366, 2, "paint"]
];

const browser = await chromium.launch({ executablePath: chromePath, headless: true });

try {
  for (const [name, width, height, scale, screen] of captures) {
    const context = await browser.newContext({
      viewport: { width, height },
      deviceScaleFactor: scale
    });
    const page = await context.newPage();
    await page.goto(`http://127.0.0.1:${port}/scripts/screenshot-harness.html?screen=${screen}`);
    await page.waitForTimeout(1400);
    await page.screenshot({ path: join(outputDirectory, `${name}.png`) });
    await context.close();
    console.log(`${name}: ${width * scale}x${height * scale}`);
  }
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
