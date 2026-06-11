# AutoShop n8n Automation

## Description
This project is an e-commerce automation system built with n8n, PostgreSQL, Mailpit, and Metabase.

## Tools
- n8n
- Docker
- PostgreSQL
- Mailpit
- Metabase

## Installation
docker compose up -d

## Access Links
- n8n: http://localhost:5678
- Mailpit: http://localhost:8025
- Metabase: http://localhost:3000

## Workflows
- 01 - New Order Reception
- 02 - Stock Update
- 03 - Customer Email Confirmation
- 04 - Delivery Status Update
- 05 - Abandoned Cart Relance
- 06 - Daily Sales Report

## Database
The database contains: customers, products, orders, order_items, stock_movements, carts, email_logs, and automation_logs.

## Testing
The project was tested with valid orders, invalid orders, low stock, delivery update, and abandoned cart.

## Final Result
The system automates order processing, stock update, emails, delivery notification, abandoned cart relance, and reporting.