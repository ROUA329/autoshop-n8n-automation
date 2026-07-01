# Test Cases — AutoShop n8n Automation

Tous les tests ont été réalisés avec **Invoke-RestMethod (PowerShell)** ou **Postman**.  
Emails vérifiés sur **Mailpit** : `http://localhost:8025`  
Données vérifiées dans **PostgreSQL** via `docker exec`.

---

## Workflow 01 — New Order Reception

**Déclencheur :** `POST http://localhost:5678/webhook/new-order`

**PowerShell pour envoyer une commande :**
```powershell
$body = '<coller le JSON ci-dessous>'
Invoke-RestMethod -Uri "http://localhost:5678/webhook/new-order" -Method POST -ContentType "application/json" -Body $body
```

---

### ✅ Commandes valides (5 tests)

#### Test 1 — CMD-3001
```json
{
  "order_code": "CMD-3001",
  "customer": { "full_name": "Sara Ben Ali", "email": "sara@test.com", "phone": "22111222" },
  "items": [{ "product_code": "P001", "product_name": "Black T-shirt", "quantity": 2, "unit_price": 35 }],
  "total_amount": 70,
  "payment_status": "paid"
}
```
**Résultat :** commande enregistrée, client inséré, order items sauvegardés, email confirmation envoyé.

---

#### Test 2 — CMD-3002
```json
{
  "order_code": "CMD-3002",
  "customer": { "full_name": "Lina Mansour", "email": "lina@test.com", "phone": "22555666" },
  "items": [{ "product_code": "P002", "product_name": "White Sneakers", "quantity": 1, "unit_price": 180 }],
  "total_amount": 180,
  "payment_status": "paid"
}
```
**Résultat :** commande enregistrée, client inséré, order items sauvegardés, email confirmation envoyé.

---

#### Test 3 — CMD-3003
```json
{
  "order_code": "CMD-3003",
  "customer": { "full_name": "Amine Trabelsi", "email": "amine@test.com", "phone": "22333444" },
  "items": [{ "product_code": "P003", "product_name": "Blue Backpack", "quantity": 1, "unit_price": 90 }],
  "total_amount": 90,
  "payment_status": "paid"
}
```
**Résultat :** commande enregistrée, client inséré, order items sauvegardés, email confirmation envoyé.

---

#### Test 4 — CMD-3004
```json
{
  "order_code": "CMD-3004",
  "customer": { "full_name": "Mariem", "email": "mariem@test.com", "phone": "22123456" },
  "items": [{ "product_code": "P004", "product_name": "Smart Watch", "quantity": 1, "unit_price": 220 }],
  "total_amount": 220,
  "payment_status": "paid"
}
```
**Résultat :** commande enregistrée, stock bas détecté (P004 : 5 → 4, minimum = 3), alerte stock bas envoyée.

---

#### Test 5 — CMD-3005
```json
{
  "order_code": "CMD-3005",
  "customer": { "full_name": "Sara Ben Ali", "email": "sara@test.com", "phone": "22111222" },
  "items": [{ "product_code": "P005", "product_name": "Wireless Mouse", "quantity": 2, "unit_price": 45 }],
  "total_amount": 90,
  "payment_status": "paid"
}
```
**Résultat :** commande enregistrée, client inséré, order items sauvegardés, email confirmation envoyé.

---

### ❌ Commandes invalides (3 tests)

#### Test ERR1 — Email manquant
```json
{
  "order_code": "CMD-ERR1",
  "customer": { "full_name": "Ahmed", "phone": "22999888" },
  "items": [{ "product_code": "P001", "quantity": 1, "unit_price": 35 }],
  "total_amount": 35,
  "payment_status": "paid"
}
```
**Résultat attendu :**
```json
{ "valid": false, "errors": ["Customer email is required"] }
```
Commande non enregistrée, erreur journalisée dans `automation_logs`.

---

#### Test ERR2 — Items vide
```json
{
  "order_code": "CMD-ERR2",
  "customer": { "full_name": "Ahmed", "email": "ahmed@test.com", "phone": "22999888" },
  "items": [],
  "total_amount": 35,
  "payment_status": "paid"
}
```
**Résultat attendu :**
```json
{ "valid": false, "errors": ["Order must contain at least one item"] }
```

---

#### Test ERR3 — Total = 0
```json
{
  "order_code": "CMD-ERR3",
  "customer": { "full_name": "Ahmed", "email": "ahmed@test.com", "phone": "22999888" },
  "items": [{ "product_code": "P001", "quantity": 1, "unit_price": 35 }],
  "total_amount": 0,
  "payment_status": "paid"
}
```
**Résultat attendu :**
```json
{ "valid": false, "errors": ["Total amount must be greater than 0"] }
```

---

## Workflow 06 — Abandoned Cart Relance

**Déclencheur :** `POST http://localhost:5678/webhook/cart-created`

### Test — Panier abandonné CART-2001
```powershell
$body = '{
  "cart_code": "CART-2001",
  "customer_name": "Amine Trabelsi",
  "customer_email": "amine@test.com",
  "total_amount": 180
}'
Invoke-RestMethod -Uri "http://localhost:5678/webhook/cart-created" -Method POST -ContentType "application/json" -Body $body
```

**Déroulement :**
1. Le panier est enregistré en base avec `status = 'open'`
2. Le workflow attend (4h en production, 1 minute en mode test)
3. n8n vérifie si le panier est toujours `open`
4. Si oui → notification Telegram de relance envoyée au client

**Résultat attendu :**
- Notification Telegram reçue sur le bot avec un message de relance du type :
  *"Vous avez laissé des articles dans votre panier. Total : 180 TND. Complétez votre commande avant qu'il soit trop tard !"*
- Statut du panier mis à jour dans la table `carts`

**Vérifier en base :**
```sql
SELECT * FROM carts WHERE cart_code = 'CART-2001';
```

---

## Workflow 08 — Livreur Email Trigger

> Ce workflow est le plus complexe. Il simule le flux réel : le livreur envoie un email depuis son compte Gmail pour confirmer l'état de livraison → n8n lit cet email automatiquement → met à jour la base → envoie une notification Telegram au client.

### Comment ça fonctionne

```
Livreur envoie email Gmail
        ↓
n8n lit l'email (IMAP trigger)
        ↓
Extrait : order_code + delivery_status
        ↓
Cherche la commande dans PostgreSQL
        ↓
Vérifie si le statut est déjà identique
        ↓
Non → Met à jour delivery_status en base
     → Envoie notification Telegram au client
     → Envoie email de confirmation au livreur
Oui → Envoie email "déjà mis à jour" au livreur
```

### Format de l'email envoyé par le livreur

Le livreur envoie un email Gmail avec ce format exact :

**Sujet :** libre (ex: `livraison CMD-3002`)

**Corps :**
```
order_code: CMD-3002
delivery_status: shipped
```
ou
```
order_code: CMD-3002
delivery_status: delivered
```

### Test 8.1 — Statut "shipped" (en cours de livraison)

1. Le livreur envoie un email Gmail avec :
   ```
   order_code: CMD-3002
   delivery_status: shipped
   ```
2. n8n détecte l'email (polling IMAP toutes les minutes)
3. Résultat attendu :
   - `delivery_status` de CMD-3002 mis à jour à `shipped` dans la table `orders`
   - Notification Telegram reçue par le client : *"Votre commande CMD-3002 est en cours de livraison"*
   - Email de confirmation envoyé au livreur 

**Vérifier en base :**
```sql
SELECT order_code, delivery_status, updated_at FROM orders WHERE order_code = 'CMD-3002';
```

---

### Test 8.2 — Statut "delivered" (livré)

1. Le livreur envoie un deuxième email Gmail :
   ```
   order_code: CMD-3002
   delivery_status: delivered
   ```
2. Résultat attendu :
   - `delivery_status` mis à jour à `delivered`
   - Nouvelle notification Telegram au client : *"Votre commande CMD-3002 a été livrée"*
   - Email de confirmation au livreur 

---

### Test 8.3 — Statut déjà identique (doublon)

1. Le livreur renvoie le même email avec `delivered` (déjà mis à jour)
2. Résultat attendu :
   - Le node **"Is Already Updated"** détecte que le statut est identique
   - Email "Notify Livreur Already Updated" envoyé au livreur
   - Aucune mise à jour en base, aucun Telegram envoyé

---

## Vérifications après chaque test

| Vérification | Comment |
|---|---|
| Commande en base | `SELECT * FROM orders WHERE order_code = 'CMD-XXXX';` |
| Items en base | `SELECT * FROM order_items WHERE order_id = X;` |
| Stock mis à jour | `SELECT product_code, stock_quantity FROM products;` |
| Email client | Mailpit → `http://localhost:8025` |
| Email log | `SELECT * FROM email_logs ORDER BY created_at DESC LIMIT 5;` |
| Notification Telegram | Vérifier le chat Telegram du bot |
| Erreurs | `SELECT * FROM automation_logs ORDER BY created_at DESC LIMIT 5;` |