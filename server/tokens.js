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
