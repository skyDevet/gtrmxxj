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
}