-- Fix all orders with incorrect totals
-- This script recalculates total_amount = sum(items) + delivery_fee

UPDATE orders
SET total_amount = (
  COALESCE((
    SELECT SUM(quantity * price)
    FROM order_items
    WHERE order_items.order_id = orders.id
  ), 0) + delivery_fee
)
WHERE id IN (
  SELECT DISTINCT order_id FROM order_items
)
AND total_amount != (
  COALESCE((
    SELECT SUM(quantity * price)
    FROM order_items
    WHERE order_items.order_id = orders.id
  ), 0) + delivery_fee
);

-- Fix orders with no items (delivery fee only)
UPDATE orders
SET total_amount = delivery_fee
WHERE id NOT IN (
  SELECT DISTINCT order_id FROM order_items
);

-- Verify the fix
SELECT 
  o.order_number,
  o.id,
  o.delivery_fee,
  COALESCE(oi_sum.items_total, 0) as items_subtotal,
  o.total_amount as db_total,
  (COALESCE(oi_sum.items_total, 0) + o.delivery_fee) as correct_total,
  CASE 
    WHEN o.total_amount = (COALESCE(oi_sum.items_total, 0) + o.delivery_fee) THEN 'CORRECT'
    ELSE 'WRONG'
  END as status
FROM orders o
LEFT JOIN (
  SELECT order_id, SUM(quantity * price) as items_total
  FROM order_items
  GROUP BY order_id
) oi_sum ON o.id = oi_sum.order_id
WHERE (COALESCE(oi_sum.items_total, 0) + o.delivery_fee) != o.total_amount
ORDER BY o.id;
