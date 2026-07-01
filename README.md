# AutoShop n8n Automation

## Description

Système d'automatisation e-commerce construit avec **n8n**, **PostgreSQL**, **Mailpit**, et **Metabase**. Il automatise : réception de commande, mise à jour du stock, emails de confirmation, mise à jour de livraison par le livreur via email, notification Telegram au client, relance panier abandonné, et rapport de ventes quotidien.

## Outils utilisés

| Outil | Rôle |
|---|---|
| n8n | Moteur d'automatisation (9 workflows) |
| Docker | Exécution locale de tous les services |
| PostgreSQL | Base de données |
| Mailpit | Test d'emails en local |
| Metabase | Dashboard et reporting |
| Telegram Bot API | Notification client sur statut de livraison |
| Gmail IMAP | Déclencheur email du livreur (workflow 08) |

## Installation

### 1. Cloner le repo
```bash
git clone https://github.com/ROUA329/autoshop-n8n-automation
cd autoshop-n8n-automation
```

### 2. Lancer les containers
```bash
docker compose up -d
docker ps
```
Vérifier que ces 4 containers sont actifs :
- `autoshop_n8n`
- `autoshop_postgres`
- `autoshop_mailpit`
- `autoshop_metabase`

### 3. Créer la base de données

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

### 4. Importer les workflows dans n8n
1. Ouvrir `http://localhost:5678`
2. Créer un compte (première connexion)
3. Pour chaque fichier dans `workflows/` :
   - **Create workflow → "..." → Import from File**
   - Sélectionner le fichier JSON

## ⚠️ Recréer les credentials (étape obligatoire)

Les credentials ne sont **jamais** incluses dans les exports JSON (sécurité n8n). Après import, recréer les 4 credentials suivantes dans **Settings → Credentials → Add credential**, puis les réassigner sur chaque node concerné.

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

### d) Telegram Bot API — workflow "04 - Telegram Notification"
| Champ | Valeur |
|---|---|
| Access Token | Token obtenu via [@BotFather](https://t.me/BotFather) |

> Créer un bot : ouvrir Telegram → chercher @BotFather → `/newbot` → copier le token.

## Accès aux interfaces

| Interface | URL |
|---|---|
| n8n | http://localhost:5678 |
| Mailpit | http://localhost:8025 |
| Metabase | http://localhost:3000 |

## Liste des workflows (9)

| # | Nom | Déclencheur | Objectif |
|---|---|---|---|
| 01 | New Order Reception | Webhook POST `/new-order` | Recevoir, valider, enregistrer une commande |
| 02 | Stock Update | Interne (suite à 01) | Décrémenter le stock, alerter si stock bas |
| 03 | Customer Email Confirmation | Interne (suite à 01) | Envoyer email de confirmation au client |
| 04 | Telegram Notification | Interne (suite à 08) | Notifier le client sur Telegram du statut livraison |
| 05 | Delivery Status Update | Webhook POST `/delivery-update` | Mettre à jour statut, envoyer email de suivi |
| 06 | Abandoned Cart Relance | Webhook POST `/cart-created` | Détecter panier abandonné, envoyer relance |
| 07 | Order Confirmation | Interne | Confirmation de commande |
| 08 | Livreur Email Trigger | Email Trigger IMAP | Le livreur envoie un email avec statut + order code → mise à jour DB → Telegram au client |
| 09 | Daily Sales Report | Schedule 18:00 | Rapport de ventes quotidien par email |

## Scénario de test complet

Voir [`docs/test-cases.md`](./docs/test-cases.md) pour tous les JSON de test avec résultats attendus.

## Base de données

Tables : `customers`, `products`, `orders`, `order_items`, `stock_movements`, `carts`, `email_logs`, `automation_logs`

## Résultat final

Le système automatise entièrement : réception de commande → stock → emails → livraison (via email du livreur) → notification Telegram → relance panier abandonné → rapport quotidien → dashboard Metabase.