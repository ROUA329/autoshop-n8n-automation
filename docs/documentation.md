# AutoShop n8n Automation — Documentation Technique Complète

**Projet :** AutoShop Automation System  
**Stagiaire :** ROUA Hamrouni  
**Période :** Juin – Juillet 2026  
**Outils :** n8n · Docker · PostgreSQL · Mailpit · Metabase · Telegram Bot · Gmail IMAP

---

## Table des matières

1. [Architecture générale](#1-architecture-générale)
2. [Workflow 01 — New Order Reception](#2-workflow-01--new-order-reception)
3. [Workflow 02 — Stock Update](#3-workflow-02--stock-update)
4. [Workflow 03 — Customer Email Confirmation](#4-workflow-03--customer-email-confirmation)
5. [Workflow 04 — Telegram Notification](#5-workflow-04--telegram-notification)
6. [Workflow 05 — Delivery Status Update](#6-workflow-05--delivery-status-update)
7. [Workflow 06 — Abandoned Cart Relance](#7-workflow-06--abandoned-cart-relance)
8. [Workflow 07 — Order Confirmation (Telegram Callback)](#8-workflow-07--order-confirmation-telegram-callback)
9. [Workflow 08 — Livreur Email Trigger](#9-workflow-08--livreur-email-trigger)
10. [Workflow 09 — Daily Sales Report](#10-workflow-09--daily-sales-report)

---

## 1. Architecture générale

```
Client / Postman
      │
      ▼ POST /new-order
┌─────────────┐
│  01 - New   │──► 03 - Customer Email Confirmation (Mailpit)
│   Order     │──► 04 - Telegram Notification (client confirme)
│ Reception   │
└─────────────┘
      │
      ▼ (après confirmation Telegram)
┌─────────────┐
│  07 - Order │──► 02 - Stock Update ──► Alerte email stock bas
│Confirmation │──► Telegram (confirmed / cancelled)
└─────────────┘

POST /delivery-update
┌─────────────┐
│  05 -       │──► Telegram (processing / shipped / delivered)
│  Delivery   │──► Save email log
│  Status     │
└─────────────┘

Gmail IMAP (livreur envoie email)
┌─────────────┐
│  08 -       │──► Update DB ──► Telegram client ──► Email livreur
│  Livreur    │
│  Email      │
└─────────────┘

POST /cart-created
┌─────────────┐
│  06 -       │──► Wait ──► Check ──► Telegram relance
│  Abandoned  │
│  Cart       │
└─────────────┘

Schedule (18:00)
┌─────────────┐
│  09 - Daily │──► Email rapport manager (Mailpit)
│  Report     │
└─────────────┘

PostgreSQL ◄──────────── tous les workflows lisent/écrivent
Metabase   ──────────── lit PostgreSQL pour le dashboard
```

---

## 2. Workflow 01 — New Order Reception

**Objectif :** Recevoir une commande via Webhook, valider les données, insérer le client, la commande et les articles en base, puis déclencher l'email de confirmation et la notification Telegram.

**Déclencheur :** `POST http://localhost:5678/webhook/new-order`

**Flux des nodes :**
```
Webhook → Validate Data → If
                           ├── true  → Insert Customer → Insert Order → Insert Order Items
                           │          → Save Order Items → Prepare Telegram Data
                           │          → Call '04 - Telegram Notification'
                           │          → Prepare Email Data → Call Email Confirmation
                           │          → Respond to Webhook (success)
                           └── false → Respond to Webhook1 (error)
```

---

### Node 1 : Webhook

| Paramètre | Valeur |
|---|---|
| Type | Webhook |
| Méthode HTTP | POST |
| Path | `new-order` |
| Response Mode | Using Respond to Webhook node |

**Rôle :** Point d'entrée du système. Reçoit les commandes JSON depuis le site e-commerce, Postman, ou curl.

---

### Node 2 : Validate Data (Code)

**Rôle :** Vérifie que tous les champs obligatoires sont présents et valides avant d'enregistrer quoi que ce soit en base.

```javascript
const order = $json.body || $json;
const errors = [];

if (!order.order_code) {
  errors.push("Order code is required");
}
if (!order.customer || !order.customer.full_name) {
  errors.push("Customer full name is required");
}
if (!order.customer || !order.customer.email) {
  errors.push("Customer email is required");
}
if (!order.items || order.items.length === 0) {
  errors.push("Order must contain at least one item");
}
if (!order.total_amount || order.total_amount <= 0) {
  errors.push("Total amount must be greater than 0");
}

if (errors.length > 0) {
  return [{ json: { valid: false, errors: errors } }];
}
return [{ json: { valid: true, order: order } }];
```

**Règles de validation :**
- `order_code` obligatoire
- `customer.full_name` obligatoire
- `customer.email` obligatoire
- `items` non vide
- `total_amount` > 0

---

### Node 3 : If

**Rôle :** Branche le flux selon le résultat de la validation.

| Condition | Branche |
|---|---|
| `valid === "true"` | true → insertion en base |
| sinon | false → réponse d'erreur |

---

### Node 4 : Insert Customer (PostgreSQL)

**Rôle :** Insère le client en base et retourne son ID pour le lier à la commande.

```sql
INSERT INTO customers (full_name, email, phone)
VALUES (
  '{{ $json.order.customer.full_name }}',
  '{{ $json.order.customer.email }}',
  '{{ $json.order.customer.phone }}'
)
RETURNING id;
```

---

### Node 5 : Insert Order (PostgreSQL)

**Rôle :** Insère la commande avec le statut `confirmed` et retourne l'ID de commande.

```sql
INSERT INTO orders (
  order_code, customer_id, total_amount,
  status, payment_status, delivery_status
)
VALUES (
  '{{ $('Validate Data').item.json.order.order_code }}',
  {{ $json.id }},
  {{ $('Validate Data').item.json.order.total_amount }},
  'confirmed',
  '{{ $('Validate Data').item.json.order.payment_status }}',
  'not_shipped'
)
RETURNING id;
```

---

### Node 6 : Insert Order Items (Code)

**Rôle :** Transforme le tableau `items` de la commande en plusieurs items séparés pour les traiter un par un.

```javascript
const items = $('Validate Data').item.json.order.items;
const orderId = $json.id;
const results = [];

for (const item of items) {
  results.push({
    json: {
      order_id: orderId,
      product_code: item.product_code,
      quantity: item.quantity,
      unit_price: item.unit_price,
      line_total: item.quantity * item.unit_price
    }
  });
}
return results;
```

---

### Node 7 : Save Order Items (PostgreSQL)

**Rôle :** Pour chaque item, insère dans `order_items` en faisant un JOIN sur `products` pour récupérer le `product_id`.

```sql
INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total)
SELECT
  {{ $json.order_id }},
  id,
  {{ $json.quantity }},
  {{ $json.unit_price }},
  {{ $json.line_total }}
FROM products
WHERE product_code = '{{ $json.product_code }}'
RETURNING id, product_id, '{{ $json.product_code }}' as product_code,
          {{ $json.quantity }} as ordered_quantity;
```

---

### Node 8 : Prepare Telegram Data (Set)

**Rôle :** Prépare les champs nécessaires pour le workflow 04 (Telegram).

| Champ | Valeur |
|---|---|
| order_code | `$('Validate Data').item.json.order.order_code` |
| customer_name | `$('Validate Data').item.json.order.customer.full_name` |
| customer_email | `$('Validate Data').item.json.order.customer.email` |
| total_amount | `$('Validate Data').item.json.order.total_amount` |
| payment_status | `$('Validate Data').item.json.order.payment_status` |

---

### Node 9 : Call '04 - Telegram Notification' (Execute Workflow)

**Rôle :** Appelle le workflow 04 pour envoyer la notification Telegram au gestionnaire afin qu'il confirme ou annule la commande.

---

### Node 10 : Prepare Email Data (Set)

**Rôle :** Prépare les champs pour le workflow 03 (email de confirmation client).

---

### Node 11 : Call Email Confirmation (Execute Workflow)

**Rôle :** Appelle le workflow 03 pour envoyer l'email de confirmation au client.

---

### Node 12 : Respond to Webhook (success)

```json
{ "status": "success", "message": "Order received" }
```

### Node 13 : Respond to Webhook1 (error)

```json
{ "status": "error", "valid": false, "errors": "..." }
```

---

## 3. Workflow 02 — Stock Update

**Objectif :** Décrémenter le stock du produit commandé, journaliser le mouvement, et envoyer une alerte email si le stock passe sous le seuil minimum.

**Déclencheur :** Appelé par le workflow 07 (Order Confirmation) via Execute Workflow.

**Flux des nodes :**
```
When Executed by Another Workflow
  → Read Product Stock
  → Calculate New Stock
  → Update Product Stock
  → Save Stock Movement
  → Check Low Stock
      ├── true → Send Low Stock Alert (email)
      └── false → (fin)
```

---

### Node 1 : When Executed by Another Workflow

**Rôle :** Trigger qui permet à ce workflow d'être appelé depuis un autre workflow (ici le workflow 07).

---

### Node 2 : Read Product Stock (PostgreSQL)

**Rôle :** Lit le stock actuel du produit concerné.

```sql
SELECT id, product_code, product_name, stock_quantity, minimum_stock
FROM products
WHERE product_code = '{{ $json.product_code }}';
```

---

### Node 3 : Calculate New Stock (Code)

**Rôle :** Calcule le nouveau stock et détermine si le produit est en stock bas.

```javascript
const product = $json;
const triggerData = $('When Executed by Another Workflow').item.json;
const orderedQuantity = Number(triggerData.ordered_quantity || triggerData.quantity || 1);
const oldStock = Number(product.stock_quantity);
const newStock = oldStock - orderedQuantity;
const minimumStock = Number(product.minimum_stock);

return [{
  json: {
    product_id: product.id,
    product_code: product.product_code,
    product_name: product.product_name,
    old_stock: oldStock,
    ordered_quantity: orderedQuantity,
    new_stock: newStock,
    minimum_stock: minimumStock,
    low_stock: newStock <= minimumStock   // true si stock bas
  }
}];
```

---

### Node 4 : Update Product Stock (PostgreSQL)

```sql
UPDATE products
SET stock_quantity = {{ $json.new_stock }}
WHERE id = {{ $json.product_id }};
```

---

### Node 5 : Save Stock Movement (PostgreSQL)

**Rôle :** Journalise chaque mouvement de stock dans la table `stock_movements`.

```sql
INSERT INTO stock_movements (
  product_id, movement_type, quantity,
  old_stock, new_stock, reason
)
VALUES (
  {{ $('Calculate New Stock').item.json.product_id }},
  'sale',
  {{ $('Calculate New Stock').item.json.ordered_quantity }},
  {{ $('Calculate New Stock').item.json.old_stock }},
  {{ $('Calculate New Stock').item.json.new_stock }},
  'Stock updated after customer order'
);
```

---

### Node 6 : Check Low Stock (IF)

**Condition :** `low_stock === true`

---

### Node 7 : Send Low Stock Alert (Email SMTP)

**Rôle :** Envoie un email d'alerte au manager via Mailpit si le stock est bas.

| Champ | Valeur |
|---|---|
| From | `autoshop@test.com` |
| To | `manager@test.com` |
| Sujet | `Low Stock Alert - {product_name}` |
| Credential | SMTP Mailpit (host: mailpit, port: 1025) |

**Corps de l'email :**
```
Hello,
The product {product_name} is now low in stock.
Old stock: {old_stock}
New stock: {new_stock}
Minimum stock: {minimum_stock}
Please prepare a restocking action.
AutoShop Automation
```

---

## 4. Workflow 03 — Customer Email Confirmation

**Objectif :** Envoyer un email de confirmation au client après une commande réussie.

**Déclencheur :** Appelé par le workflow 01 via Execute Workflow.

**Flux des nodes :**
```
When Executed by Another Workflow
  → Prepare Email
  → Send Confirmation Email
  → Save Email Log
```

---

### Node 1 : Prepare Email (Code)

**Rôle :** Normalise les données d'entrée selon la source (différents formats possibles).

```javascript
const data = $json;
return [{
  json: {
    customer_email: data.customer_email || data.customer?.email,
    customer_name: data.customer_name || data.customer?.full_name,
    order_code: data.order_code || data.order?.order_code,
    total_amount: data.total_amount || data.order?.total_amount
  }
}];
```

---

### Node 2 : Send Confirmation Email (SMTP)

| Champ | Valeur |
|---|---|
| From | `autoshop@test.com` |
| To | `{{ $json.customer_email }}` |
| Sujet | `Your order {{ $json.order_code }} is confirmed` |

**Corps :**
```
Hello {{ customer_name }},
Thank you for your order.
Your order number is: {{ order_code }}
Total amount: {{ total_amount }} TND
We will notify you when your order is shipped.
Best regards, AutoShop Team
```

---

### Node 3 : Save Email Log (PostgreSQL)

```sql
INSERT INTO email_logs (recipient_email, subject, email_type, status)
VALUES (
  '{{ $json.customer_email }}',
  'Your order {{ $json.order_code }} is confirmed',
  'order_confirmation',
  'sent'
);
```

---

## 5. Workflow 04 — Telegram Notification

**Objectif :** Envoyer une notification Telegram au gestionnaire avec les boutons ✅ YES / ❌ NO pour confirmer ou annuler une nouvelle commande.

**Déclencheur :** Appelé par le workflow 01 via Execute Workflow.

**Flux des nodes :**
```
When Executed by Another Workflow
  → Send a text message (Telegram avec boutons inline)
```

---

### Node 1 : Send a text message (Telegram)

| Champ | Valeur |
|---|---|
| Chat ID | `8471701647` |
| Reply Markup | Inline Keyboard |
| Credential | AutoShop Telegram Bot |

**Message envoyé :**
```
New Order Received!

Order: {{ order_code }}
Customer: {{ customer_name }}
Email: {{ customer_email }}
Total: {{ total_amount }} TND
Payment: {{ payment_status }}

Do you confirm this order?
Please reply with:
✅ YES to confirm
❌ NO to cancel
```

**Boutons inline :**
- `✅ YES` → callback_data: `confirm_{order_code}`
- `❌ NO` → callback_data: `cancel_{order_code}`

> Ces callbacks sont traités par le workflow 07.

---

## 6. Workflow 05 — Delivery Status Update

**Objectif :** Mettre à jour le statut de livraison d'une commande via Webhook, et envoyer une notification Telegram personnalisée selon le statut.

**Déclencheur :** `POST http://localhost:5678/webhook/delivery-update`

**Flux des nodes :**
```
Webhook → Find Order → Update Delivery Status → Check Delivery Status
                                                    ├── processing → Send Processing Telegram
                                                    ├── shipped   → Send Shipped Telegram → Save Log
                                                    └── delivered → Send Delivered Telegram → Save Log
                                                                     → Respond to Webhook
```

---

### Node 1 : Find Order (PostgreSQL)

```sql
SELECT orders.id, orders.order_code, orders.delivery_status,
       customers.full_name, customers.email
FROM orders
JOIN customers ON customers.id = orders.customer_id
WHERE orders.order_code = '{{ $json.body.order_code }}'
```

---

### Node 2 : Update Delivery Status (PostgreSQL)

```sql
UPDATE orders
SET delivery_status = '{{ $('Webhook').item.json.body.delivery_status }}',
    updated_at = CURRENT_TIMESTAMP
WHERE order_code = '{{ $('Webhook').item.json.body.order_code }}'
RETURNING id, order_code, delivery_status
```

---

### Node 3 : Check Delivery Status (Switch)

**Rôle :** Route vers 3 branches selon la valeur de `delivery_status`.

| Valeur | Branche |
|---|---|
| `processing` | Send Processing Telegram |
| `shipped` | Send Shipped Telegram |
| `delivered` | Send Delivered Telegram |

---

### Node 4a : Send Processing Telegram

```
📦 Your order is being prepared!
Order: {{ order_code }}
Customer: {{ full_name }}
Our team is preparing your package.
You will be notified when it ships.
AutoShop Team
```

### Node 4b : Send Shipped Telegram

```
Your order has been shipped!
Order: {{ order_code }}
Customer: {{ full_name }}
Carrier: {{ carrier }}
Tracking number: {{ tracking_code }}
Use this tracking number to follow your package.
AutoShop Team
```

### Node 4c : Send Delivered Telegram

```
Your order has been delivered!
Order: {{ order_code }}
Customer: {{ full_name }}
Thank you for shopping with us!
AutoShop Team
```

---

### Node 5 : Save Log (PostgreSQL)

```sql
INSERT INTO email_logs (recipient_email, subject, email_type, status)
VALUES (
  '{{ $json.customer_email }}',
  'Delivery update for order {{ $json.order_code }}',
  'delivery_notification',
  'sent'
)
```

---

### Réponse Webhook

```json
{
  "status": "success",
  "message": "Delivery status updated and customer notified via Telegram"
}
```

---

## 7. Workflow 06 — Abandoned Cart Relance

**Objectif :** Enregistrer un panier, attendre un délai, vérifier si le panier est toujours ouvert, et envoyer une notification Telegram de relance si c'est le cas.

**Déclencheur :** `POST http://localhost:5678/webhook/cart-created`

**Flux des nodes :**
```
Webhook → Save Cart → Wait (1 min test / 4h prod)
  → Check Cart Status → Is Cart Still Open
      ├── true  → Send Telegram Relance → Update Cart Status → Respond to Webhook
      └── false → (fin, panier déjà fermé)
```

---

### Node 1 : Save Cart (PostgreSQL)

```sql
INSERT INTO carts (cart_code, customer_email, customer_name, total_amount, status)
VALUES (
  '{{ $json.body.cart_code }}',
  '{{ $json.body.customer_email }}',
  '{{ $json.body.customer_name }}',
  {{ $json.body.total_amount }},
  'open'
)
RETURNING id, cart_code, customer_name, customer_email, total_amount, status
```

---

### Node 2 : Wait

| Mode test | Mode production |
|---|---|
| 1 minute | 4 heures |

---

### Node 3 : Check Cart Status (PostgreSQL)

```sql
SELECT id, cart_code, customer_name, customer_email, total_amount, status
FROM carts
WHERE cart_code = '{{ $('Save Cart').item.json.cart_code }}'
AND status = 'open'
```

---

### Node 4 : Is Cart Still Open (IF)

**Condition :** `status === "open"`

---

### Node 5 : Send Telegram Relance (Telegram)

```
You left something in your cart!
Customer: {{ customer_name }}
Cart total: {{ total_amount }} TND
Complete your order before the products are sold out!
Go back to your cart and finalize your purchase now.
AutoShop Team
```

---

### Node 6 : Update Cart Status (PostgreSQL)

```sql
UPDATE carts
SET status = 'relance_sent', updated_at = CURRENT_TIMESTAMP
WHERE cart_code = '{{ $('Save Cart').item.json.cart_code }}'
RETURNING id, cart_code, status
```

---

## 8. Workflow 07 — Order Confirmation (Telegram Callback)

**Objectif :** Recevoir la réponse du gestionnaire depuis Telegram (✅ YES / ❌ NO), confirmer ou annuler la commande en base, puis déclencher la mise à jour du stock si confirmée.

**Déclencheur :** `POST http://localhost:5678/webhook/telegram-confirmation` (Telegram envoie le callback ici via le bot webhook).

**Flux des nodes :**
```
Webhook → Extract Callback Data → Is Confirmed (type = client_confirmation ?)
  ├── true  → Is Really Confirmed (confirmed = true ?)
  │     ├── true  → Confirm Order → Get Order Items
  │     │           → Send Confirmation Telegram + Call '02 - Stock Update'
  │     │           → Respond to Webhook
  │     └── false → Send Cancellation Telegram → Respond to Webhook1
  └── false → (autre type, ignoré)
```

---

### Node 1 : Extract Callback Data (Code)

**Rôle :** Analyse le message Telegram reçu. Gère deux cas : réponse aux boutons inline (callback_query) ou message texte simple.

```javascript
const body = $json.body;

if (body.callback_query) {
  const callbackQuery = body.callback_query;
  const callbackData = callbackQuery.data;
  const chatId = callbackQuery.message.chat.id;
  const messageId = callbackQuery.message.message_id;
  const isConfirmed = callbackData.startsWith('confirm_');
  const orderCode = callbackData.replace('confirm_', '').replace('cancel_', '');

  return [{
    json: {
      type: 'client_confirmation',
      order_code: orderCode,
      chat_id: chatId,
      message_id: messageId,
      confirmed: isConfirmed,
      callback_data: callbackData
    }
  }];
}

if (body.message) {
  const message = body.message;
  const text = message.text;
  const chatId = message.chat.id;
  const parts = text.trim().split(' ');
  const status = parts[0].toLowerCase();
  const orderCode = parts[1];

  return [{
    json: {
      type: 'delivery_update',
      delivery_status: status,
      order_code: orderCode,
      chat_id: chatId
    }
  }];
}

return [{ json: { type: 'unknown', raw: body } }];
```

---

### Node 2 : Is Confirmed (IF)

**Condition :** `type === "client_confirmation"`

---

### Node 3 : Is Really Confirmed (IF)

**Condition :** `confirmed === true`

---

### Node 4 : Confirm Order (PostgreSQL)

```sql
UPDATE orders
SET status = 'confirmed', updated_at = CURRENT_TIMESTAMP
WHERE order_code = '{{ $json.order_code }}'
RETURNING id, order_code, status, customer_id
```

---

### Node 5 : Get Order Items (PostgreSQL)

**Rôle :** Récupère les articles de la commande pour les passer au workflow 02 (Stock Update).

```sql
SELECT order_items.quantity, products.product_code, products.product_name,
       products.stock_quantity, products.minimum_stock, products.id as product_id
FROM order_items
JOIN products ON products.id = order_items.product_id
WHERE order_items.order_id = {{ $json.id }}
```

---

### Node 6 : Send Confirmation Telegram

```
✅ Thank you for confirming!
Order: {{ order_code }}
Your order has been confirmed and will be shipped soon!
We will notify you when your package is on its way.
AutoShop Team
```

### Node 7 : Send Cancellation Telegram

```
❌ Order Cancelled
Order: {{ order_code }}
Your order has been cancelled. No charges will be made.
If you change your mind, feel free to order again!
AutoShop Team
```

---

### Node 8 : Call '02 - Stock Update' (Execute Workflow)

**Rôle :** Déclenche le workflow 02 pour chaque article de la commande confirmée.

---

## 9. Workflow 08 — Livreur Email Trigger

**Objectif :** Le livreur envoie un email Gmail avec le statut de livraison et le code commande → n8n lit l'email automatiquement → met à jour la base → envoie une notification Telegram au client → envoie un email de confirmation au livreur.

**Déclencheur :** Email Trigger IMAP (Gmail, polling automatique)

**Flux des nodes :**
```
Email Trigger Livreur → Extract Email Data → Find Order → Is Already Updated
  ├── true  → Notify Livreur Already Updated (email)
  └── false → Update Delivery Status → Send Telegram to Client → Send Email to Livreur
```

---

### Node 1 : Email Trigger Livreur (IMAP)

**Rôle :** Surveille une boîte Gmail et déclenche le workflow à chaque nouvel email reçu.

| Paramètre | Valeur |
|---|---|
| Type | Email Read IMAP |
| Credential | IMAP account (Gmail + App Password) |

---

### Node 2 : Extract Email Data (Code)

**Rôle :** Extrait le statut de livraison et le code commande depuis le sujet de l'email.

**Format attendu du sujet :** `shipped CMD-3002` ou `delivered CMD-3002`

```javascript
const email = $json;
const subject = email.subject || '';
const content = subject.toLowerCase().trim();
const parts = content.split(' ');

const status = parts[0];                                  // shipped ou delivered
const orderCode = parts[1] ? parts[1].toUpperCase() : ''; // CMD-3002

const fromEmail = email.from || email.metadata?.from || 'livreur@unknown.com';

return [{
  json: {
    delivery_status: status,
    order_code: orderCode,
    livreur_email: typeof fromEmail === 'string' ? fromEmail : 'livreur@unknown.com',
    raw_subject: subject
  }
}];
```

---

### Node 3 : Find Order (PostgreSQL)

**Rôle :** Récupère la commande et son statut actuel depuis la base.

```sql
SELECT orders.id, orders.order_code, orders.delivery_status,
       customers.full_name, customers.email AS livreur_email
FROM orders
JOIN customers ON customers.id = orders.customer_id
WHERE orders.order_code = '{{ $json.order_code }}'
```

---

### Node 4 : Is Already Updated (IF)

**Rôle :** Vérifie si le statut en base est déjà identique au statut envoyé par le livreur, pour éviter les doublons.

**Condition :**
```
$json.delivery_status (base) === $('Extract Email Data').item.json.delivery_status (email)
```

| Résultat | Branche |
|---|---|
| true (déjà identique) | → Notify Livreur Already Updated |
| false (statut différent) | → Update Delivery Status |

---

### Node 5a : Notify Livreur Already Updated (Email)

**Rôle :** Informe le livreur que le statut est déjà à jour, sans modifier la base.

```
Bonjour,
La commande {{ order_code }} est déjà au statut : {{ delivery_status }}
Aucune action supplémentaire n'a été effectuée.
AutoShop Team
```

---

### Node 5b : Update Delivery Status (PostgreSQL)

```sql
UPDATE orders
SET delivery_status = '{{ $('Extract Email Data').item.json.delivery_status }}',
    updated_at = CURRENT_TIMESTAMP
WHERE order_code = '{{ $('Extract Email Data').item.json.order_code }}'
RETURNING id, order_code, delivery_status
```

---

### Node 6 : Send Telegram to Client (Telegram)

**Rôle :** Notifie le client sur Telegram avec un message adapté au statut.

```javascript
// Message conditionnel selon le statut
delivery_status === 'shipped'
  ? '🚚 Your order has been shipped and is on its way!'
  : '✅ Your order has been delivered! Thank you for shopping with us!'
```

**Message complet :**
```
🚚 / ✅ Delivery Update!
Order: {{ order_code }}
Customer: {{ full_name }}
[Message selon statut]
AutoShop Team
```

---

### Node 7 : Send Email to Livreur (Email SMTP)

**Rôle :** Confirme au livreur que son email a bien été traité et que le client a été notifié.

```
Hello,
The delivery status has been updated successfully.
Order: {{ order_code }}
New Status: {{ delivery_status }}
The customer has been notified via Telegram.
AutoShop System
```

---

## 10. Workflow 09 — Daily Sales Report

**Objectif :** Générer et envoyer automatiquement un rapport de ventes complet chaque jour à 18h00.

**Déclencheur :** Schedule Trigger — tous les jours à 18:00

**Flux des nodes :**
```
Schedule Trigger
  → Get Daily Orders
  → Get Orders by Status
  → Get Top Products
  → Get Low Stock Products
  → Send Report to Manager (email)
  → Save Log
```

---

### Node 1 : Schedule Trigger

| Paramètre | Valeur |
|---|---|
| Type | Schedule Trigger |
| Heure | 18:00 tous les jours |

---

### Node 2 : Get Daily Orders (PostgreSQL)

```sql
SELECT
  COUNT(*) AS total_orders,
  COALESCE(SUM(total_amount), 0) AS total_sales
FROM orders;
```

---

### Node 3 : Get Orders by Status (PostgreSQL)

```sql
SELECT status, COUNT(*) AS total
FROM orders
GROUP BY status;
```

---

### Node 4 : Get Top Products (PostgreSQL)

```sql
SELECT
  p.product_name,
  SUM(oi.quantity) AS total_sold,
  SUM(oi.line_total) AS total_revenue
FROM order_items oi
JOIN products p ON p.id = oi.product_id
JOIN orders o ON o.id = oi.order_id
GROUP BY p.product_name
ORDER BY total_sold DESC
LIMIT 5;
```

---

### Node 5 : Get Low Stock Products (PostgreSQL)

```sql
SELECT product_name, stock_quantity, minimum_stock
FROM products
WHERE stock_quantity <= minimum_stock
ORDER BY stock_quantity ASC;
```

---

### Node 6 : Send Report to Manager (Email SMTP)

| Champ | Valeur |
|---|---|
| From | `autoshop@store.com` |
| To | `manager@autoshop.com` |
| Sujet | `📊 Daily Sales Report - {date}` |

**Corps du rapport :**
```
DAILY SALES REPORT
Date: {date}

SALES SUMMARY
Total Orders: {total_orders}
Total Sales: {total_sales} TND

ORDERS BY STATUS
confirmed: X
cancelled: Y

TOP PRODUCTS
Product A: X units
Product B: Y units

LOW STOCK ALERT
Black T-shirt: 2 units
Smart Watch: 1 unit

AutoShop System
```

---

### Node 7 : Save Log (PostgreSQL)

```sql
INSERT INTO automation_logs (workflow_name, action, status, details)
VALUES (
  '09 - Daily Sales Report',
  'daily_report_sent',
  'success',
  'Daily report sent to manager - Orders: {total_orders} - Sales: {total_sales} TND'
)
```

---

## Résumé des tables de base de données utilisées

| Table | Utilisée par |
|---|---|
| `customers` | WF01 (insert), WF05, WF08 (select) |
| `products` | WF02 (select/update), WF09 (select) |
| `orders` | WF01 (insert), WF05, WF07, WF08 (update), WF09 (select) |
| `order_items` | WF01 (insert), WF07, WF09 (select) |
| `stock_movements` | WF02 (insert) |
| `carts` | WF06 (insert/update) |
| `email_logs` | WF03, WF05 (insert) |
| `automation_logs` | WF09 (insert) |

## Résumé des credentials nécessaires

| Credential | Workflows concernés |
|---|---|
| PostgreSQL (`postgres`) | 01, 02, 03, 05, 06, 07, 08, 09 |
| SMTP Mailpit (`smtp`) | 02, 03, 08, 09 |
| Telegram Bot API (`telegramApi`) | 04, 05, 06, 07, 08 |
| Gmail IMAP (`imap`) | 08 |