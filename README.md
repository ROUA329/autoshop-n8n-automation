# AutoShop n8n Automation

## Description

Système d'automatisation e-commerce construit avec **n8n**, **PostgreSQL**, **Mailpit**, **Metabase**, et **Telegram**. Il automatise : réception de commande, validation sécurisée (HMAC + WAF), mise à jour du stock, emails de confirmation, assignation automatique du livreur par zone, notifications Telegram (client et livreur), mise à jour du statut de livraison via boutons Telegram, relance panier abandonné, et rapport de ventes quotidien.

## Outils utilisés

| Outil | Rôle |
|---|---|
| n8n | Moteur d'automatisation (10 workflows) |
| Docker | Exécution locale de tous les services |
| PostgreSQL | Base de données |
| Mailpit | Test d'emails en local |
| Metabase | Dashboard et reporting |
| Telegram Bot API | Notifications client + livreur, boutons de mise à jour livraison |
| Gmail IMAP | Déclencheur email du livreur (workflow 08) |

## Installation

### 1. Cloner le repo
```bash
git clone https://github.com/ROUA329/autoshop-n8n-automation
cd autoshop-n8n-automation
```

### 2. Créer le fichier .env
```bash
cp .env.example .env
```
Remplir les vraies valeurs dans `.env` (voir section credentials).

### 3. Lancer les containers
```bash
docker compose up -d
docker ps
```
Vérifier que ces 4 containers sont actifs :
- `autoshop_n8n`
- `autoshop_postgres`
- `autoshop_mailpit`
- `autoshop_metabase`

### 4. Créer la base de données

**Linux/Mac :**
```bash
docker exec -i autoshop_postgres psql -U autoshop_user -d autoshop_db < database/schema.sql
docker exec -i autoshop_postgres psql -U autoshop_user -d autoshop_db < database/seed-data.sql
```

**Windows PowerShell :**
```powershell
Get-Content database/schema.sql | docker exec -i autoshop_postgres psql -U autoshop_user -d autoshop_db
Get-Content database/seed-data.sql | docker exec -i autoshop_postgres psql -U autoshop_user -d autoshop_db
```

### 5. Importer les workflows dans n8n
1. Ouvrir `http://localhost:5678`
2. Créer un compte (première connexion)
3. Pour chaque fichier dans `workflows/` :
   - **Create workflow → "..." → Import from File**
   - Sélectionner le fichier JSON

## ⚠️ Recréer les credentials (étape obligatoire)

Les credentials ne sont **jamais** incluses dans les exports JSON (sécurité n8n). Après import, recréer les credentials suivantes dans **Settings → Credentials → Add credential**, puis les réassigner sur chaque node concerné.

### a) PostgreSQL
| Champ | Valeur |
|---|---|
| Host | `postgres` |
| Port | `5432` |
| Database | `autoshop_db` |
| User | `autoshop_user` |
| Password | `autoshop_password` |

### b) SMTP — Mailpit
| Champ | Valeur |
|---|---|
| Host | `mailpit` |
| Port | `1025` |
| SSL/TLS | Non |
| User / Password | Laisser vide |

### c) Gmail IMAP — workflow "08 - Livreur Email Trigger"
| Champ | Valeur |
|---|---|
| Type | IMAP |
| Host | `imap.gmail.com` |
| Port | `993` |
| Email | adresse Gmail surveillée |
| Password | **App Password** Gmail (pas le mot de passe principal) |

> Pour créer un App Password Gmail : Compte Google → Sécurité → Validation en 2 étapes → Mots de passe des applications.

### d) Telegram Bot API — workflows 04, 06, 07, 08
| Champ | Valeur |
|---|---|
| Access Token | Token obtenu via [@BotFather](https://t.me/BotFather) |

> Créer un bot : ouvrir Telegram → chercher @BotFather → `/newbot` → copier le token.

> ⚠️ Configurer le webhook Telegram pour pointer vers : `http://localhost:5678/webhook/telegram-confirmation`

## Accès aux interfaces

| Interface | URL |
|---|---|
| n8n | http://localhost:5678 |
| Mailpit | http://localhost:8025 |
| Metabase | http://localhost:3000 |

## Liste des workflows (10)

| # | Nom | Déclencheur | Objectif |
|---|---|---|---|
| 01 | New Order Reception | Webhook POST `/new-order` | Recevoir, valider (HMAC + WAF), enregistrer une commande |
| 02 | Stock Update | Interne (suite à 07) | Décrémenter le stock, alerter si stock bas |
| 03 | Customer Email Confirmation | Interne (suite à 01) | Envoyer email de confirmation au client |
| 04 | Telegram Notification | Interne (suite à 01) | Envoyer notification Telegram au gestionnaire avec boutons ✅ YES / ❌ NO |
| 06 | Abandoned Cart Relance | Webhook POST `/cart-created` | Détecter panier abandonné, envoyer relance Telegram |
| 07 | Order Confirmation | Webhook POST `/telegram-confirmation` | Gérer toutes les interactions Telegram : confirmation client, liaison livreur, mise à jour livraison par boutons |
| 08 | Livreur Email Trigger | Email Trigger IMAP (Gmail) | Le livreur envoie un email (shipped/delivered + order code) → mise à jour DB → Telegram au client |
| 09 | Daily Sales Report | Schedule Trigger 18:00 | Rapport de ventes quotidien par email (Mailpit) |
| 10 | Send Agent Telegram Invite | Webhook POST `/invite-agent` | Envoyer email d'invitation au livreur avec lien Telegram unique |

## Sécurité — WAF (Web Application Firewall)

Le workflow 01 intègre une couche de sécurité WAF qui protège le webhook `/new-order` contre :

- **Injection SQL** — détection de patterns comme `SELECT`, `DROP`, `INSERT`, `--`, `' OR '1'='1`
- **Injection de scripts (XSS)** — détection de balises `<script>`, `javascript:`, `onerror=`
- **Requêtes non signées** — vérification de la signature **HMAC-SHA256** dans le header `X-Signature`

Si une attaque est détectée, la requête est **bloquée** et l'événement est journalisé dans la table `security_logs`.

### Envoyer une requête sécurisée (Windows PowerShell)

```powershell
$secret = "votre-clé-secrète"
$body = '{"order_code":"CMD-001", ...}'

$hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
$hmacsha256.Key = [Text.Encoding]::UTF8.GetBytes($secret)
$signatureBytes = $hmacsha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($body))
$signature = ($signatureBytes | ForEach-Object { $_.ToString("x2") }) -join ''

Invoke-RestMethod -Uri "http://localhost:5678/webhook/new-order" `
  -Method POST -ContentType "application/json" `
  -Headers @{ "X-Signature" = $signature } `
  -Body $body
```

## Système livreur — fonctionnement complet

```
1. POST /invite-agent { agent_id: X }
        ↓
2. Email envoyé au livreur avec lien https://t.me/bot?start=AGENT-X
        ↓
3. Livreur clique → Telegram enregistre son chat_id en base
        ↓
4. Client confirme commande ✅ → livreur de la même zone assigné automatiquement
        ↓
5. Livreur reçoit commande sur Telegram avec boutons 🚚 Shipped / ✅ Delivered
        ↓
6. Livreur clique bouton → statut mis à jour en base → client notifié sur Telegram
```

## Base de données

| Table | Contenu |
|---|---|
| `customers` | Clients avec zone et telegram_chat_id |
| `products` | Produits avec stock et seuil minimum |
| `orders` | Commandes avec statut, delivery_agent_id, assigned_at |
| `order_items` | Articles de chaque commande |
| `stock_movements` | Historique des mouvements de stock |
| `delivery_agents` | Livreurs avec zone, telegram_chat_id, is_active |
| `carts` | Paniers avec statut (open / relance_sent) |
| `email_logs` | Historique des emails envoyés |
| `automation_logs` | Logs des workflows n8n |
| `security_logs` | Tentatives d'attaque détectées par le WAF (injection SQL, XSS, requêtes non signées) |

## Scénarios de test

Voir [`docs/test-cases.md`](./docs/test-cases.md) pour tous les JSON de test avec résultats attendus.

## Résultat final

Le système automatise entièrement :
- Réception et validation sécurisée de commande (HMAC-SHA256 + WAF)
- Mise à jour du stock et alerte stock bas
- Email de confirmation au client
- Notification Telegram au gestionnaire pour confirmation
- Assignation automatique du livreur par zone géographique
- Notifications Telegram au livreur avec boutons de mise à jour
- Mise à jour du statut de livraison en temps réel
- Notification Telegram au client à chaque étape
- Relance panier abandonné via Telegram
- Rapport de ventes quotidien par email
- Dashboard Metabase avec toutes les métriques