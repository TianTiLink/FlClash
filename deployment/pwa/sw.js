// 云茄 PWA service worker。
// - HTML 入口(app.html):network-first —— 在线永远拿最新(支付/业务修复即时生效),离线才回退缓存。
// - 静态资源(图标/manifest):cache-first(快),只在 resp.ok 时写缓存(不缓存 5xx/错误页)。
// - API(/api/)与非 GET:一律走网络,绝不缓存(账号/订阅/支付实时)。
// 改版号即可让浏览器重装、清旧缓存。
const CACHE = 'yq-shell-v5';
const STATIC = ['/dl/manifest.webmanifest', '/dl/icon-180.png', '/dl/icon-192.png', '/dl/icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(STATIC)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

function putIfOk(req, resp) {
  if (resp && resp.ok && resp.type === 'basic') {
    const clone = resp.clone();
    caches.open(CACHE).then((c) => c.put(req, clone));
  }
  return resp;
}

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.pathname.startsWith('/api/')) return;   // API 永不缓存
  if (!url.pathname.startsWith('/dl/')) return;

  if (url.pathname.endsWith('/app.html')) {
    // 入口文档:network-first,离线回退缓存
    e.respondWith(
      fetch(e.request).then((resp) => putIfOk(e.request, resp))
        .catch(() => caches.match(e.request).then((r) => r || caches.match('/dl/app.html')))
    );
  } else {
    // 静态资源:cache-first
    e.respondWith(
      caches.match(e.request).then((hit) => hit || fetch(e.request).then((resp) => putIfOk(e.request, resp)))
    );
  }
});
