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
