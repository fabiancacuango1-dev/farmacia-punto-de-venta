const express = require('express');
const bcrypt = require('bcryptjs');
const { getDb } = require('../database');
const { generateToken } = require('../middleware/auth');

const router = express.Router();

// POST /api/auth/login
router.post('/login', (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username y password requeridos' });
  }

  const db = getDb();
  const user = db.prepare('SELECT * FROM users WHERE username = ? AND is_active = 1').get(username);

  if (!user) {
    return res.status(401).json({ error: 'Credenciales inválidas' });
  }

  const valid = bcrypt.compareSync(password, user.password_hash);
  if (!valid) {
    return res.status(401).json({ error: 'Credenciales inválidas' });
  }

  const token = generateToken(user);

  res.json({
    token,
    user: {
      id: user.id,
      username: user.username,
      fullName: user.full_name,
      role: user.role,
    },
  });
});

// POST /api/auth/register (admin only — requires token in real usage)
router.post('/register', (req, res) => {
  const { id, username, password, fullName, role } = req.body;

  if (!username || !password || !fullName) {
    return res.status(400).json({ error: 'Campos requeridos: username, password, fullName' });
  }

  const db = getDb();
  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) {
    return res.status(409).json({ error: 'El usuario ya existe' });
  }

  const hash = bcrypt.hashSync(password, 10);
  const userId = id || require('uuid').v4();

  db.prepare(`
    INSERT INTO users (id, username, password_hash, full_name, role)
    VALUES (?, ?, ?, ?, ?)
  `).run(userId, username, hash, fullName, role || 'cashier');

  res.status(201).json({ id: userId, username, fullName, role: role || 'cashier' });
});

module.exports = router;
