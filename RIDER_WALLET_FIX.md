# Rider Wallet Balance Fix

## Issues Found and Fixed

### Issue 1: Double-Counting Delivery Fees in Wallet Stats ✅
**File**: `routes/orders.js` (lines 746-758)

**Problem**:
- The wallet-stats query was summing delivery_fees for ALL orders
- But cash_received already included delivery fees (since total_amount = items + delivery_fee)
- Result: Delivery fees were counted twice for cash orders

**Before**:
```javascript
// Cash received - includes delivery fee
SELECT SUM(total_amount) ... WHERE payment_method='cash'

// Delivery fees - counted separately (WRONG!)
SELECT SUM(delivery_fee) ... (no payment_method filter)
```

**After**:
```javascript
// Cash received - includes delivery fee
SELECT SUM(total_amount) ... WHERE payment_method='cash'

// Delivery fees - only for non-cash orders
SELECT SUM(delivery_fee) ... WHERE payment_method != 'cash'
```

---

### Issue 2: Incorrect Wallet Balance Update ✅
**File**: `routes/orders.js` (lines 1420-1425)

**Problem**:
- When marking payment as 'paid', the code always credited the rider with `total_amount`
- But for card/wallet payments, rider should only get `delivery_fee`
- Only for cash payments should rider get full `total_amount`

**Business Logic**:
- **Cash Orders**: Rider collects money from customer → gets full `total_amount`
- **Card/Wallet Orders**: Customer pays card/wallet directly → rider gets only `delivery_fee`

**Before**:
```javascript
const riderEarnings = order.total_amount; // WRONG - always full amount
```

**After**:
```javascript
const riderEarnings = order.payment_method === 'cash' 
    ? parseFloat(order.total_amount || 0) 
    : parseFloat(order.delivery_fee || 0);
```

---

### Issue 3: Database Schema Support ✅
**File**: `database/schema.sql` (lines 210-228)

**Changes**:
- Updated wallets table to support both `user_id` (customers) and `rider_id` (riders)
- Added `user_type` column to distinguish between customer and rider wallets
- Added foreign key constraints and indexes

**Migration**:
- Run `node migrate-wallets.js` to update existing database

---

## Testing Steps

After deploying these fixes:

1. **For Cash Orders**:
   - Place order with cash payment method
   - Mark as delivered and payment as 'paid'
   - Verify rider wallet increases by `total_amount`

2. **For Card/Wallet Orders**:
   - Place order with card/wallet payment method
   - Mark as delivered and payment as 'paid'
   - Verify rider wallet increases by `delivery_fee` only

3. **Check Wallet Stats**:
   - Daily/Weekly/Monthly earnings should match balance change
   - Should not double-count fees

---

## Files Modified

- ✅ `routes/orders.js` - Fixed wallet stats and balance update logic
- ✅ `database/schema.sql` - Enhanced wallets table structure
- ✅ `migrate-wallets.js` - Enhanced migration script with idempotent checks

---

## Expected Behavior After Fix

**Example**:
- Cash order: Items 100 + Delivery 20 = Total 120
  - Rider earnings: 120 (full amount)
  
- Card order: Items 100 + Delivery 20 = Total 120
  - Rider earnings: 20 (delivery fee only)

- Wallet stats breakdown:
  - Cash received: sum of totals from cash orders only
  - Delivery fees: sum of fees from non-cash orders only
  - **No double-counting**
