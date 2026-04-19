use storedb;



CREATE TABLE account (
  account_id int auto_increment PRIMARY KEY,
  first_name varchar(50),
  last_name varchar(50),
  email varchar(50) UNIQUE,
  username varchar(50),
  password varchar(100),
  role ENUM ('customer', 'vendor', 'admin'),
  created_at datetime DEFAULT now(),
  UNIQUE KEY (account_id, role)
);

CREATE TABLE product (
  product_id int auto_increment PRIMARY KEY,
  vendor_id int,
  vendor_role ENUM('customer', 'vendor', 'admin') DEFAULT 'vendor' NOT NULL, 
  name varchar(50),
  description text,
  available int,
  price float,
  original_price float,
  is_discount boolean DEFAULT False,
  discount_start datetime NULL,
  discount_end datetime NULL,
  CONSTRAINT fk_product_vendor 
    FOREIGN KEY (vendor_id, vendor_role) 
    REFERENCES account (account_id, role),
  CONSTRAINT chk_discount_dates CHECK (discount_end > discount_start)
);
CREATE TABLE product_color (
    product_color_id int auto_increment PRIMARY KEY,
    product_id int,
    color_code varchar(50),
    color_name varchar(50),
    FOREIGN KEY (product_id) REFERENCES product (product_id)
);
CREATE TABLE product_image (
    product_image_id int auto_increment PRIMARY KEY,
    product_id int,
    image_link varchar(255),
    FOREIGN KEY (product_id) REFERENCES product (product_id)
);

CREATE TABLE cart (
  cart_id int auto_increment unique,
  owner_id int,
  owner_role ENUM('customer', 'vendor', 'admin') DEFAULT 'customer' NOT NULL,
  total_price float,
  CONSTRAINT fk_cart_owner
    FOREIGN KEY (owner_id, owner_role)
    REFERENCES account (account_id, role)
);

CREATE TABLE cart_item (
  cart_item_id int auto_increment PRIMARY KEY,
  cart_id int,
  product_id int,
  quantity int DEFAULT 1,
  price_at_addition float,
  FOREIGN KEY (cart_id) REFERENCES cart (cart_id),
  FOREIGN KEY (product_id) REFERENCES product (product_id)
);

CREATE TABLE orders (
    order_id int auto_increment PRIMARY KEY,
    customer_id int,
    customer_role ENUM('customer', 'vendor', 'admin') DEFAULT 'customer' NOT NULL,
    order_date timestamp DEFAULT now(),
    total_items int DEFAULT 0,
    total_amount float,
    order_confirmed bool DEFAULT false,
    status ENUM ('pending', 'confirmed', 'handed to delivery partner', 'shipped', 'completed', 'cancelled'),
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id, customer_role)
        REFERENCES account (account_id, role)
);

CREATE TABLE order_item (
    order_item_id int auto_increment PRIMARY KEY,
    order_id int,
    product_id int,
    quantity int DEFAULT 1,
    price_at_purchase float, 
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);


CREATE TABLE review (
  review_id int auto_increment unique,
  customer_id int,
  customer_role ENUM('customer', 'vendor', 'admin') DEFAULT 'customer' NOT NULL,
  product_id int,
  rating int CHECK (rating >= 1 and rating <= 5),
  description text,
  CONSTRAINT fk_review_customer
    FOREIGN KEY (customer_id, customer_role)
    REFERENCES account (account_id, role),
  FOREIGN KEY (product_id) REFERENCES product (product_id)
);

CREATE TABLE claim (
    claim_id int auto_increment PRIMARY KEY,
    customer_id int,
    customer_role ENUM('customer', 'vendor', 'admin') DEFAULT 'customer' NOT NULL,
    order_id int,
    product_id int,
    claim_type ENUM('return', 'warranty') NOT NULL, 
    reason text,
    status ENUM ('pending', 'rejected', 'confirmed', 'processing', 'complete') DEFAULT 'pending',
    CONSTRAINT fk_claim_customer
        FOREIGN KEY (customer_id, customer_role)
        REFERENCES account (account_id, role),
    FOREIGN KEY (order_id) REFERENCES orders (order_id),
    FOREIGN KEY (product_id) REFERENCES product (product_id)
);

CREATE TABLE conversation (
  conversation_id int auto_increment PRIMARY KEY
);

CREATE TABLE participant (
  conversation_id int,
  account_id int,
  username varchar(50),
  PRIMARY KEY (conversation_id, account_id),
  FOREIGN KEY (conversation_id) REFERENCES conversation (conversation_id),
  FOREIGN KEY (account_id) REFERENCES account (account_id)
);

CREATE TABLE message (
  message_id int auto_increment PRIMARY KEY,
  conversation_id int,
  sender_id int,
  message_content text,
  message_image text DEFAULT NULL,
  sent_at timestamp DEFAULT now(),
  is_read boolean DEFAULT false,
  FOREIGN KEY (conversation_id) REFERENCES conversation (conversation_id),
  FOREIGN KEY (sender_id) REFERENCES account (account_id)
);