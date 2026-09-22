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
