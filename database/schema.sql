CREATE TABLE customers (
   id SERIAL PRIMARY KEY,
   full_name VARCHAR(150) NOT NULL,
   email VARCHAR(150) NOT NULL,
   phone VARCHAR(50),
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
   id SERIAL PRIMARY KEY,
   product_code VARCHAR(50) UNIQUE NOT NULL,
   product_name VARCHAR(150) NOT NULL,
   price NUMERIC(10, 2) NOT NULL,
   stock_quantity INTEGER NOT NULL,
   minimum_stock INTEGER DEFAULT 5,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
   id SERIAL PRIMARY KEY,
   order_code VARCHAR(50) UNIQUE NOT NULL,
   customer_id INTEGER REFERENCES customers(id),
   total_amount NUMERIC(10, 2) NOT NULL,
   status VARCHAR(50) DEFAULT 'new',
   payment_status VARCHAR(50) DEFAULT 'pending',
   delivery_status VARCHAR(50) DEFAULT 'not_shipped',
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
   id SERIAL PRIMARY KEY,
   order_id INTEGER REFERENCES orders(id),
   product_id INTEGER REFERENCES products(id),
   quantity INTEGER NOT NULL,
   unit_price NUMERIC(10, 2) NOT NULL,
   line_total NUMERIC(10, 2) NOT NULL
);

CREATE TABLE stock_movements (
   id SERIAL PRIMARY KEY,
   product_id INTEGER REFERENCES products(id),
   movement_type VARCHAR(50) NOT NULL,
   quantity INTEGER NOT NULL,
   old_stock INTEGER NOT NULL,
   new_stock INTEGER NOT NULL,
   reason TEXT,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE carts (
   id SERIAL PRIMARY KEY,
   cart_code VARCHAR(50) UNIQUE NOT NULL,
   customer_email VARCHAR(150) NOT NULL,
   customer_name VARCHAR(150),
   total_amount NUMERIC(10, 2),
   status VARCHAR(50) DEFAULT 'open',
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE email_logs (
   id SERIAL PRIMARY KEY,
   recipient_email VARCHAR(150) NOT NULL,
   subject VARCHAR(255) NOT NULL,
   email_type VARCHAR(100),
   status VARCHAR(50) DEFAULT 'sent',
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE automation_logs (
   id SERIAL PRIMARY KEY,
   workflow_name VARCHAR(150),
   action VARCHAR(150),
   status VARCHAR(50),
   details TEXT,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);