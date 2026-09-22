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
