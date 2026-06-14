/* 旅遊記帳 PWA Service Worker
 * 策略：
 *  - App Shell（本站檔案 + CDN 套件）→ 快取優先，離線也能開啟介面
 *  - Supabase API → 一律走網路（記帳資料必須即時，不快取）
 * 改版時請把 CACHE_NAME 的版本號 +1，舊快取會自動清除。
 */
const CACHE_NAME = 'travel-ledger-v11';

const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/logo.png',
  'https://cdn.tailwindcss.com',
  'https://unpkg.com/vue@3.4.27/dist/vue.global.prod.js',
  'https://unpkg.com/@supabase/supabase-js@2',
  'https://fonts.googleapis.com/icon?family=Material+Icons',
  'https://unpkg.com/xlsx@0.18.5/dist/xlsx.full.min.js',
  'https://unpkg.com/html5-qrcode@2.3.8/html5-qrcode.min.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => Promise.allSettled(APP_SHELL.map((url) => cache.add(url))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Supabase 資料 / 即時匯率 / 商品條碼查詢 API：不快取，永遠走網路
  if (url.hostname.endsWith('.supabase.co') ||
      url.hostname === 'open.er-api.com' ||
      url.hostname === 'api.open-meteo.com' ||
      url.hostname === 'ipapi.co' ||
      url.hostname.endsWith('openfoodfacts.org')) {
    return; // 交給瀏覽器預設處理
  }

  // 其餘資源：快取優先，沒有才抓網路並存入快取
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) return cached;
      return fetch(event.request).then((resp) => {
        if (event.request.method === 'GET' && resp && resp.status === 200) {
          const clone = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return resp;
      }).catch(() =>
        // 離線且無快取時，回首頁殼
        caches.match('./index.html')
      );
    })
  );
});
