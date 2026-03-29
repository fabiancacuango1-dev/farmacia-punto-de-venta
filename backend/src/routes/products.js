const express = require('express');
const { getDb } = require('../database');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// GET /api/products
router.get('/', (req, res) => {
  const { search, category_id, active_only } = req.query;
  const db = getDb();

  let query = 'SELECT * FROM products WHERE 1=1';
  const params = [];

  if (active_only !== 'false') {
    query += ' AND is_active = 1';
  }
  if (category_id) {
    query += ' AND category_id = ?';
    params.push(category_id);
  }
  if (search) {
    query += ' AND (name LIKE ? OR barcode LIKE ? OR generic_name LIKE ?)';
    const term = `%${search}%`;
    params.push(term, term, term);
  }

  query += ' ORDER BY name ASC';
  const products = db.prepare(query).all(...params);
  res.json(products);
});

// GET /api/products/:id
router.get('/:id', (req, res) => {
  const db = getDb();
  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
  if (!product) return res.status(404).json({ error: 'Producto no encontrado' });
  res.json(product);
});

// POST /api/products
router.post('/', (req, res) => {
  const db = getDb();
  const p = req.body;
  const id = p.id || require('uuid').v4();

  db.prepare(`
    INSERT INTO products (id, barcode, internal_code, name, generic_name, description,
      category_id, supplier_id, purchase_price, sale_price, current_stock, minimum_stock,
      maximum_stock, unit, location, requires_prescription, is_tax_exempt, is_active)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    id, p.barcode, p.internal_code, p.name, p.generic_name, p.description,
    p.category_id, p.supplier_id, p.purchase_price || 0, p.sale_price || 0,
    p.current_stock || 0, p.minimum_stock || 5, p.maximum_stock || 1000,
    p.unit || 'unidad', p.location, p.requires_prescription ? 1 : 0,
    p.is_tax_exempt ? 1 : 0, 1
  );

  res.status(201).json({ id, ...p });
});

// PUT /api/products/:id
router.put('/:id', (req, res) => {
  const db = getDb();
  const p = req.body;

  const existing = db.prepare('SELECT id FROM products WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Producto no encontrado' });

  db.prepare(`
    UPDATE products SET barcode = ?, internal_code = ?, name = ?, generic_name = ?,
      description = ?, category_id = ?, supplier_id = ?, purchase_price = ?,
      sale_price = ?, current_stock = ?, minimum_stock = ?, maximum_stock = ?,
      unit = ?, location = ?, requires_prescription = ?, is_tax_exempt = ?,
      updated_at = datetime('now')
    WHERE id = ?
  `).run(
    p.barcode, p.internal_code, p.name, p.generic_name, p.description,
    p.category_id, p.supplier_id, p.purchase_price, p.sale_price,
    p.current_stock, p.minimum_stock, p.maximum_stock, p.unit, p.location,
    p.requires_prescription ? 1 : 0, p.is_tax_exempt ? 1 : 0,
    req.params.id
  );

  res.json({ id: req.params.id, ...p });
});

// DELETE /api/products/:id (soft delete)
router.delete('/:id', (req, res) => {
  const db = getDb();
  db.prepare('UPDATE products SET is_active = 0, updated_at = datetime(\'now\') WHERE id = ?').run(req.params.id);
  res.json({ success: true });
});

module.exports = router;
