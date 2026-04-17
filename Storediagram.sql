use storedb;

CREATE TABLE account (
  account_id int auto_increment PRIMARY KEY,
  first_name varchar(50),
  last_name varchar(50),
  email varchar(50) UNIQUE,
  username varchar(50),
  password varchar(100),
  role ENUM ('customer', 'vendor', 'admin'),
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
    order_date timestamp DEFAULT (now()),
    total_amount float,
    status ENUM ('pending', 'confirmed', 'handed to delivery partner', 'completed'),
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id, customer_role)
        REFERENCES account (account_id, role)
);

CREATE TABLE order_items (
    order_item_id int auto_increment PRIMARY KEY,
    order_id int,
    product_id int,
    quantity int,
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
    reason text,
    status ENUM ('pending', 'rejected', 'confirmed', 'processing', 'complete') DEFAULT 'pending',
    CONSTRAINT fk_claim_customer
        FOREIGN KEY (customer_id, customer_role)
        REFERENCES account (account_id, role),
    FOREIGN KEY (order_id) REFERENCES orders (order_id),
    FOREIGN KEY (product_id) REFERENCES product (product_id)
);

CREATE TABLE conversation (
  conversation_id int auto_increment unique
);

CREATE TABLE participant (
  conversation_id int,
  account_id int
);

CREATE TABLE message (
  message_id int auto_increment unique,
  conversation_id int,
  sender_id int,
  message_content text,
  sent_at timestamp DEFAULT (now()),
  is_read boolean
);



ALTER TABLE `participant` ADD FOREIGN KEY (`conversation_id`) REFERENCES `conversation` (`conversation_id`);
ALTER TABLE `participant` ADD FOREIGN KEY (`account_id`) REFERENCES `account` (`account_id`);

ALTER TABLE `message` ADD FOREIGN KEY (`conversation_id`) REFERENCES `conversation` (`conversation_id`);
ALTER TABLE `message` ADD FOREIGN KEY (`sender_id`) REFERENCES `account` (`account_id`);

ALTER TABLE `claim` ADD FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`);



DELIMITER //

CREATE TRIGGER tr_create_cart_after_customer_insert
AFTER INSERT ON account
FOR EACH ROW
BEGIN
    IF NEW.role = 'customer' THEN
        INSERT INTO cart (owner_id, owner_role, total_price)
        VALUES (NEW.account_id, NEW.role, 0.00);
    END IF;
END //

DELIMITER ;


DELIMITER //

CREATE PROCEDURE sp_apply_discount(
    IN p_product_id INT,
    IN p_new_price DECIMAL(10,2),
    IN p_duration INT,
    IN p_unit VARCHAR(10)
)
BEGIN
    DECLARE v_end_time DATETIME;

    SET v_end_time = CASE
        WHEN p_unit = 'minute' THEN DATE_ADD(NOW(), INTERVAL p_duration MINUTE)
        WHEN p_unit = 'hour'   THEN DATE_ADD(NOW(), INTERVAL p_duration HOUR)
        WHEN p_unit = 'day'    THEN DATE_ADD(NOW(), INTERVAL p_duration DAY)
        ELSE NULL
    END;

    UPDATE product
    SET
        price = p_new_price,
        is_discount = True,
        discount_start = NOW(),
        discount_end = v_end_time
    WHERE product_id = p_product_id;
END //

DELIMITER ;


DELIMITER //

CREATE PROCEDURE sp_add_to_cart(
    IN p_cart_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_current_price DECIMAL(10,2);
    
    -- Get current price from product table
    SELECT price INTO v_current_price FROM product WHERE product_id = p_product_id;

    -- If item exists, add to quantity. If not, insert new row.
    IF EXISTS (SELECT 1 FROM cart_item WHERE cart_id = p_cart_id AND product_id = p_product_id) THEN
        UPDATE cart_item 
        SET quantity = quantity + p_quantity,
            price_at_addition = v_current_price
        WHERE cart_id = p_cart_id AND product_id = p_product_id;
    ELSE
        INSERT INTO cart_item (cart_id, product_id, quantity, price_at_addition)
        VALUES (p_cart_id, p_product_id, p_quantity, v_current_price);
    END IF;
    
    -- Recalculate total cart price
    UPDATE cart 
    SET total_price = (SELECT SUM(quantity * price_at_addition) FROM cart_item WHERE cart_id = p_cart_id)
    WHERE cart_id = p_cart_id;
END //

DELIMITER ;


DELIMITER //

CREATE PROCEDURE sp_checkout_v2(
    IN p_cart_id INT
)
BEGIN
    DECLARE v_order_id INT;
    DECLARE v_cust_id INT;
    DECLARE v_cust_role VARCHAR(20);
    DECLARE v_total FLOAT;

    SELECT owner_id, owner_role, total_price 
    INTO v_cust_id, v_cust_role, v_total
    FROM cart WHERE cart_id = p_cart_id;

    INSERT INTO orders (customer_id, customer_role, total_amount, status)
    VALUES (v_cust_id, v_cust_role, v_total, 'pending');
    
    SET v_order_id = LAST_INSERT_ID();

    INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase)
    SELECT v_order_id, product_id, quantity, price_at_addition
    FROM cart_item
    WHERE cart_id = p_cart_id;

    DELETE FROM cart_item WHERE cart_id = p_cart_id;
    UPDATE cart SET total_price = 0 WHERE cart_id = p_cart_id;
END //

DELIMITER ;



INSERT INTO account VALUES (NULL, 'john', 'doe', 'jdoe@email', 'admin123', 'password123', 'admin');
INSERT INTO account VALUES (NULL, 'jane', 'doe', 'janedoe@email', 'admin456', 'password123', 'admin');

INSERT INTO account VALUES (NULL, 'john', 'vendor', 'jvendor@email', 'vendor123', 'password123', 'vendor');
INSERT INTO account VALUES (NULL, 'jane', 'vendor', 'janevendor@email', 'vendor456', 'password123', 'vendor');
INSERT INTO account VALUES (NULL, 'joe', 'vendor', 'joevendor@email', 'vendor789', 'password123', 'vendor');

INSERT INTO account VALUES (NULL, 'john', 'customer', 'jcustomer@email', 'customer123', 'password123', 'customer');
INSERT INTO account VALUES (NULL, 'jane', 'customer', 'janecustomer@email', 'customer456', 'password123', 'customer');
INSERT INTO account VALUES (NULL, 'joe', 'customer', 'joecustomer@email', 'customer789', 'password123', 'customer');
INSERT INTO account VALUES (NULL, 'alice', 'customer', 'alicecustomer@email', 'customer246', 'password123', 'customer');
INSERT INTO account VALUES (NULL, 'tom', 'customer', 'tomcustomer@email', 'customer135', 'password123', 'customer');



INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES 
((SELECT account_id FROM account WHERE username = 'vendor123'), 'first product', 'the first product ever added to the storefront', 30, 14.99, 14.99, False),
((SELECT account_id FROM account WHERE username = 'vendor123'), 'second product', 'the second product added to the storefront', 15, 12.99, 12.99, False),
((SELECT account_id FROM account WHERE username = 'vendor123'), 'third product', 'the third product added to the storefront', 10, 9.99, 9.99, False);

INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES 
((SELECT account_id FROM account WHERE username = 'vendor456'), 'fourth party', 'a product made by a different vendor', 20, 4.99, 4.99, False),
((SELECT account_id FROM account WHERE username = 'vendor456'), 'item V', 'a super cool product made by a new vendor', 5, 19.99, 19.99, False),
((SELECT account_id FROM account WHERE username = 'vendor456'), 'Streets VI', 'a physical copy of a totally original game', 50, 7.99, 7.99, False);

INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES 
((SELECT account_id FROM account WHERE username = 'vendor789'), "Seven Eleven's Power Berry", 'Fresh from the iconic Big Gulp Cup', 7, 1.49, 1.49, False),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Crazy Eight', 'A 8 ball that goes kinda crazy', 45, 4.99, 4.99, False),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Job application', 'For those not employed enough to print one themselves', 35, 1.99, 1.99, False),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Ben 10 DvD', 'Totally not the reboot', 10, 3.99, 3.99, False);


CALL sp_apply_discount(10, 1.99, NULL, NULL);
CALL sp_apply_discount(6, 4.99, NULL, NULL);

CALL sp_apply_discount(1, 9.99, 7, 'day');
CALL sp_apply_discount(5, 14.99, 48, 'hour');


CALL sp_add_to_cart(1, 5, 2);
CALL sp_add_to_cart(1, 3, 1);
CALL sp_add_to_cart(2, 8, 1);
CALL sp_add_to_cart(2, 10, 1);
CALL sp_add_to_cart(3, 5, 10);
CALL sp_add_to_cart(4, 2, 2);
CALL sp_add_to_cart(4, 3, 1);
CALL sp_add_to_cart(4 ,5, 2);
CALL sp_add_to_cart(5, 6, 2);

select * from account;
select * from product;
select * from cart;
select * from cart_item;