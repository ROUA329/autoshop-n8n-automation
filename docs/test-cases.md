# Test Cases — AutoShop Automation

## Workflow 01 - New Order Reception

---

### Valid Orders (5 tests)

#### Test 1 — CMD-3001
- Customer: Sara Ben Ali / sara@test.com
- Product: P001 Black T-shirt x2 / 35 TND
- Total: 70 TND
- Result: Order saved, customer inserted, order items saved

#### Test 2 — CMD-3002
- Customer: Lina Mansour / lina@test.com
- Product: P002 White Sneakers x1 / 180 TND
- Total: 180 TND
- Result: Order saved, customer inserted, order items saved

#### Test 3 — CMD-3003
- Customer: Amine Trabelsi / amine@test.com
- Product: P003 Blue Backpack x1 / 90 TND
- Total: 90 TND
- Result:  Order saved, customer inserted, order items saved

#### Test 4 — CMD-3004
- Customer: Mariem / mariem@test.com
- Product: P004 Smart Watch x1 / 220 TND
- Total: 220 TND
- Result:  Order saved, customer inserted, order items saved

#### Test 5 — CMD-3005
- Customer: Sara Ben Ali / sara@test.com
- Product: P005 Wireless Mouse x2 / 45 TND
- Total: 90 TND
- Result:  Order saved, customer inserted, order items saved

---

###  Invalid Orders (3 tests)

#### Test ERR1 — Email manquant
- Input: customer sans email
- Expected: valid: false, errors: Customer email is required
- Result:  Error returned, order not saved

#### Test ERR2 — Items vide
- Input: items: []
- Expected: valid: false, errors: Order must contain at least one item
- Result:  Error returned, order not saved

#### Test ERR3 — Total = 0
- Input: total_amount: 0
- Expected: valid: false, errors: Total amount must be greater than 0
- Result:  Error returned, order not saved