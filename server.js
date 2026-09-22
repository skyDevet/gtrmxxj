import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import fetch from 'node-fetch';
import authRoutes from './server/routes/auth.js';
import pinRoutes from './server/routes/pins.js';

const app = express();
const PORT = 3001;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '50mb' }));
app.use(cookieParser());

// ---------- Existing Instagram scrapers (unchanged) ----------
function extractPostId(url) {
  const match = url.match(/\/p\/([^/?]+)/) || url.match(/\/reel\/([^/?]+)/) || url.match(/\/tv\/([^/?]+)/);
  return match ? match[1] : null;
}

async function safeParseJSON(response) {
  try {
    const text = await response.text();
    if (!text || text.trim() === '') return null;
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

function getFullResUrl(url) {
  try {
    let fullResUrl = url.replace(/\/s\d+x\d+\//, '/');
    fullResUrl = fullResUrl.replace(/&stp=dst-jpg_[^&]+/g, '');
    fullResUrl = fullResUrl.replace(/&_nc_sid=[^&]+/g, '');
    fullResUrl = fullResUrl.replace(/&ccb=[^&]+/g, '');
    if (!fullResUrl.includes('stp=')) {
      fullResUrl += '&stp=dst-jpg_e35_p1080x1080';
    }
    return fullResUrl;
  } catch {
    return url;
  }
}

async function scrapeInstagram(url) {
  try {
    const postId = extractPostId(url);
    if (!postId) return null;

    const response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache'
      }
    });

    if (response.ok) {
      const html = await response.text();
      const patterns = [
        { name: 'image_versions2', regex: /"image_versions2":\s*\[(.*?)\]/, extract: (m) => {
          try { const d = JSON.parse(`[${m[1]}]`); if (Array.isArray(d) && d.length) { d.sort((a,b)=>(b.width*b.height)-(a.width*a.height)); return d[0].url; } } catch {} return null; } },
        { name: 'display_resources', regex: /"display_resources":\s*\[(.*?)\]/, extract: (m) => {
          try { const d = JSON.parse(`[${m[1]}]`); if (Array.isArray(d) && d.length) { d.sort((a,b)=>(b.config_width*b.config_height)-(a.config_width*a.config_height)); return d[0].src; } } catch {} return null; } },
        { name: 'display_url', regex: /"display_url":"([^"]+)"/, extract: (m) => m[1].replace(/\\u0026/g, '&').replace(/\\\//g, '/') },
        { name: 'thumbnail_src', regex: /"thumbnail_src":"([^"]+)"/, extract: (m) => m[1].replace(/\\u0026/g, '&').replace(/\\\//g, '/') },
        { name: 'og:image', regex: /<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/, extract: (m) => m[1] },
        { name: 'cdn_image', regex: /https?:\/\/[^"']*cdninstagram[^"']*/, extract: (m) => m[0].replace(/\\u0026/g, '&').replace(/\\\//g, '/') }
      ];
      for (const p of patterns) {
        const m = html.match(p.regex);
        if (m) {
          try { const u = p.extract(m); if (u && u.includes('http')) return u; } catch {}
        }
      }
    }
  } catch (e) {
    console.error('Scrape error:', e.message);
  }
  return null;
}

async function fetchViaEmbed(url) {
  try {
    const postId = extractPostId(url);
    if (!postId) return null;
    const embedUrl = `https://api.instagram.com/oembed/?url=https://www.instagram.com/p/${postId}/`;
    const response = await fetch(embedUrl, { headers: { 'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json' } });
    if (response.ok) {
      const data = await safeParseJSON(response);
      if (data && data.thumbnail_url) return getFullResUrl(data.thumbnail_url);
    }
  } catch {}
  return null;
}

async function fetchViaProxy(url) {
  const postId = extractPostId(url);
  if (!postId) return null;
  const proxyUrls = [
    `https://corsproxy.io/?${encodeURIComponent(`https://www.instagram.com/p/${postId}/`)}`,
    `https://api.allorigins.win/raw?url=${encodeURIComponent(`https://www.instagram.com/p/${postId}/`)}`,
    `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(`https://www.instagram.com/p/${postId}/`)}`
  ];
  for (const proxyUrl of proxyUrls) {
    try {
      const response = await fetch(proxyUrl, { headers: { 'User-Agent': 'Mozilla/5.0', 'Accept': 'text/html,application/xhtml+xml' } });
      if (response.ok) {
        const html = await response.text();
        const patterns = [/\"display_url\":\"([^\"]+)\"/, /\"thumbnail_src\":\"([^\"]+)\"/, /<meta[^>]*property=[\"']og:image[\"'][^>]*content=[\"']([^\"']+)[\"']/, /https?:\/\/[^\"']*cdninstagram[^\"']*/];
        for (const pattern of patterns) {
          const match = html.match(pattern);
          if (match) {
            let u = match[1] || match[0];
            u = u.replace(/\\u0026/g, '&').replace(/\\\//g, '/');
            if (u.startsWith('//')) u = 'https:' + u;
            if (u.includes('http') && !u.includes('logo')) return getFullResUrl(u);
          }
        }
      }
    } catch {}
  }
  return null;
}

async function fetchImageAsBase64(imageUrl) {
  if (imageUrl.startsWith('data:')) return imageUrl;

  const fullResUrl = getFullResUrl(imageUrl);
  const attempts = [
    { name: 'Direct', fn: async () => {
      const r = await fetch(fullResUrl, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36', 'Accept': 'image/*,*/*;q=0.8', 'Referer': 'https://www.instagram.com/' } });
      if (r.ok) return r; throw new Error(`Direct ${r.status}`);
    }},
    { name: 'CORS Proxy', fn: async () => {
      const r = await fetch(`https://corsproxy.io/?${encodeURIComponent(imageUrl)}`);
      if (r.ok) return r; throw new Error('CORS proxy failed');
    }},
    { name: 'AllOrigins', fn: async () => {
      const r = await fetch(`https://api.allorigins.win/raw?url=${encodeURIComponent(imageUrl)}`);
      if (r.ok) return r; throw new Error('AllOrigins failed');
    }},
    { name: 'CodeTabs', fn: async () => {
      const r = await fetch(`https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(imageUrl)}`);
      if (r.ok) return r; throw new Error('CodeTabs failed');
    }}
  ];

  for (const attempt of attempts) {
    try {
      const r = await attempt.fn();
      if (r && r.ok) {
        const buffer = await r.buffer();
        if (buffer.length < 10000) continue;
        const base64 = buffer.toString('base64');
        const contentType = r.headers.get('content-type') || 'image/jpeg';
        return `data:${contentType};base64,${base64}`;
      }
    } catch {}
  }

  const last = await fetch(imageUrl);
  if (last.ok) {
    const buffer = await last.buffer();
    if (buffer.length > 5000) {
      const base64 = buffer.toString('base64');
      const contentType = last.headers.get('content-type') || 'image/jpeg';
      return `data:${contentType};base64,${base64}`;
    }
  }
  throw new Error('All fetch methods failed');
}

async function getInstagramImage(url) {
  const postId = extractPostId(url);
  if (!postId) throw new Error('Invalid Instagram URL');

  const methods = [
    { name: 'Scrape', fn: () => scrapeInstagram(url) },
    { name: 'Embed', fn: () => fetchViaEmbed(url) },
    { name: 'Proxy', fn: () => fetchViaProxy(url) }
  ];

  for (const m of methods) {
    try {
      const result = await m.fn();
      if (result) {
        if (result.startsWith('data:')) return result;
        return await fetchImageAsBase64(result);
      }
    } catch {}
  }

  throw new Error('Could not fetch Instagram image.');
}

app.post('/api/fetch-social-post', async (req, res) => {
  const { url, platform } = req.body;
  if (!url) return res.status(400).json({ error: 'URL is required' });

  try {
    let imageData = null;
    let title = 'Instagram Post';
    let description = 'From Instagram';

    if (platform === 'instagram') {
      imageData = await getInstagramImage(url);
    } else {
      try {
        const response = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' } });
        if (response.ok) {
          const html = await response.text();
          const ogMatch = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/);
          if (ogMatch) imageData = await fetchImageAsBase64(ogMatch[1]);
        }
      } catch {}
    }

    if (!imageData) throw new Error('No image found.');

    res.json({ success: true, image: imageData, title, description, sourceUrl: url, platform: platform || 'social' });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message || 'Failed to fetch.', suggestion: 'Try "Fetch Direct Image URL" instead.' });
  }
});

app.post('/api/fetch-image-url', async (req, res) => {
  const { imageUrl } = req.body;
  if (!imageUrl) return res.status(400).json({ error: 'Image URL is required' });
  try {
    const imageData = await fetchImageAsBase64(imageUrl);
    res.json({ success: true, image: imageData });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch image: ' + error.message });
  }
});

// ---------- New routes ----------
app.use('/api/auth', authRoutes);
app.use('/api/pins', pinRoutes);

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

app.listen(PORT, () => {
  console.log(`✅ Server running on http://localhost:${PORT}`);
});
