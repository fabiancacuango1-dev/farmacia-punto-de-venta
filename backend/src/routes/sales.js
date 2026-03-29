const express = require('express');
const { getDb } = require('../database');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// GET /api/sales
router.get('/', (req, res) => {
  const { from, to, user_id, status } = req.query;
  const db = getDb();

  let query = 'SELECT * FROM sales WHERE 1=1';
  const params = [];

  if (from) {
    query += ' AND created_at >= ?';
    params.push(from);
  }
  if (to) {
    query += ' AND created_at <= ?';
    params.push(to);
  }
  if (user_id) {
    query += ' AND user_id = ?';
    params.push(user_id);
  }
  if (status) {
    query += ' AND status = ?';
    params.push(status);
  }

  query += ' ORDER BY created_at DESC LIMIT 500';
  const sales = db.prepare(query).all(...params);
  res.json(sales);
});

// GET /api/sales/:id
router.get('/:id', (req, res) => {
  const db = getDb();
  const sale = db.prepare('SELECT * FROM sales WHERE id = ?').get(req.params.id);
  if (!sale) return res.status(404).json({ error: 'Venta no encontrada' });

  const items = db.prepare('SELECT * FROM sale_items WHERE sale_id = ?').all(req.params.id);
  res.json({ ...sale, items });
});

// POST /api/sales
router.post('/', (req, res) => {
  const db = getDb();
  const { sale, items } = req.body;

  if (!sale || !items || !items.length) {
    return res.status(400).json({ error: 'Sale y items son requeridos' });
  }

  try {
    db.transaction(() => {
      db.prepare(`
        INSERT INTO sales (id, invoice_number, user_id, customer_name, customer_ruc,
          subtotal, tax_amount, discount_amount, total, payment_method,
          amount_received, change_given, status, cash_register_id, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        sale.id, sale.invoice_number, sale.user_id, sale.customer_name,
        sale.customer_ruc, sale.subtotal, sale.tax_amount, sale.discount_amount,
        sale.total, sale.payment_method, sale.amount_received, sale.change_given,
        sale.status || 'completed', sale.cash_register_id, sale.notes
      );

      const insertItem = db.prepare(`
        INSERT INTO sale_items (sale_id, product_id, product_name, quantity,
          unit_price, discount, tax_rate, subtotal)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const item of items) {
        insertItem.run(
          sale.id, item.product_id, item.product_name, item.quantity,
          item.unit_price, item.discount || 0, item.tax_rate || 0.15, item.subtotal
        );

        // Update stock
        db.prepare('UPDATE products SET current_stock = current_stock - ? WHERE id = ?')
          .run(item.quantity, item.product_id);
      }
    })();

    res.status(201).json({ id: sale.id, invoice_number: sale.invoice_number });
  } catch (err) {
    console.error('Sale creation error:', err);
    res.status(500).json({ error: 'Error al crear venta' });
  }
});

// GET /api/sales/reports/summary
router.get('/reports/summary', (req, res) => {
  const { from, to } = req.query;
  const db = getDb();

  const params = [];
  let dateFilter = '';
  if (from && to) {
    dateFilter = 'WHERE created_at BETWEEN ? AND ?';
    params.push(from, to);
  }

  const summary = db.prepare(`
    SELECT
      COUNT(*) as total_sales,
      COALESCE(SUM(total), 0) as total_revenue,
      COALESCE(SUM(tax_amount), 0) as total_tax,
      COALESCE(SUM(discount_amount), 0) as total_discounts,
      COALESCE(AVG(total), 0) as average_sale
    FROM sales ${dateFilter} ${dateFilter ? 'AND' : 'WHERE'} status = 'completed'
  `).get(...params);

  res.json(summary);
});

module.exports = router;
