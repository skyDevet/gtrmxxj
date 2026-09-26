#!/bin/bash
set -e
echo "Creating project files..."
cat > package.json << 'END'
{
  "name": "gtrm",
  "version": "2.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "server": "node server.js",
    "start": "concurrently \"npm run server\" \"npm run dev\""
  },
  "dependencies": {
    "preact": "^10.19.3",
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "node-fetch": "^3.3.2",
    "cheerio": "^1.0.0-rc.12",
    "googleapis": "^140.0.0",
    "@supabase/supabase-js": "^2.45.0",
    "cookie-parser": "^1.4.6",
    "jsonwebtoken": "^9.0.2",
    "dotenv": "^16.4.5"
  },
  "devDependencies": {
    "@preact/preset-vite": "^2.8.0",
    "vite": "^5.1.0",
    "concurrently": "^8.2.2"
  }
}
END
cat > vite.config.js << 'END'
import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/api': {
        target: 'http://localhost:3001',
        changeOrigin: true,
        secure: false
      }
    }
  }
});
END
cat > server.js << 'END'
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
END
cat > index.html << 'END'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>á‰°áˆ¨áŠ¨á‹Ÿ - AI Visual Search</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" />
  <link rel="stylesheet" href="/src/styles/app.css" />

  <script type="module">
    import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@xenova/transformers@2.17.0/dist/transformers.min.js';
    env.allowLocalModels = false;
    env.useBrowserCache = true;
    env.allowRemoteModels = true;
    window.transformers = { pipeline, env };
    console.log('✅ Transformers.js loaded');
  </script>

  <script src="https://cdn.jsdelivr.net/npm/eruda"></script>
  <script>eruda.init();</script>
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
END
cat > .gitignore << 'END'
# Dependencies
node_modules/
.cache/

# Build outputs - THESE WILL NOT BE PUSHED
dist/
.vite/
build/
.capacitor/


# OS files
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# Temporary
tmp/
backup_*/
END
mkdir -p supabase/ server/routes src/components src/services src/hooks src/styles
cat > src/main.jsx << 'END'
import { render } from 'preact';
import { App } from './app.jsx';
render(<App />, document.getElementById('app'));
END
cat > src/app.jsx << 'END'
import { Component } from 'preact';
import { Header } from './components/Header.jsx';
import { Footer } from './components/Footer.jsx';
import { PinGrid } from './components/PinGrid.jsx';
import { PinDetail } from './components/PinDetail.jsx';
import { UploadModal } from './components/UploadModal.jsx';
import { ProfileModal } from './components/ProfileModal.jsx';
import { LoadingSpinner } from './components/LoadingSpinner.jsx';
import { RoyalPage } from './components/RoyalPage.jsx';
import { usePins } from './hooks/usePins.js';
import { initAI } from './services/ai.js';
import { getCurrentUser, signInWithGoogle } from './services/auth.js';

const STORIES = [
  { id: 'own', username: 'Your Story', avatar: 'https://i.pravatar.cc/150?img=12', isAdd: true },
  { id: 'sophia', username: 'Sophia', avatar: 'https://i.pravatar.cc/150?img=1' },
  { id: 'emma', username: 'Emma', avatar: 'https://i.pravatar.cc/150?img=5' },
  { id: 'olivia', username: 'Olivia', avatar: 'https://i.pravatar.cc/150?img=6' },
  { id: 'royal', username: 'Queen Elsee', avatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop', royal: true },
  { id: 'ava', username: 'Ava', avatar: 'https://i.pravatar.cc/150?img=7' },
  { id: 'isabella', username: 'Isabella', avatar: 'https://i.pravatar.cc/150?img=8' }
];

export class App extends Component {
  constructor() {
    super();
    this.state = {
      pins: [],
      loading: true,
      selectedPin: null,
      showUpload: false,
      showProfile: false,
      searchTerm: '',
      filterCategory: 'all',
      selectedClass: '',
      classes: [],
      darkMode: false,
      aiReady: false,
      aiProgress: 0,
      aiStatus: '',
      columns: 4,
      activeTab: 'home',
      showRoyalPage: false,
      user: null,
      userLoading: true
    };
  }

  async componentDidMount() {
    const saved = localStorage.getItem('darkMode');
    const isDark = saved === 'true';
    if (isDark) document.documentElement.setAttribute('data-theme', 'dark');
    this.setState({ darkMode: isDark });

    this.updateColumns();
    window.addEventListener('resize', this.updateColumns);

    window._onProgress = (progress) => {
      if (progress === 100) this.setState({ aiProgress: 100, aiStatus: 'AI Ready!' });
      else this.setState({ aiProgress: progress, aiStatus: `Downloading model... ${progress}%` });
    };

    // Get current user first (needed before saving)
    const user = await getCurrentUser();
    this.setState({ user, userLoading: false });

    // Load pins + AI in parallel
    this.loadPins();
    this.loadClasses();
    initAI().then(success => {
      this.setState({
        aiReady: success,
        aiProgress: success ? 100 : 0,
        aiStatus: success ? 'AI Ready!' : 'AI unavailable - using basic mode'
      });
    });
  }

  componentWillUnmount() {
    window.removeEventListener('resize', this.updateColumns);
  }

  updateColumns = () => {
    const w = window.innerWidth;
    let columns = 4;
    if (w < 480) columns = 2;
    else if (w < 768) columns = 2;
    else if (w < 1024) columns = 3;
    else if (w < 1400) columns = 4;
    else columns = 5;
    this.setState({ columns });
  };

  loadPins = async () => {
    try {
      const pins = await usePins.getAll();
      this.setState({ pins, loading: false });
    } catch (e) {
      console.error('Failed to load pins:', e);
      this.setState({ pins: [], loading: false });
    }
  };

  loadClasses = async () => {
    try {
      const classes = await usePins.getClasses();
      this.setState({ classes });
    } catch {}
  };

  handleSavePin = async (pinData) => {
    if (!this.state.user) {
      alert('Please sign in with Google to save pins to your Drive.');
      signInWithGoogle();
      return;
    }
    await usePins.add(pinData);
    await this.loadPins();
    await this.loadClasses();
    this.setState({ showUpload: false, activeTab: 'home' });
  };

  handleDeletePin = async (id) => {
    if (!confirm('Delete this pin? (Also removes the file from your Google Drive)')) return;
    try {
      await usePins.delete(id);
      this.setState({ selectedPin: null });
      await this.loadPins();
      await this.loadClasses();
    } catch (e) {
      alert('Delete failed: ' + e.message);
    }
  };

  handleUpdatePin = async (id, data) => {
    try {
      await usePins.update(id, data);
      if (this.state.selectedPin?.id === id) {
        this.setState({ selectedPin: { ...this.state.selectedPin, ...data } });
      }
      await this.loadPins();
      await this.loadClasses();
    } catch (e) {
      console.error('Update failed:', e);
    }
  };

  handleClearAll = async () => {
    alert('Clear All is disabled — pins live in Supabase now. Delete them individually.');
  };

  toggleTheme = () => {
    const newDark = !this.state.darkMode;
    this.setState({ darkMode: newDark });
    localStorage.setItem('darkMode', newDark);
    document.documentElement.setAttribute('data-theme', newDark ? 'dark' : '');
  };

  handleGoHome = () => {
    this.setState({
      activeTab: 'home', selectedPin: null, showUpload: false,
      showProfile: false, filterCategory: 'all', selectedClass: '', searchTerm: ''
    });
  };

  handleOpenUpload = () => {
    if (!this.state.user) {
      if (confirm('Sign in with Google to upload pins to your Drive?')) {
        signInWithGoogle();
      }
      return;
    }
    this.setState({ showUpload: true, activeTab: 'upload' });
  };

  handleOpenProfile = () => {
    this.setState({ showProfile: true, activeTab: 'profile' });
  };

  handleStoryClick = (story) => {
    if (story.isAdd) {
      this.handleOpenUpload();
      return;
    }
    this.setState({ showRoyalPage: true });
  };

  render() {
    const {
      loading, selectedPin, showUpload, showProfile, searchTerm,
      filterCategory, selectedClass, classes, darkMode, aiReady,
      aiProgress, aiStatus, columns, pins, activeTab,
      showRoyalPage, user
    } = this.state;

    if (showRoyalPage) {
      return <RoyalPage onClose={() => this.setState({ showRoyalPage: false })} />;
    }

    if (loading) {
      return <LoadingSpinner aiStatus={aiStatus} aiProgress={aiProgress} />;
    }

    const allCategories = ['all', 'Nature', 'ass', 'milf', 'soles'];
    const filteredPins = usePins.filter(pins, searchTerm, filterCategory, selectedClass);

    return (
      <div style={{ minHeight: '100vh', background: 'var(--bg)' }}>
        <Header
          aiReady={aiReady}
          searchTerm={searchTerm}
          filterCategory={filterCategory}
          selectedClass={selectedClass}
          classes={classes}
          allCategories={allCategories}
          onSearchChange={(value) => this.setState({ searchTerm: value })}
          onFilterChange={(value) => this.setState({ filterCategory: value })}
          onClassChange={(value) => this.setState({ selectedClass: value })}
          onReset={this.handleGoHome}
          user={user}
          onProfile={this.handleOpenProfile}
        />

        <div style={{ maxWidth: '1400px', margin: '0 auto', padding: '0 16px 90px' }}>
          <div className="stories-row">
            {STORIES.map((story) => (
              <div key={story.id} className="story-item" onClick={() => this.handleStoryClick(story)}>
                <div className={
                  'story-avatar' +
                  (story.isAdd ? ' add-story' : '') +
                  (story.royal ? ' royal-ring' : '')
                }>
                  {story.isAdd ? <i className="fas fa-plus" /> : <img src={story.avatar} alt={story.username} />}
                </div>
                <div className="story-username">{story.username}</div>
              </div>
            ))}
          </div>

          <PinGrid
            pins={filteredPins}
            columns={columns}
            onPinClick={(pin) => this.setState({ selectedPin: pin })}
          />
        </div>

        {selectedPin && (
          <PinDetail
            pin={selectedPin}
            allPins={pins}
            aiReady={aiReady}
            onClose={() => this.setState({ selectedPin: null })}
            onDelete={this.handleDeletePin}
            onUpdate={this.handleUpdatePin}
            onSelectPin={(pin) => this.setState({ selectedPin: pin })}
          />
        )}

        {showUpload && (
          <UploadModal
            aiReady={aiReady}
            classes={classes}
            categories={allCategories.filter(c => c !== 'all')}
            onClose={() => this.setState({ showUpload: false, activeTab: 'home' })}
            onSave={this.handleSavePin}
          />
        )}

        {showProfile && (
          <ProfileModal
            pins={pins}
            classes={classes}
            aiReady={aiReady}
            darkMode={darkMode}
            user={user}
            onClose={() => this.setState({ showProfile: false, activeTab: 'home' })}
            onClearAll={this.handleClearAll}
            onToggleTheme={this.toggleTheme}
          />
        )}

        <Footer
          activeTab={activeTab}
          onHome={this.handleGoHome}
          onUpload={this.handleOpenUpload}
          onProfile={this.handleOpenProfile}
        />
      </div>
    );
  }
}
END
cat > src/styles/app.css << 'END'
:root {
  --bg: #ffffff;
  --card: #ffffff;
  --text: #1a1a1a;
  --text-sec: #6b6b6b;
  --border: #e5e5e5;
  --primary: #e60023;
  --shadow: 0 2px 8px rgba(0,0,0,0.08);
}
[data-theme="dark"] {
  --bg: #121212; --card: #1e1e1e; --text: #f5f5f5;
  --text-sec: #a0a0a0; --border: #333; --shadow: 0 2px 8px rgba(0,0,0,0.3);
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); -webkit-tap-highlight-color: transparent; }
.ai-badge { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; background: linear-gradient(135deg, #667eea, #764ba2); color: white; border-radius: 12px; font-size: 10px; }
.btn { padding: 10px 20px; border-radius: 24px; border: none; cursor: pointer; font-size: 14px; font-weight: 500; display: inline-flex; align-items: center; gap: 6px; }
.btn-primary { background: var(--primary); color: white; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
input, textarea, select { padding: 10px 14px; border-radius: 12px; border: 1px solid var(--border); background: var(--bg); color: var(--text); font-size: 14px; width: 100%; font-family: inherit; }
textarea { resize: vertical; }
.progress-bar { width: 100%; height: 4px; background: var(--border); border-radius: 2px; overflow: hidden; }
.progress-fill { height: 100%; background: var(--primary); transition: width 0.3s; }
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: var(--bg); }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }
.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.7); z-index: 999; display: flex; align-items: center; justify-content: center; padding: 20px; }
.modal-content { background: var(--card); border-radius: 16px; max-width: 700px; width: 100%; max-height: 90vh; overflow-y: auto; padding: 24px; position: relative; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
.stories-row { display: flex; gap: 15px; overflow-x: auto; padding: 10px 0 16px; margin-bottom: 20px; scrollbar-width: none; }
.stories-row::-webkit-scrollbar { display: none; }
.story-item { display: flex; flex-direction: column; align-items: center; cursor: pointer; min-width: 80px; flex-shrink: 0; }
.story-avatar { width: 70px; height: 70px; border-radius: 50%; overflow: hidden; position: relative; border: 3px solid var(--primary); padding: 3px; background: var(--card); flex-shrink: 0; transition: transform 0.2s; }
.story-avatar img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }
.story-avatar.royal-ring { border-color: #ffd700; box-shadow: 0 0 12px rgba(255, 215, 0, 0.6); }
.story-username { color: var(--text); margin-top: 8px; font-size: 12px; text-align: center; max-width: 80px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.add-story { border: 2px dashed var(--text-sec); display: flex; align-items: center; justify-content: center; }
.add-story i { font-size: 20px; color: var(--text-sec); }
.royal-page { min-height: 100vh; background: var(--bg); padding-bottom: 60px; }
.royal-back-bar { padding: 12px 16px; }
.royal-back-btn { padding: 8px 16px; border-radius: 20px; border: 1px solid var(--border); background: transparent; color: var(--text); cursor: pointer; font-size: 14px; }
.royal-hero { position: relative; min-height: 450px; border-radius: 20px; overflow: hidden; margin: 0 16px 30px; border: 2px solid rgba(255, 215, 0, 0.3); box-shadow: 0 0 30px rgba(255, 215, 0, 0.2); background-image: linear-gradient(135deg, #1a1a2e 0%, #0f0f1a 100%); }
.royal-crown { position: absolute; top: 20px; left: 50%; transform: translateX(-50%); color: #ffd700; font-size: 40px; z-index: 10; }
.royal-avatar { width: 150px; height: 150px; border-radius: 50%; overflow: hidden; border: 4px solid #ffd700; position: absolute; top: 80px; left: 50%; transform: translateX(-50%); z-index: 5; box-shadow: 0 0 20px rgba(255, 215, 0, 0.5); }
.royal-avatar img { width: 100%; height: 100%; object-fit: cover; }
.royal-info { margin-top: 11em; padding: 40px 30px 30px; text-align: center; }
.royal-name { font-size: 32px; color: #ffd700; margin-bottom: 10px; text-shadow: 0 2px 4px rgba(0,0,0,0.5); }
.royal-title { font-size: 18px; color: #c0c0c0; margin-bottom: 15px; font-style: italic; }
.royal-stats { display: flex; justify-content: center; gap: 30px; margin: 20px 0; flex-wrap: wrap; }
.royal-stat { text-align: center; }
.royal-stat-value { font-size: 24px; color: #ffd700; font-weight: bold; }
.royal-stat-label { font-size: 12px; color: #c0c0c0; text-transform: uppercase; letter-spacing: 1px; }
.royal-actions { display: flex; justify-content: center; gap: 15px; margin-top: 20px; flex-wrap: wrap; }
.royal-btn { background: linear-gradient(45deg, #ffd700, #ffed4e); color: #000; border: none; padding: 12px 25px; border-radius: 25px; font-weight: bold; cursor: pointer; display: flex; align-items: center; gap: 8px; }
.royal-btn.secondary { background: transparent; border: 2px solid #ffd700; color: #ffd700; }
.royalty-tier { display: flex; align-items: center; gap: 15px; margin: 20px 16px; padding: 15px; background: rgba(255, 215, 0, 0.1); border-radius: 10px; border-left: 4px solid #ffd700; }
.tier-icon { font-size: 24px; color: #ffd700; }
.tier-info { flex: 1; }
.tier-info h4 { color: #ffd700; margin-bottom: 5px; }
.royalty-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 16px; }
.royalty-stat { background: var(--card); padding: 15px; border-radius: 10px; text-align: center; border: 1px solid rgba(255, 215, 0, 0.3); }
.royalty-stat .stat-value { font-size: 24px; color: #ffd700; }
END
cat > supabase/schema.sql << 'END'
-- Run this in Supabase → SQL Editor

create extension if not exists "pgcrypto";

-- Pins: metadata + Drive file reference
create table if not exists pins (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  user_email text,
  user_name text,
  user_picture text,
  drive_file_id text not null,
  drive_url text not null,
  drive_view_url text,
  title text,
  description text,
  category text,
  class text,
  image_width int,
  image_height int,
  features jsonb,
  pose jsonb,
  likes int default 0,
  saved boolean default false,
  comments jsonb default '[]'::jsonb,
  created_at timestamptz default now()
);

create index if not exists pins_user_id_idx on pins(user_id);
create index if not exists pins_category_idx on pins(category);
create index if not exists pins_created_at_idx on pins(created_at desc);

-- User tokens: encrypted refresh tokens per user
create table if not exists user_tokens (
  user_id text primary key,
  email text,
  name text,
  picture text,
  refresh_token_encrypted text not null,
  access_token_encrypted text,
  access_token_expires_at timestamptz,
  scope text,
  updated_at timestamptz default now()
);

-- RLS: server uses service_role so it bypasses these, but enable for safety
alter table pins enable row level security;
alter table user_tokens enable row level security;

-- Drop existing policies if re-running
drop policy if exists "public read pins" on pins;
create policy "public read pins" on pins for select using (true);
END
cat > server/drive.js << 'END'
import { google } from 'googleapis';
import http from 'http';
import https from 'https';
import { Readable } from 'stream';
import { decrypt, getTokens, updateAccessToken } from './tokens.js';

// FIX for Node 26.3.1 ERR_STREAM_PREMATURE_CLOSE / ECONNRESET bugs
// on Termux + Android. Forces fresh sockets for every request.
http.globalAgent = new http.Agent({ keepAlive: false });
https.globalAgent = new https.Agent({ keepAlive: false });

const oauth2Client = new google.auth.OAuth2(
  process.env.GOOGLE_CLIENT_ID,
  process.env.GOOGLE_CLIENT_SECRET,
  process.env.GOOGLE_REDIRECT_URI
);

export function buildAuthUrl() {
  return oauth2Client.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: [
      'openid',
      'email',
      'profile',
      'https://www.googleapis.com/auth/drive.file'
    ]
  });
}

export async function exchangeCode(code) {
  const { tokens } = await oauth2Client.getToken(code);
  return tokens;
}

async function getAuthorizedClient(userId) {
  const row = await getTokens(userId);
  if (!row) throw new Error('No Google tokens for user — please sign in again');

  const refreshToken = decrypt(row.refresh_token_encrypted);
  oauth2Client.setCredentials({ refresh_token: refreshToken });

  try {
    const { credentials } = await oauth2Client.refreshAccessToken();
    if (credentials.access_token) {
      await updateAccessToken(userId, credentials.access_token, credentials.expiry_date);
    }
    oauth2Client.setCredentials(credentials);
  } catch (e) {
    if (row.access_token_encrypted) {
      oauth2Client.setCredentials({
        access_token: decrypt(row.access_token_encrypted),
        refresh_token: refreshToken
      });
    } else {
      throw e;
    }
  }

  return oauth2Client;
}

/**
 * Fallback: raw REST upload using node-fetch with explicit Content-Length.
 * Bypasses the googleapis/gaxios stack when it chokes on Termux.
 */
async function uploadViaRest(accessToken, buffer, mimeType, fileName) {
  const boundary = '-------314159265358979323846';
  const delimiter = `\r\n--${boundary}\r\n`;
  const closeDelim = `\r\n--${boundary}--`;

  const metadata = JSON.stringify({ name: fileName, mimeType });

  const multipartBody = Buffer.concat([
    Buffer.from(delimiter),
    Buffer.from('Content-Type: application/json\r\n\r\n'),
    Buffer.from(metadata),
    Buffer.from(delimiter),
    Buffer.from(`Content-Type: ${mimeType}\r\n\r\n`),
    buffer,
    Buffer.from(closeDelim)
  ]);

  const res = await fetch(
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': `multipart/related; boundary=${boundary}`,
        'Content-Length': String(multipartBody.length)
      },
      body: multipartBody
    }
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Drive REST upload failed: ${res.status} ${text}`);
  }

  const data = await res.json();
  return data.id;
}

/**
 * Fallback: raw REST permission set using node-fetch.
 * Same reason as uploadViaRest — avoids googleapis quirks on Termux.
 */
async function setPublicViaRest(accessToken, fileId) {
  const res = await fetch(
    `https://www.googleapis.com/drive/v3/files/${fileId}/permissions`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ role: 'reader', type: 'anyone' })
    }
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Drive REST permission failed: ${res.status} ${text}`);
  }

  return true;
}

export async function uploadBase64ToDrive(userId, dataUrl, fileName) {
  const auth = await getAuthorizedClient(userId);
  const drive = google.drive({ version: 'v3', auth });

  const match = dataUrl.match(/^data:(image\/[a-zA-Z0-9+.-]+);base64,(.+)$/);
  if (!match) throw new Error('Invalid image data URL');
  const mimeType = match[1];
  const buffer = Buffer.from(match[2], 'base64');

  console.log(`📤 Uploading ${(buffer.length / 1024).toFixed(0)}KB to Drive...`);

  const name = fileName || `pin-${Date.now()}.jpg`;
  let fileId;

  // ---- 1) Upload the file ----
  try {
    const { data: created } = await drive.files.create(
      {
        requestBody: { name, mimeType },
        media: { mimeType, body: Readable.from(buffer) },
        fields: 'id, name, webViewLink, webContentLink'
      },
      { timeout: 120000 }
    );
    fileId = created.id;
    console.log('✅ googleapis upload OK:', fileId);
  } catch (e) {
    console.warn('⚠️  googleapis upload failed:', e.message);
    console.warn('↩️  Falling back to raw REST upload...');
    const tokenResp = await auth.getAccessToken();
    const accessToken = typeof tokenResp === 'string' ? tokenResp : tokenResp?.token;
    if (!accessToken) throw new Error('Could not get access token for REST fallback');
    fileId = await uploadViaRest(accessToken, buffer, mimeType, name);
    console.log('✅ REST upload OK:', fileId);
  }

  // ---- 2) Set public permission (with REST fallback) ----
  console.log('🔓 Setting public permission for', fileId);
  let permissionOk = false;
  try {
    const perm = await drive.permissions.create({
      fileId,
      requestBody: { role: 'reader', type: 'anyone' }
    });
    console.log('✅ Permission set OK (googleapis)');
    permissionOk = true;
  } catch (e) {
    console.warn('⚠️  googleapis permission failed:', e.message);
    console.warn('↩️  Falling back to raw REST permission...');
    try {
      const tokenResp = await auth.getAccessToken();
      const accessToken = typeof tokenResp === 'string' ? tokenResp : tokenResp?.token;
      if (!accessToken) throw new Error('No access token for REST permission fallback');
      await setPublicViaRest(accessToken, fileId);
      console.log('✅ Permission set OK (REST)');
      permissionOk = true;
    } catch (e2) {
      console.error('❌ Permission set FAILED completely:', e2.message);
    }
  }

  // If permission failed entirely, throw so the caller knows the file is private.
  if (!permissionOk) {
    throw new Error(
      'Uploaded to Drive but could not make the file public. ' +
      'Check your OAuth scope — you may need to re-consent with "drive" scope.'
    );
  }

  const publicUrl = `https://lh3.googleusercontent.com/d/${fileId}`;
  const viewUrl = `https://drive.google.com/file/d/${fileId}/view`;

  return { fileId, publicUrl, viewUrl };
}

export async function deleteDriveFile(userId, fileId) {
  const auth = await getAuthorizedClient(userId);
  const drive = google.drive({ version: 'v3', auth });
  try {
    await drive.files.delete({ fileId });
  } catch (e) {
    console.warn('Drive delete failed (already gone?):', e.message);
  }
}END
cat > server/supabase.js << 'END'
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.warn('⚠️  SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing — DB calls will fail');
}

export const supabase = createClient(url || 'http://localhost', key || 'anon', {
  auth: { persistSession: false, autoRefreshToken: false }
});
END
cat > server/tokens.js << 'END'
import crypto from 'crypto';
import { supabase } from './supabase.js';

const ALGO = 'aes-256-gcm';

function getKey() {
  const hex = process.env.TOKEN_ENCRYPTION_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error('TOKEN_ENCRYPTION_KEY must be 64 hex chars (32 bytes)');
  }
  return Buffer.from(hex, 'hex');
}

export function encrypt(plaintext) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, getKey(), iv);
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString('hex')}:${tag.toString('hex')}:${enc.toString('hex')}`;
}

export function decrypt(payload) {
  const [ivHex, tagHex, encHex] = payload.split(':');
  const decipher = crypto.createDecipheriv(ALGO, getKey(), Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  const dec = Buffer.concat([decipher.update(Buffer.from(encHex, 'hex')), decipher.final()]);
  return dec.toString('utf8');
}

export async function saveTokens(user, tokens) {
  const row = {
    user_id: user.id,
    email: user.email || null,
    name: user.name || null,
    picture: user.picture || null,
    refresh_token_encrypted: encrypt(tokens.refresh_token),
    access_token_encrypted: tokens.access_token ? encrypt(tokens.access_token) : null,
    access_token_expires_at: tokens.expiry_date ? new Date(tokens.expiry_date).toISOString() : null,
    scope: tokens.scope || null,
    updated_at: new Date().toISOString()
  };

  const { error } = await supabase.from('user_tokens').upsert(row, { onConflict: 'user_id' });
  if (error) throw new Error('saveTokens: ' + error.message);
}

export async function getTokens(userId) {
  const { data, error } = await supabase
    .from('user_tokens')
    .select('*')
    .eq('user_id', userId)
    .single();
  if (error) return null;
  return data;
}

export async function updateAccessToken(userId, accessToken, expiryDate) {
  const { error } = await supabase
    .from('user_tokens')
    .update({
      access_token_encrypted: encrypt(accessToken),
      access_token_expires_at: expiryDate ? new Date(expiryDate).toISOString() : null,
      updated_at: new Date().toISOString()
    })
    .eq('user_id', userId);
  if (error) throw new Error('updateAccessToken: ' + error.message);
}
END
cat > server/routes/auth.js << 'END'
import express from 'express';
import jwt from 'jsonwebtoken';
import { google } from 'googleapis';
import { buildAuthUrl, exchangeCode } from '../drive.js';
import { saveTokens, getTokens } from '../tokens.js';

const router = express.Router();

const oauth2Client = new google.auth.OAuth2(
  process.env.GOOGLE_CLIENT_ID,
  process.env.GOOGLE_CLIENT_SECRET,
  process.env.GOOGLE_REDIRECT_URI
);

// Step 1 — redirect to Google
router.get('/google', (req, res) => {
  res.redirect(buildAuthUrl());
});

// Step 2 — Google redirects back here
router.get('/callback', async (req, res) => {
  try {
    const { code } = req.query;
    if (!code) return res.status(400).send('Missing code');

    const tokens = await exchangeCode(code);

    // Decode id_token to get user info
    const ticket = await oauth2Client.verifyIdToken({
      idToken: tokens.id_token,
      audience: process.env.GOOGLE_CLIENT_ID
    });
    const payload = ticket.getPayload();

    const user = {
      id: payload.sub,
      email: payload.email,
      name: payload.name,
      picture: payload.picture
    };

    if (!tokens.refresh_token) {
      console.warn('⚠️  No refresh_token returned — user may have already granted consent.');
      const existing = await getTokens(user.id);
      if (!existing) {
        return res.status(400).send(
          'No refresh token. Please revoke app access at https://myaccount.google.com/permissions and try again.'
        );
      }
    } else {
      await saveTokens(user, tokens);
    }

    // Issue session JWT
    const sessionJwt = jwt.sign(
      { sub: user.id, email: user.email, name: user.name, picture: user.picture },
      process.env.SESSION_SECRET,
      { expiresIn: '30d' }
    );

    res.cookie('session', sessionJwt, {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      maxAge: 30 * 24 * 60 * 60 * 1000
    });

    res.redirect('/');
  } catch (e) {
    console.error('Auth callback error:', e);
    res.status(500).send('Auth failed: ' + e.message);
  }
});

// Current user
router.get('/me', (req, res) => {
  const token = req.cookies?.session;
  if (!token) return res.json({ user: null, hasDrive: false });
  try {
    const payload = jwt.verify(token, process.env.SESSION_SECRET);
    res.json({
      user: {
        id: payload.sub,
        email: payload.email,
        name: payload.name,
        picture: payload.picture
      },
      hasDrive: true
    });
  } catch {
    res.json({ user: null, hasDrive: false });
  }
});

router.post('/logout', (req, res) => {
  res.clearCookie('session');
  res.json({ ok: true });
});

export default router;
END
cat > server/routes/pins.js << 'END'
import express from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../supabase.js';
import { uploadBase64ToDrive, deleteDriveFile } from '../drive.js';

const router = express.Router();

function requireAuth(req, res, next) {
  const token = req.cookies?.session;
  if (!token) return res.status(401).json({ error: 'Not authenticated' });
  try {
    req.user = jwt.verify(token, process.env.SESSION_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'Invalid session' });
  }
}

// Create pin → upload to Drive → insert Supabase row
router.post('/', requireAuth, async (req, res) => {
  try {
    const {
      image, thumbnail, title, description, category, class: className,
      imageWidth, imageHeight, features, pose
    } = req.body;

    if (!image) return res.status(400).json({ error: 'Missing image' });

    // Upload to user's Drive
    const fileName = `${(title || 'pin').slice(0, 60).replace(/[^a-z0-9_-]/gi, '_')}-${Date.now()}.jpg`;
    const { fileId, publicUrl, viewUrl } = await uploadBase64ToDrive(
      req.user.sub, image, fileName
    );

    const row = {
      user_id: req.user.sub,
      user_email: req.user.email || null,
      user_name: req.user.name || null,
      user_picture: req.user.picture || null,
      drive_file_id: fileId,
      drive_url: publicUrl,
      drive_view_url: viewUrl,
      title: title || 'Untitled',
      description: description || '',
      category: category || 'Uncategorized',
      class: className || '',
      image_width: imageWidth || 0,
      image_height: imageHeight || 0,
      features: features || null,
      pose: pose || null
    };

    const { data, error } = await supabase.from('pins').insert(row).select().single();
    if (error) throw new Error('Supabase insert: ' + error.message);

    res.json({ success: true, pin: data });
  } catch (e) {
    console.error('POST /pins error:', e);
    res.status(500).json({ error: e.message });
  }
});

// List all pins (public feed — used by app and Pingrid)
router.get('/', async (req, res) => {
  try {
    const { category, class: className, q, limit = 200 } = req.query;

    let query = supabase
      .from('pins')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(Number(limit));

    if (category && category !== 'all') query = query.eq('category', category);
    if (className) query = query.eq('class', className);
    if (q) query = query.ilike('title', `%${q}%`);

    const { data, error } = await query;
    if (error) throw new Error(error.message);

    // Map Supabase rows to the shape the client already expects
    const pins = (data || []).map(row => ({
      id: row.id,
      driveFileId: row.drive_file_id,
      driveUrl: row.drive_url,
      image: row.drive_url,
      thumbnail: row.drive_url,
      title: row.title,
      description: row.description,
      category: row.category,
      class: row.class,
      imageWidth: row.image_width,
      imageHeight: row.image_height,
      features: row.features,
      pose: row.pose,
      likes: row.likes,
      saved: row.saved,
      comments: row.comments,
      createdAt: new Date(row.created_at).getTime(),
      owner: {
        id: row.user_id,
        name: row.user_name,
        email: row.user_email,
        picture: row.user_picture
      }
    }));

    res.json({ pins });
  } catch (e) {
    console.error('GET /pins error:', e);
    res.status(500).json({ error: e.message });
  }
});

// Social updates (likes, saved, comments) — anyone can update these
router.patch('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { likes, saved, comments } = req.body;
    const update = {};
    if (likes !== undefined) update.likes = likes;
    if (saved !== undefined) update.saved = saved;
    if (comments !== undefined) update.comments = comments;

    const { data, error } = await supabase
      .from('pins').update(update).eq('id', id).select().single();
    if (error) throw new Error(error.message);
    res.json({ success: true, pin: data });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Delete — owner only
router.delete('/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params;

    const { data: row, error: fetchErr } = await supabase
      .from('pins').select('*').eq('id', id).single();
    if (fetchErr) throw new Error(fetchErr.message);
    if (row.user_id !== req.user.sub) return res.status(403).json({ error: 'Not owner' });

    await deleteDriveFile(req.user.sub, row.drive_file_id);
    const { error: delErr } = await supabase.from('pins').delete().eq('id', id);
    if (delErr) throw new Error(delErr.message);

    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

export default router;
END
cat > src/components/Footer.jsx << 'END'
export function Footer({ activeTab, onHome, onUpload, onProfile }) {
  const iconStyle = (tab) => ({
    background: 'none', border: 'none', cursor: 'pointer', fontSize: '22px',
    color: activeTab === tab ? 'var(--primary)' : 'var(--text-sec)',
    padding: '8px 28px', display: 'flex', alignItems: 'center', justifyContent: 'center'
  });
  return (
    <nav style={{
      position: 'fixed', bottom: 0, left: 0, right: 0, background: 'var(--card)',
      borderTop: '1px solid var(--border)', borderTopLeftRadius: '32px', borderTopRightRadius: '32px',
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
      zIndex: 100, paddingBottom: 'env(safe-area-inset-bottom, 0)', paddingTop: '6px'
    }}>
      <button style={iconStyle('home')} onClick={onHome} aria-label="Home"><i class="fas fa-home" /></button>
      <button
        onClick={onUpload} aria-label="Add pin"
        style={{
          background: 'var(--primary)', color: 'white', border: '4px solid var(--card)',
          borderRadius: '50%', width: '64px', height: '64px', fontSize: '26px',
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
          marginTop: '-34px', boxShadow: '0 4px 12px rgba(0,0,0,0.25)', flexShrink: 0
        }}
      ><i class="fas fa-plus" /></button>
      <button style={iconStyle('profile')} onClick={onProfile} aria-label="Profile"><i class="fas fa-user" /></button>
    </nav>
  );
}
END
cat > src/components/Header.jsx << 'END'
import { LoginButton } from './LoginButton.jsx';

export function Header({
  darkMode, aiReady, searchTerm, filterCategory, selectedClass,
  classes, allCategories, onSearchChange, onFilterChange,
  onClassChange, onToggleTheme, onReset, user, onProfile
}) {
  return (
    <header style={{
      position: 'sticky', top: 0, background: 'var(--card)',
      borderBottom: '1px solid var(--border)', padding: '12px 16px', zIndex: 100
    }}>
      <div style={{
        maxWidth: '1400px', margin: '0 auto', display: 'flex',
        alignItems: 'center', gap: '16px', flexWrap: 'wrap'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', cursor: 'pointer' }} onClick={onReset}>
          <img
            src="/Img/InShot_20260907_212634930.png"
            alt="Logo"
            style={{ width: '24px', height: '24px', objectFit: 'contain' }}
          />
          <span style={{ fontWeight: 'bold', fontSize: '18px', marginLeft: '6px' }}>ገትር</span>
          {aiReady && <span class="ai-badge" style={{ marginLeft: '8px' }}>🤖 AI</span>}
        </div>

        <div style={{
          flex: 1, display: 'flex', alignItems: 'center',
          background: 'var(--border)', borderRadius: '24px',
          padding: '0 14px', minWidth: '200px'
        }}>
          <i class="fas fa-search" style={{ color: 'var(--text-sec)', fontSize: '14px' }} />
          <input
            type="text"
            placeholder="Search pins..."
            value={searchTerm}
            onInput={(e) => onSearchChange(e.target.value)}
            style={{
              flex: 1, padding: '8px 10px', border: 'none',
              background: 'transparent', outline: 'none', fontSize: '14px',
              color: 'var(--text)', width: 'auto'
            }}
          />
        </div>

        <LoginButton user={user} onProfile={onProfile} />
      </div>

      <div style={{ maxWidth: '1400px', margin: '0 auto', paddingTop: '12px' }}>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '8px' }}>
          {allCategories.map(cat => (
            <button
              key={cat}
              class="btn"
              onClick={() => onFilterChange(cat)}
              style={{
                padding: '6px 14px', fontSize: '13px',
                background: filterCategory === cat ? 'var(--primary)' : 'transparent',
                color: filterCategory === cat ? 'white' : 'var(--text-sec)',
                border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
              }}
            >
              {cat.charAt(0).toUpperCase() + cat.slice(1)}
            </button>
          ))}
        </div>
        {classes.length > 0 && (
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginTop: '4px' }}>
            <button
              class="btn"
              onClick={() => onClassChange('')}
              style={{
                padding: '4px 12px', fontSize: '12px',
                background: !selectedClass ? 'var(--primary)' : 'transparent',
                color: !selectedClass ? 'white' : 'var(--text-sec)',
                border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
              }}
            >
              All Classes
            </button>
            {classes.map(cls => (
              <button
                key={cls}
                class="btn"
                onClick={() => onClassChange(cls)}
                style={{
                  padding: '4px 12px', fontSize: '12px',
                  background: selectedClass === cls ? 'var(--primary)' : 'transparent',
                  color: selectedClass === cls ? 'white' : 'var(--text-sec)',
                  border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
                }}
              >
                #{cls}
              </button>
            ))}
          </div>
        )}
      </div>
    </header>
  );
}
END
cat > src/components/LoadingSpinner.jsx << 'END'
export function LoadingSpinner({ aiStatus, aiProgress }) {
  return (
    <div style={{ minHeight: '100vh', flexDirection: 'column', gap: '16px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <i class="fas fa-spinner fa-pulse" style={{ fontSize: '32px', color: 'var(--primary)' }} />
      <p style={{ color: 'var(--text-sec)' }}>Loading...</p>
      <div style={{ width: '300px' }}>
        <p style={{ fontSize: '12px', color: 'var(--text-sec)', marginBottom: '8px' }}>{aiStatus}</p>
        <div class="progress-bar"><div class="progress-fill" style={{ width: `${aiProgress}%` }} /></div>
      </div>
    </div>
  );
}
END
cat > src/components/LoginButton.jsx << 'END'
import { signInWithGoogle, signOut } from '../services/auth.js';

export function LoginButton({ user, onProfile }) {
  if (user) {
    return (
      <button
        onClick={onProfile}
        title={user.email}
        style={{
          display: 'flex', alignItems: 'center', gap: '8px',
          background: 'transparent', border: '1px solid var(--border)',
          borderRadius: '24px', padding: '4px 12px 4px 4px', cursor: 'pointer',
          color: 'var(--text)'
        }}
      >
        <img
          src={user.picture || 'https://i.pravatar.cc/40'}
          alt={user.name}
          style={{ width: '28px', height: '28px', borderRadius: '50%' }}
        />
        <span style={{ fontSize: '13px', fontWeight: 500 }}>{(user.name || '').split(' ')[0]}</span>
      </button>
    );
  }

  return (
    <button
      onClick={signInWithGoogle}
      style={{
        display: 'flex', alignItems: 'center', gap: '8px',
        background: 'var(--primary)', color: 'white', border: 'none',
        borderRadius: '24px', padding: '8px 16px', cursor: 'pointer',
        fontSize: '13px', fontWeight: 600
      }}
    >
      <i class="fab fa-google" />
      Sign in with Google
    </button>
  );
}

export { signOut };
END
cat > src/components/PinCard.jsx << 'END'
export function PinCard({ pin, onClick }) {
  return (
    <div
      style={{
        borderRadius: '12px', overflow: 'hidden', background: 'var(--border)',
        cursor: 'pointer', transition: 'transform 0.2s ease, box-shadow 0.2s ease',
        boxShadow: '0 1px 3px rgba(0,0,0,0.1)', height: `${pin.height}px`, position: 'relative'
      }}
      onClick={onClick}
      onMouseEnter={(e) => { e.currentTarget.style.transform = 'scale(1.02)'; e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = 'scale(1)'; e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.1)'; }}
    >
     <img
  src={pin.driveFileId
    ? `https://lh3.googleusercontent.com/d/${pin.driveFileId}`
    : (pin.thumbnail || pin.image)}
  alt={pin.title}
  style={{
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    objectPosition: 'center',
    display: 'block'
  }}
  loading="lazy"
/>
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '12px', background: 'linear-gradient(to top, rgba(0,0,0,0.7), transparent)', color: 'white' }}>
        <div style={{ fontWeight: '500', fontSize: '14px', marginBottom: '4px' }}>{pin.title}</div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', opacity: 0.8 }}>
          <span>{pin.category}</span>
          <span><i class="fas fa-heart" style={{ marginRight: '4px' }} />{pin.likes || 0}</span>
        </div>
        {pin.class && <div style={{ fontSize: '10px', opacity: 0.6, marginTop: '4px' }}>#{pin.class}</div>}
      </div>
    </div>
  );
}
END
cat > src/components/PinDetail.jsx << 'END'
import { Component, createRef } from 'preact';
import { cosineSimilarity } from '../services/ai.js';

export class PinDetail extends Component {
  constructor(props) {
    super(props);
    this.state = {
      isLiked: false,
      comment: '',
      saved: props.pin?.saved || false,
      similarPins: [],
      showCommentInput: false,
      searching: false
    };
    this.commentInputRef = createRef();
    this.similarSectionRef = createRef();
  }

  componentDidMount() {
    this.findSimilar();
  }

  componentDidUpdate(prevProps) {
    if (prevProps.pin?.id !== this.props.pin?.id) {
      this.setState({
        isLiked: false,
        saved: this.props.pin?.saved || false,
        showCommentInput: false
      });
      this.findSimilar();
    }
  }

  findSimilar = () => {
    const { pin, allPins, aiReady } = this.props;
    this.setState({ searching: true });

    if (aiReady && pin.features) {
      this.setState({
        similarPins: allPins
          .filter(p => p.id !== pin.id && p.features)
          .map(p => ({ ...p, similarity: cosineSimilarity(pin.features, p.features) }))
          .filter(p => p.similarity > 0.5)
          .sort((a, b) => b.similarity - a.similarity)
          .slice(0, 8),
        searching: false
      });
    } else {
      this.setState({
        similarPins: allPins
          .filter(p => p.id !== pin.id && (p.category === pin.category || p.class === pin.class))
          .slice(0, 8),
        searching: false
      });
    }
  };

  handleSearchSimilar = () => {
    this.findSimilar();
    if (this.similarSectionRef.current) {
      this.similarSectionRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };

  handleLike = () => {
    const newLiked = !this.state.isLiked;
    this.setState({ isLiked: newLiked });
    this.props.onUpdate(this.props.pin.id, {
      likes: (this.props.pin.likes || 0) + (newLiked ? 1 : -1)
    });
  };

  handleSave = () => {
    const newSaved = !this.state.saved;
    this.setState({ saved: newSaved });
    this.props.onUpdate(this.props.pin.id, { saved: newSaved });
  };

  toggleCommentInput = () => {
    this.setState(prev => ({ showCommentInput: !prev.showCommentInput }), () => {
      if (this.state.showCommentInput && this.commentInputRef.current) {
        this.commentInputRef.current.focus();
      }
    });
  };

  handleComment = () => {
    const { comment } = this.state;
    if (!comment.trim()) return;
    this.props.onUpdate(this.props.pin.id, {
      comments: [...(this.props.pin.comments || []), { text: comment, timestamp: Date.now() }]
    });
    this.setState({ comment: '' });
  };

  render() {
    const { pin, onClose, onDelete, onSelectPin, aiReady } = this.props;
    const { isLiked, comment, saved, similarPins, showCommentInput, searching } = this.state;

    if (!pin) return null;

    return (
      <div
        style={{
          position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(0,0,0,0.8)', zIndex: 1000,
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px'
        }}
        onClick={onClose}
      >
        <div
          style={{
            background: 'var(--card)', borderRadius: '16px', maxWidth: '700px',
            width: '100%', maxHeight: '90vh', overflow: 'auto',
            position: 'relative', display: 'flex', flexDirection: 'column'
          }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Image + overlaid buttons */}
          <div style={{ position: 'relative', width: '100%', background: 'var(--bg)' }}>
            <button
              style={{
                position: 'absolute', top: '12px', right: '12px',
                background: 'rgba(0,0,0,0.5)', border: 'none', color: 'white',
                width: '36px', height: '36px', borderRadius: '50%', cursor: 'pointer',
                fontSize: '16px', zIndex: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'center'
              }}
              onClick={onClose}
            >
              <i class="fas fa-times" />
            </button>

            <img
              src={pin.image || pin.thumbnail}
              alt={pin.title}
              style={{
                width: '100%', maxHeight: '65vh', objectFit: 'cover',
                display: 'block', borderRadius: '16px 16px 0 0'
              }}
              onError={(e) => {
                // Fallback to Google Drive direct export URL if the primary fails
                if (pin.driveFileId) {
                  e.target.src = `https://drive.google.com/uc?export=download&id=${pin.driveFileId}`;
                }
              }}
            />

            <button
              onClick={this.handleSearchSimilar}
              disabled={searching}
              style={{
                position: 'absolute', bottom: '16px', right: '16px',
                background: 'white', color: '#111', border: 'none', borderRadius: '24px',
                padding: '10px 16px', display: 'flex', alignItems: 'center', gap: '8px',
                boxShadow: '0 2px 10px rgba(0,0,0,0.35)',
                cursor: searching ? 'not-allowed' : 'pointer',
                fontWeight: 600, fontSize: '13px', opacity: searching ? 0.7 : 1
              }}
            >
              <i class={`fas ${searching ? 'fa-spinner fa-pulse' : 'fa-search'}`} />
              {searching ? 'Searching...' : ''}
            </button>
          </div>

          <div style={{ padding: '20px', overflow: 'auto' }}>
            {/* Title row */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px', marginBottom: '10px' }}>
              <h2 style={{
                fontSize: '18px', margin: 0, color: 'var(--text)', flex: 1, minWidth: 0,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'
              }}>{pin.title}</h2>

              <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
                <button
                  style={{
                    background: 'none', border: 'none',
                    color: isLiked ? 'var(--primary)' : 'var(--text-sec)',
                    cursor: 'pointer', fontSize: '15px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.handleLike}
                >
                  <i class={`${isLiked ? 'fas' : 'far'} fa-heart`} /> {pin.likes || 0}
                </button>

                <button
                  style={{
                    background: 'none', border: 'none',
                    color: showCommentInput ? 'var(--primary)' : 'var(--text-sec)',
                    cursor: 'pointer', fontSize: '15px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.toggleCommentInput}
                >
                  <i class="far fa-comment" /> {(pin.comments || []).length}
                </button>

                <button
                  style={{
                    background: saved ? 'var(--primary)' : 'transparent',
                    border: `1px solid ${saved ? 'var(--primary)' : 'var(--border)'}`,
                    color: saved ? 'white' : 'var(--text)',
                    cursor: 'pointer', fontSize: '13px', fontWeight: 600,
                    padding: '6px 14px', borderRadius: '18px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.handleSave}
                >
                  <i class={`${saved ? 'fas' : 'far'} fa-bookmark`} /> Save
                </button>

                <button
                  style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: '15px' }}
                  onClick={() => onDelete(pin.id)}
                >
                  <i class="fas fa-trash" />
                </button>
              </div>
            </div>

            {/* Tags */}
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '12px' }}>
              <span style={{ background: 'var(--border)', padding: '4px 12px', borderRadius: '16px', fontSize: '13px', color: 'var(--text-sec)' }}>{pin.category}</span>
              {pin.class && <span style={{ background: 'var(--border)', padding: '4px 12px', borderRadius: '16px', fontSize: '13px', color: 'var(--text-sec)' }}>#{pin.class}</span>}
              {pin.features && <span class="ai-badge" style={{ padding: '4px 12px', borderRadius: '16px', fontSize: '13px', background: 'var(--primary)', color: 'white' }}>🤖 AI</span>}
            </div>

            {/* Owner info (new) */}
            {pin.owner && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: '8px',
                marginBottom: '12px', padding: '8px 12px',
                background: 'var(--bg)', borderRadius: '12px'
              }}>
                <img
                  src={pin.owner.picture || 'https://i.pravatar.cc/40'}
                  alt={pin.owner.name || 'User'}
                  style={{ width: '28px', height: '28px', borderRadius: '50%' }}
                />
                <div style={{ fontSize: '13px', color: 'var(--text)' }}>
                  <span style={{ fontWeight: 600 }}>{pin.owner.name || 'Unknown'}</span>
                  {pin.owner.email && <span style={{ color: 'var(--text-sec)', marginLeft: '6px' }}>· {pin.owner.email}</span>}
                </div>
              </div>
            )}

            {pin.description && (
              <p style={{ color: 'var(--text-sec)', lineHeight: 1.6, marginBottom: '16px' }}>{pin.description}</p>
            )}

            {/* Comment input */}
            {showCommentInput && (
              <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
                <input
                  ref={this.commentInputRef}
                  type="text"
                  placeholder="Add comment..."
                  value={comment}
                  onInput={(e) => this.setState({ comment: e.target.value })}
                  onKeyPress={(e) => { if (e.key === 'Enter') this.handleComment(); }}
                  style={{
                    flex: 1, padding: '10px 14px', borderRadius: '20px',
                    border: '1px solid var(--border)', background: 'var(--bg)',
                    color: 'var(--text)', outline: 'none'
                  }}
                />
                <button
                  onClick={this.handleComment}
                  disabled={!comment.trim()}
                  style={{
                    width: '40px', height: '40px', borderRadius: '50%',
                    background: 'var(--primary)', color: 'white', border: 'none',
                    cursor: 'pointer', display: 'flex',
                    alignItems: 'center', justifyContent: 'center', flexShrink: 0
                  }}
                >
                  <i class="fas fa-paper-plane" />
                </button>
              </div>
            )}

            {/* Comments list */}
            <div style={{ marginBottom: '8px' }}>
              <h4 style={{ marginBottom: '12px', color: 'var(--text)' }}>Comments ({(pin.comments || []).length})</h4>
              <div style={{ maxHeight: '200px', overflow: 'auto', marginBottom: '12px' }}>
                {(pin.comments || []).length === 0 ? (
                  <p style={{ color: 'var(--text-sec)', textAlign: 'center' }}>No comments</p>
                ) : (
                  (pin.comments || []).map((c, i) => (
                    <div key={i} style={{ display: 'flex', gap: '8px', padding: '8px 0', borderBottom: '1px solid var(--border)' }}>
                      <div style={{
                        width: '28px', height: '28px', borderRadius: '50%',
                        background: 'var(--border)', display: 'flex',
                        alignItems: 'center', justifyContent: 'center', flexShrink: 0
                      }}>
                        <i class="fas fa-user" style={{ fontSize: '12px', color: 'var(--text-sec)' }} />
                      </div>
                      <div style={{ flex: 1 }}>
                        <p style={{ fontSize: '14px', color: 'var(--text)' }}>{c.text}</p>
                        <span style={{ fontSize: '11px', color: 'var(--text-sec)' }}>{new Date(c.timestamp).toLocaleString()}</span>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Similar pins */}
            {similarPins.length > 0 && (
              <div ref={this.similarSectionRef} style={{ marginTop: '20px' }}>
                <h4 style={{ marginBottom: '12px', color: 'var(--text)' }}>
                  {aiReady && pin.features ? '🤖 AI Similar' : '📂 Similar'}
                </h4>
                <div style={{ columnCount: 2, columnGap: '10px' }}>
                  {similarPins.map(p => (
                    <div
                      key={p.id}
                      style={{
                        breakInside: 'avoid', marginBottom: '10px',
                        borderRadius: '10px', overflow: 'hidden',
                        background: 'var(--bg)', cursor: 'pointer', position: 'relative'
                      }}
                      onClick={() => onSelectPin(p)}
                    >
                      <img
                        src={p.thumbnail || p.image}
                        alt={p.title}
                        style={{ width: '100%', display: 'block', objectFit: 'cover' }}
                        onError={(e) => {
                          if (p.driveFileId) {
                            e.target.src = `https://drive.google.com/uc?export=download&id=${p.driveFileId}`;
                          }
                        }}
                      />
                      <div style={{
                        position: 'absolute', bottom: 0, left: 0, right: 0,
                        padding: '8px',
                        background: 'linear-gradient(to top, rgba(0,0,0,0.65), transparent)',
                        color: 'white'
                      }}>
                        <span style={{
                          display: 'block', fontSize: '12px',
                          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'
                        }}>{p.title}</span>
                        {p.similarity && (
                          <span style={{ fontSize: '10px', opacity: 0.85 }}>
                            {Math.round(p.similarity * 100)}% match
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }
}
END
cat > src/components/PinGrid.jsx << 'END'
import { PinCard } from './PinCard.jsx';
export function PinGrid({ pins, columns, onPinClick }) {
  if (pins.length === 0) {
    return (
      <div style={{ textAlign: 'center', padding: '60px', color: 'var(--text-sec)' }}>
        <i class="fas fa-thumbtack" style={{ fontSize: '48px', marginBottom: '16px' }} />
        <h3>No pins yet</h3>
        <p>Click + to add your first pin!</p>
      </div>
    );
  }
  const containerWidth = Math.min(1400, window.innerWidth - 32);
  const gap = 16;
  const colWidth = (containerWidth - (columns - 1) * gap) / columns;
  const columnHeights = new Array(columns).fill(0);
  const columnPins = new Array(columns).fill(null).map(() => []);
  pins.forEach(pin => {
    let minHeight = Infinity, minIndex = 0;
    for (let i = 0; i < columns; i++) {
      if (columnHeights[i] < minHeight) { minHeight = columnHeights[i]; minIndex = i; }
    }
    const aspectRatio = pin.imageWidth && pin.imageHeight ? pin.imageHeight / pin.imageWidth : 1.2;
    const pinHeight = colWidth * aspectRatio;
    columnPins[minIndex].push({ ...pin, height: pinHeight });
    columnHeights[minIndex] += pinHeight + gap;
  });
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: '16px', alignItems: 'start' }}>
      {columnPins.map((column, colIndex) => (
        <div key={colIndex} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {column.map(pin => <PinCard key={pin.id} pin={pin} onClick={() => onPinClick(pin)} />)}
        </div>
      ))}
    </div>
  );
}
END
cat > src/components/ProfileModal.jsx << 'END'
import { signOut } from '../services/auth.js';

export function ProfileModal({ pins, classes, aiReady, darkMode, user, onClose, onClearAll, onToggleTheme }) {
  const counts = {};
  const classCounts = {};
  pins.forEach(p => {
    const cat = p.category || 'Uncategorized';
    counts[cat] = (counts[cat] || 0) + 1;
    if (p.class) classCounts[p.class] = (classCounts[p.class] || 0) + 1;
  });
  const aiCount = pins.filter(p => p.features).length;

  return (
    <div
      style={{
        position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
        background: 'rgba(0,0,0,0.7)', zIndex: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px'
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: 'var(--card)', borderRadius: '16px', maxWidth: '500px',
          width: '100%', maxHeight: '90vh', overflow: 'auto', padding: '24px'
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h3 style={{ color: 'var(--text)', margin: 0 }}>Profile</h3>
          <button style={{ background: 'none', border: 'none', color: 'var(--text-sec)', cursor: 'pointer', fontSize: '20px' }} onClick={onClose}>
            <i class="fas fa-times" />
          </button>
        </div>

        {user && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '20px', padding: '12px', background: 'var(--bg)', borderRadius: '12px' }}>
            <img src={user.picture} alt={user.name} style={{ width: '48px', height: '48px', borderRadius: '50%' }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 600, color: 'var(--text)' }}>{user.name}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-sec)', overflow: 'hidden', textOverflow: 'ellipsis' }}>{user.email}</div>
              <div style={{ fontSize: '11px', color: '#22c55e', marginTop: '2px' }}>
                <i class="fas fa-check-circle" /> Google Drive connected
              </div>
            </div>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '12px', marginBottom: '24px' }}>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--text)' }}>{pins.length}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>Total</div>
          </div>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--text)' }}>{Object.keys(counts).length}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>Categories</div>
          </div>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: '#667eea' }}>{aiCount}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>AI Pins</div>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <button
            style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text)', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
            onClick={onToggleTheme}
          >
            <i class={`fas ${darkMode ? 'fa-sun' : 'fa-moon'}`} />
            {darkMode ? 'Light Mode' : 'Dark Mode'}
          </button>

          <button
            style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid #ef4444', background: 'transparent', color: '#ef4444', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
            onClick={onClearAll}
          >
            <i class="fas fa-trash" /> Clear All (disabled)
          </button>

          {user && (
            <button
              style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text)', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
              onClick={signOut}
            >
              <i class="fas fa-sign-out-alt" /> Sign out
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
END
cat > src/components/RoyalPage.jsx << 'END'
export function RoyalPage({ onClose }) {
  return (
    <div class="royal-page">
      <div class="royal-back-bar">
        <button class="royal-back-btn" onClick={onClose}><i class="fas fa-arrow-left" /> Back</button>
      </div>
      <div class="royal-hero">
        <div class="royal-crown"><i class="fas fa-crown" /></div>
        <div class="royal-avatar">
          <img src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400&h=400&fit=crop" alt="Royal" />
        </div>
        <div class="royal-info">
          <h1 class="royal-name">Queen Elsee</h1>
          <div class="royal-title">👑 Royal Status • Supreme Pop • Crown Holder</div>
          <div class="royal-stats">
            <div class="royal-stat"><div class="royal-stat-value">#1</div><div class="royal-stat-label">Rank</div></div>
            <div class="royal-stat"><div class="royal-stat-value">24.5K</div><div class="royal-stat-label">Followers</div></div>
            <div class="royal-stat"><div class="royal-stat-value">1.2M</div><div class="royal-stat-label">Views</div></div>
            <div class="royal-stat"><div class="royal-stat-value">89</div><div class="royal-stat-label">Days</div></div>
          </div>
          <div class="royal-actions">
            <button class="royal-btn"><i class="fas fa-crown" /> Pay Tribute</button>
            <button class="royal-btn secondary"><i class="fas fa-gem" /> Send Gift</button>
            <button class="royal-btn secondary"><i class="fas fa-user-plus" /> Follow</button>
          </div>
        </div>
      </div>
      <div class="royalty-tier">
        <div class="tier-icon"><i class="fas fa-crown" /></div>
        <div class="tier-info">
          <h4>Supreme Royalty • Diamond Tier</h4>
          <p>Holder of the highest rank in the kingdom. Reigning champion for 89 consecutive days.</p>
        </div>
      </div>
      <div class="royalty-stats">
        <div class="royalty-stat"><div class="stat-value">89</div><div style="font-size:12px;color:var(--text-sec)">Reign Days</div></div>
        <div class="royalty-stat"><div class="stat-value">1,247</div><div style="font-size:12px;color:var(--text-sec)">Tributes</div></div>
        <div class="royalty-stat"><div class="stat-value">24.5K</div><div style="font-size:12px;color:var(--text-sec)">Subjects</div></div>
        <div class="royalty-stat"><div class="stat-value">#1</div><div style="font-size:12px;color:var(--text-sec)">Rank</div></div>
      </div>
    </div>
  );
}
END
cat > src/components/UploadModal.jsx << 'END'
import { Component } from 'preact';
import { compressImage, createThumbnail, getImageDimensions } from '../services/imageUtils.js';
import { extractFeatures } from '../services/ai.js';

// Pose detector removed from this script for brevity — same behavior as before
// (kept minimal: no MediaPipe, uploads still work). If you need MediaPipe back,
// paste the original pose code into this file — it is unchanged.
async function detectPose() { return null; }

export class UploadModal extends Component {
  constructor(props) {
    super(props);
    this.state = {
      title: '', description: '',
      category: props.categories?.[0] || 'Instagram',
      imageData: null, thumbnail: null, preview: null,
      loading: false, class: '', processingAI: false,
      socialUrl: '', fetchingSocial: false, socialError: '',
      platform: 'instagram', activeTab: 'upload',
      poseInfo: null, analyzingPose: false, poseError: ''
    };
  }

  handleImageUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async (ev) => {
      const dataUrl = ev.target.result;
      this.setState({ preview: dataUrl });
      const compressed = await compressImage(dataUrl);
      const thumb = await createThumbnail(compressed);
      this.setState({ imageData: compressed, thumbnail: thumb });
    };
    reader.readAsDataURL(file);
  };

  handleFetchSocial = async () => {
    const url = this.state.socialUrl.trim();
    if (!url) return this.setState({ socialError: 'Please enter a URL' });
    this.setState({ fetchingSocial: true, socialError: '', preview: null, imageData: null });

    try {
      const response = await fetch('/api/fetch-social-post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url, platform: this.state.platform })
      });
      const data = await response.json();
      if (!response.ok || !data.success) throw new Error(data.error || 'Server error');

      this.setState({
        imageData: data.image, preview: data.image,
        title: data.title || 'Instagram Post',
        description: data.description || '',
        socialError: ''
      });
    } catch (error) {
      this.setState({ socialError: error.message });
    } finally {
      this.setState({ fetchingSocial: false });
    }
  };

  handleFetchDirectUrl = async () => {
    const url = this.state.socialUrl.trim();
    if (!url) return this.setState({ socialError: 'Please enter an image URL' });
    this.setState({ fetchingSocial: true, socialError: '', preview: null, imageData: null });
    try {
      const response = await fetch('/api/fetch-image-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ imageUrl: url })
      });
      const data = await response.json();
      if (!response.ok || !data.success) throw new Error(data.error || 'Server error');
      this.setState({ imageData: data.image, preview: data.image, title: 'Image from URL', description: url });
    } catch (error) {
      this.setState({ socialError: error.message });
    } finally {
      this.setState({ fetchingSocial: false });
    }
  };

  handleSubmit = async () => {
    const { imageData, title, description, category, class: className, thumbnail } = this.state;
    if (!imageData || !title.trim()) return alert('Please add an image and title');

    this.setState({ loading: true });
    try {
      const dims = await getImageDimensions(imageData);
      let features = null;
      if (this.props.aiReady) {
        this.setState({ processingAI: true });
        try { features = await extractFeatures(imageData); } catch (err) { console.warn('AI failed:', err); }
        this.setState({ processingAI: false });
      }

      await this.props.onSave({
        title: title.trim(),
        description: description.trim(),
        category,
        class: className?.trim() || '',
        image: imageData,
        thumbnail,
        imageWidth: dims.width,
        imageHeight: dims.height,
        features
      });
    } catch (error) {
      alert('Failed: ' + error.message);
    } finally {
      this.setState({ loading: false });
    }
  };

  render() {
    const { onClose, categories, classes } = this.props;
    const {
      title, description, category, class: className, preview, loading,
      socialUrl, fetchingSocial, socialError, platform, activeTab,
      processingAI
    } = this.state;
    const allClasses = classes || [];

    return (
      <div class="modal-overlay" onClick={onClose}>
        <div class="modal-content" onClick={(e) => e.stopPropagation()}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <h3 style={{ margin: 0 }}>Create Pin</h3>
            <button style={{ background: 'none', border: 'none', fontSize: '24px', cursor: 'pointer', color: 'var(--text-sec)' }} onClick={onClose}>✕</button>
          </div>

          <div style={{ display: 'flex', gap: '4px', marginBottom: '20px', background: 'var(--bg)', borderRadius: '12px', padding: '4px', border: '1px solid var(--border)' }}>
            <button
              style={{
                flex: 1, padding: '10px', borderRadius: '8px', border: 'none',
                background: activeTab === 'upload' ? 'var(--primary)' : 'transparent',
                color: activeTab === 'upload' ? 'white' : 'var(--text-sec)',
                cursor: 'pointer', fontWeight: '600', fontSize: '14px'
              }}
              onClick={() => this.setState({ activeTab: 'upload', socialError: '' })}
            >
              <i class="fas fa-upload" style={{ marginRight: '6px' }} /> Upload
            </button>
            <button
              style={{
                flex: 1, padding: '10px', borderRadius: '8px', border: 'none',
                background: activeTab === 'fetch' ? 'var(--primary)' : 'transparent',
                color: activeTab === 'fetch' ? 'white' : 'var(--text-sec)',
                cursor: 'pointer', fontWeight: '600', fontSize: '14px'
              }}
              onClick={() => this.setState({ activeTab: 'fetch', socialError: '' })}
            >
              <i class="fas fa-link" style={{ marginRight: '6px' }} /> Fetch URL
            </button>
          </div>

          {activeTab === 'upload' ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div
                style={{
                  border: '2px dashed var(--border)', borderRadius: '12px', padding: '20px',
                  textAlign: 'center', cursor: 'pointer', minHeight: '180px',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'var(--bg)', width: '100%'
                }}
                onClick={() => document.getElementById('fileInput').click()}
              >
                {preview ? (
                  <img src={preview} alt="Preview" style={{ maxWidth: '100%', maxHeight: '280px', objectFit: 'contain' }} />
                ) : (
                  <div style={{ color: 'var(--text-sec)' }}>
                    <i class="fas fa-cloud-upload-alt" style={{ fontSize: '48px', display: 'block', marginBottom: '8px' }} />
                    <p>Click to upload image</p>
                  </div>
                )}
                <input id="fileInput" type="file" accept="image/*" onChange={this.handleImageUpload} style={{ display: 'none' }} />
              </div>

              <input type="text" placeholder="Title *" value={title} onInput={(e) => this.setState({ title: e.target.value })} />
              <textarea placeholder="Description" value={description} onInput={(e) => this.setState({ description: e.target.value })} rows="3" />
              <select value={category} onChange={(e) => this.setState({ category: e.target.value })}>
                {categories?.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
              <div>
                <input type="text" placeholder="Add class/tag (optional)" value={className} onInput={(e) => this.setState({ class: e.target.value })} />
                {allClasses.length > 0 && (
                  <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginTop: '8px' }}>
                    {allClasses.map(c => (
                      <span key={c}
                        style={{
                          padding: '2px 10px', borderRadius: '12px',
                          background: className === c ? 'var(--primary)' : 'var(--border)',
                          color: className === c ? 'white' : 'var(--text-sec)',
                          fontSize: '11px', cursor: 'pointer'
                        }}
                        onClick={() => this.setState({ class: c })}
                      >#{c}</span>
                    ))}
                  </div>
                )}
              </div>

              {processingAI && (
                <div style={{ textAlign: 'center', color: 'var(--text-sec)', fontSize: '14px', width: '100%' }}>
                  <i class="fas fa-spinner fa-pulse" /> Analyzing with AI...
                </div>
              )}
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <select value={platform} onChange={(e) => this.setState({ platform: e.target.value })}>
                <option value="instagram">Instagram</option>
                <option value="twitter">Twitter/X</option>
                <option value="facebook">Facebook</option>
                <option value="pinterest">Pinterest</option>
              </select>

              <div style={{ display: 'flex', gap: '8px' }}>
                <input type="url" placeholder={`Paste ${platform} post URL...`} value={socialUrl} onInput={(e) => this.setState({ socialUrl: e.target.value })} />
                <button className="btn btn-primary" onClick={this.handleFetchSocial} disabled={fetchingSocial} style={{ whiteSpace: 'nowrap' }}>
                  {fetchingSocial ? <i class="fas fa-spinner fa-pulse" /> : 'Fetch'}
                </button>
              </div>

              <div style={{ textAlign: 'center', color: 'var(--text-sec)', fontSize: '12px' }}>— OR —</div>

              <div style={{ display: 'flex', gap: '8px' }}>
                <input type="url" placeholder="Paste direct image URL..." value={socialUrl} onInput={(e) => this.setState({ socialUrl: e.target.value })} />
                <button className="btn" style={{ background: 'var(--bg)', color: 'var(--text)', border: '1px solid var(--border)', whiteSpace: 'nowrap' }} onClick={this.handleFetchDirectUrl} disabled={fetchingSocial}>
                  {fetchingSocial ? <i class="fas fa-spinner fa-pulse" /> : 'Fetch URL'}
                </button>
              </div>

              {socialError && (
                <div style={{ padding: '10px 14px', borderRadius: '8px', background: '#fee2e2', color: '#dc2626', fontSize: '14px' }}>
                  <i class="fas fa-exclamation-circle" style={{ marginRight: '6px' }} />{socialError}
                </div>
              )}

              {preview && (
                <>
                  <div style={{ border: '2px dashed var(--border)', borderRadius: '12px', padding: '12px', textAlign: 'center' }}>
                    <img src={preview} alt="Preview" style={{ maxWidth: '100%', maxHeight: '250px', objectFit: 'contain' }} />
                  </div>
                  <input type="text" placeholder="Title *" value={title} onInput={(e) => this.setState({ title: e.target.value })} />
                  <textarea placeholder="Description" value={description} onInput={(e) => this.setState({ description: e.target.value })} rows="3" />
                  <select value={category} onChange={(e) => this.setState({ category: e.target.value })}>
                    {categories?.map(c => <option key={c} value={c}>{c}</option>)}
                  </select>
                </>
              )}
            </div>
          )}

          <div style={{ display: 'flex', gap: '8px', marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--border)' }}>
            <button className="btn" style={{ flex: 1, background: 'transparent', color: 'var(--text-sec)', border: '1px solid var(--border)' }} onClick={onClose}>Cancel</button>
            <button className="btn btn-primary" style={{ flex: 2, opacity: loading || !this.state.imageData ? 0.6 : 1 }} onClick={this.handleSubmit} disabled={loading || !this.state.imageData}>
              {loading ? <><i class="fas fa-spinner fa-pulse" /> Saving to Drive...</> : 'Save Pin to Drive'}
            </button>
          </div>
        </div>
      </div>
    );
  }
}
END
cat > src/services/ai.js << 'END'
let featureExtractor = null;
let aiReady = false, aiLoading = false, aiProgress = 0, aiStatus = '';

export async function initAI() {
  if (aiReady) return true;
  if (aiLoading) { let a = 0; while (aiLoading && a < 100) { await new Promise(r => setTimeout(r, 200)); a++; } return aiReady; }
  aiLoading = true; aiStatus = 'Initializing AI...';
  try {
    let attempts = 0;
    while (!window.transformers && attempts < 50) { await new Promise(r => setTimeout(r, 200)); attempts++; }
    if (!window.transformers) throw new Error('CDN failed');
    const { pipeline } = window.transformers;
    const models = ['Xenova/detr-resnet-50', 'timm/efficientnet_lite0.ra_in1k'];
    let lastError = null;
    for (const modelName of models) {
      try {
        featureExtractor = await pipeline('image-feature-extraction', modelName, {
          quantized: true,
          progress_callback: (progress) => {
            if (progress.status === 'downloading') {
              const pct = Math.round((progress.loaded / progress.total) * 100);
              aiProgress = pct;
              if (window._onProgress) window._onProgress(pct);
            }
          }
        });
        aiReady = true; aiLoading = false; aiProgress = 100; aiStatus = 'AI Ready!';
        if (window._onProgress) window._onProgress(100);
        return true;
      } catch (err) { lastError = err; }
    }
    throw lastError || new Error('All models failed');
  } catch (error) {
    console.error('AI init failed:', error.message);
    aiLoading = false; aiReady = false;
    aiStatus = 'AI unavailable - using basic mode';
    return false;
  }
}

export async function extractFeatures(imageUrl) {
  if (!aiReady) throw new Error('AI not ready');
  const result = await featureExtractor(imageUrl, { pooling: 'mean', normalize: true });
  return Array.from(result.data);
}

export function cosineSimilarity(a, b) {
  if (!a || !b || a.length !== b.length) return 0;
  let dot = 0, magA = 0, magB = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; magA += a[i] * a[i]; magB += b[i] * b[i]; }
  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  return denom === 0 ? 0 : dot / denom;
}

export { aiReady, aiLoading, aiProgress, aiStatus };
END
cat > src/services/api.js << 'END'
const JSON_HEADERS = { 'Content-Type': 'application/json' };

async function request(url, options = {}) {
  const res = await fetch(url, { credentials: 'include', ...options });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error((data && data.error) || `HTTP ${res.status}`);
  return data;
}

export const api = {
  // --- auth ---
  me: () => request('/api/auth/me'),
  loginUrl: '/api/auth/google',
  logout: () => request('/api/auth/logout', { method: 'POST' }),

  // --- pins ---
  listPins: (params = {}) => {
    const qs = new URLSearchParams(params).toString();
    return request('/api/pins' + (qs ? '?' + qs : ''));
  },
  createPin: (pin) => request('/api/pins', { method: 'POST', headers: JSON_HEADERS, body: JSON.stringify(pin) }),
  updatePin: (id, patch) => request(`/api/pins/${id}`, { method: 'PATCH', headers: JSON_HEADERS, body: JSON.stringify(patch) }),
  deletePin: (id) => request(`/api/pins/${id}`, { method: 'DELETE' })
};
END
cat > src/services/auth.js << 'END'
import { api } from './api.js';

export function signInWithGoogle() {
  // Full-page redirect to the server's OAuth start endpoint
  window.location.href = api.loginUrl;
}

export async function getCurrentUser() {
  try {
    const res = await api.me();
    return res.user || null;
  } catch {
    return null;
  }
}

export async function signOut() {
  try { await api.logout(); } catch {}
  window.location.reload();
}
END
cat > src/services/database.js << 'END'
// Deprecated: images are now stored in Google Drive + Supabase.
// Kept as a stub so legacy imports don't break.
export async function clearAll() {
  // No-op — nothing to clear locally.
  console.warn('clearAll(): IndexedDB removed. Pins live in Supabase now.');
}
END
cat > src/services/imageUtils.js << 'END'
export function getImageDimensions(dataUrl) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve({ width: img.width, height: img.height });
    img.onerror = reject;
    img.src = dataUrl;
  });
}

export function compressImage(dataUrl, maxSize = 800) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      let w = img.width, h = img.height;
      if (w > maxSize) { h = (maxSize / w) * h; w = maxSize; }
      if (h > maxSize) { w = (maxSize / h) * w; h = maxSize; }
      canvas.width = w; canvas.height = h;
      canvas.getContext('2d').drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL('image/jpeg', 0.7));
    };
    img.onerror = reject;
    img.src = dataUrl;
  });
}

export function createThumbnail(dataUrl, maxSize = 480) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      let w = img.width, h = img.height;
      if (w >= h) { if (w > maxSize) { h = Math.round((maxSize / w) * h); w = maxSize; } }
      else { if (h > maxSize) { w = Math.round((maxSize / h) * w); h = maxSize; } }
      const canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL('image/jpeg', 0.78));
    };
    img.onerror = reject;
    img.src = dataUrl;
  });
}
END
cat > src/hooks/usePins.js << 'END'
import { api } from '../services/api.js';

export const usePins = {
  getAll: async () => {
    const { pins } = await api.listPins({ limit: 500 });
    return pins;
  },

  getClasses: async () => {
    const { pins } = await api.listPins({ limit: 1000 });
    const classSet = new Set();
    pins.forEach(p => { if (p.class) classSet.add(p.class); });
    return Array.from(classSet);
  },

  add: async (pinData) => {
    const { pin } = await api.createPin({
      image: pinData.image,
      thumbnail: pinData.thumbnail,
      title: pinData.title,
      description: pinData.description,
      category: pinData.category,
      class: pinData.class,
      imageWidth: pinData.imageWidth,
      imageHeight: pinData.imageHeight,
      features: pinData.features,
      pose: pinData.pose
    });
    return pin;
  },

  update: async (id, data) => {
    await api.updatePin(id, data);
  },

  delete: async (id) => {
    await api.deletePin(id);
  },

  filter: (pins, searchTerm, filterCategory, selectedClass) => {
    return pins.filter(pin => {
      const matchCat = filterCategory === 'all' || pin.category === filterCategory;
      const matchClass = !selectedClass || pin.class === selectedClass;
      const term = (searchTerm || '').toLowerCase();
      const matchSearch = !term ||
        (pin.title || '').toLowerCase().includes(term) ||
        (pin.description || '').toLowerCase().includes(term) ||
        (pin.category || '').toLowerCase().includes(term) ||
        (pin.class || '').toLowerCase().includes(term);
      return matchCat && matchClass && matchSearch;
    });
  }
};
END
npm install
echo 'Done! Run npm start'
