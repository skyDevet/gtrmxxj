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
