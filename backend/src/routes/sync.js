const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../database');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// All sync routes require authentication
router.use(authenticateToken);

// POST /api/sync/push — receive changes from a client device
router.post('/push', (req, res) => {
  const { table, record_id, operation, payload, device_id, created_at } = req.body;

  if (!table || !record_id || !operation || !payload || !device_id) {
    return res.status(400).json({ error: 'Campos requeridos: table, record_id, operation, payload, device_id' });
  }

  const db = getDb();

  try {
    db.transaction(() => {
      // 1. Log the sync entry
      db.prepare(`
        INSERT INTO sync_log (id, target_table, record_id, operation, payload, status, device_id, created_at, synced_at)
        VALUES (?, ?, ?, ?, ?, 'synced', ?, ?, datetime('now'))
      `).run(uuidv4(), table, record_id, operation, JSON.stringify(payload), device_id, created_at || new Date().toISOString());

      // 2. Apply the change to the server's table
      applyChange(db, table, operation, record_id, payload);

      // 3. Register device if new
      const device = db.prepare('SELECT id FROM devices WHERE id = ?').get(device_id);
      if (!device) {
        db.prepare('INSERT INTO devices (id, name, last_sync) VALUES (?, ?, datetime(\'now\'))').run(device_id, `Device ${device_id.substring(0, 8)}`);
      } else {
        db.prepare('UPDATE devices SET last_sync = datetime(\'now\') WHERE id = ?').run(device_id);
      }
    })();

    res.json({ success: true, message: 'Cambio sincronizado' });
  } catch (err) {
    console.error('Sync push error:', err);
    res.status(500).json({ error: 'Error al sincronizar', detail: err.message });
  }
});

// GET /api/sync/pull — send changes to a client device
router.get('/pull', (req, res) => {
  const { device_id, last_sync } = req.query;

  if (!device_id) {
    return res.status(400).json({ error: 'device_id requerido' });
  }

  const db = getDb();

  try {
    let query = `
      SELECT * FROM sync_log
      WHERE device_id != ?
      AND status = 'synced'
    `;
    const params = [device_id];

    if (last_sync) {
      query += ' AND created_at > ?';
      params.push(last_sync);
    }

    query += ' ORDER BY created_at ASC LIMIT 500';

    const changes = db.prepare(query).all(...params);

    const parsed = changes.map(c => ({
      id: c.id,
      table: c.target_table,
      record_id: c.record_id,
      operation: c.operation,
      payload: JSON.parse(c.payload),
      created_at: c.created_at,
      updated_at: c.created_at,
    }));

    // Update device last sync
    db.prepare('UPDATE devices SET last_sync = datetime(\'now\') WHERE id = ?').run(device_id);

    res.json({ changes: parsed, count: parsed.length });
  } catch (err) {
    console.error('Sync pull error:', err);
    res.status(500).json({ error: 'Error al obtener cambios' });
  }
});

// GET /api/sync/status — get sync status for a device
router.get('/status', (req, res) => {
  const { device_id } = req.query;
  const db = getDb();

  const pending = db.prepare(
    "SELECT COUNT(*) as count FROM sync_log WHERE device_id = ? AND status = 'pending'"
  ).get(device_id || '');

  const lastSync = db.prepare(
    'SELECT last_sync FROM devices WHERE id = ?'
  ).get(device_id || '');

  res.json({
    pending: pending?.count || 0,
    lastSync: lastSync?.last_sync || null,
  });
});

/**
 * Apply a change from sync to the corresponding server table
 */
function applyChange(db, table, operation, recordId, payload) {
  const allowedTables = ['products', 'categories', 'suppliers', 'sales', 'sale_items', 'users'];

  if (!allowedTables.includes(table)) {
    return; // Ignore unknown tables
  }

  if (operation === 'delete') {
    db.prepare(`UPDATE ${table} SET is_active = 0 WHERE id = ?`).run(recordId);
    return;
  }

  if (operation === 'insert' || operation === 'update') {
    const columns = Object.keys(payload);
    const values = Object.values(payload);

    if (operation === 'insert') {
      const placeholders = columns.map(() => '?').join(', ');
      const stmt = `INSERT OR REPLACE INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})`;
      db.prepare(stmt).run(...values);
    } else {
      const setClause = columns.map(c => `${c} = ?`).join(', ');
      const stmt = `UPDATE ${table} SET ${setClause} WHERE id = ?`;
      db.prepare(stmt).run(...values, recordId);
    }
  }
}

module.exports = router;
