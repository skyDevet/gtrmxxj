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
