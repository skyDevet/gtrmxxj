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
