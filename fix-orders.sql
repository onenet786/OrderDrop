-- Fix all orders with incorrect totals
-- This script recalculates total_amount = sum(items) + delivery_fee

UPDATE orders o
SET o.total_amount = (
  SELECT COALESCE(SUM(oi.quantity * oi.price), 0) + o.delivery_fee
  FROM order_items oi
  WHERE oi.order_id = o.id
)
WHERE o.id IN (
  SELECT DISTINCT o2.id
  FROM orders o2
  LEFT JOIN order_items oi2 ON o2.id = oi2.order_id
  GROUP BY o2.id
  HAVING (COALESCE(SUM(oi2.quantity * oi2.price), 0) + o2.delivery_fee) != o2.total_amount
);

-- Verify the fix
SELECT 
  o.order_number,
  o.id,
  o.delivery_fee,
  COALESCE(SUM(oi.quantity * oi.price), 0) as items_subtotal,
  o.total_amount as db_total,
  (COALESCE(SUM(oi.quantity * oi.price), 0) + o.delivery_fee) as correct_total,
  CASE 
    WHEN o.total_amount = (COALESCE(SUM(oi.quantity * oi.price), 0) + o.delivery_fee) THEN 'CORRECT'
    ELSE 'WRONG'
  END as status
FROM orders o
LEFT JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id
HAVING items_subtotal + o.delivery_fee != o.total_amount
ORDER BY o.id;
