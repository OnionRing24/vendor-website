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


CREATE PROCEDURE sp_add_to_cart(
    IN p_cart_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_current_price DECIMAL(10,2);
    
    SELECT price INTO v_current_price FROM product WHERE product_id = p_product_id;

    IF EXISTS (SELECT 1 FROM cart_item WHERE cart_id = p_cart_id AND product_id = p_product_id) THEN
        UPDATE cart_item 
        SET quantity = quantity + p_quantity,
            price_at_addition = v_current_price
        WHERE cart_id = p_cart_id AND product_id = p_product_id;
    ELSE
        INSERT INTO cart_item (cart_id, product_id, quantity, price_at_addition)
        VALUES (p_cart_id, p_product_id, p_quantity, v_current_price);
    END IF;
    
    UPDATE cart 
    SET total_price = (SELECT SUM(quantity * price_at_addition) FROM cart_item WHERE cart_id = p_cart_id)
    WHERE cart_id = p_cart_id;
END //


CREATE PROCEDURE sp_checkout(
    IN p_cart_id INT
)
BEGIN
    DECLARE v_order_id INT;
    DECLARE v_cust_id INT;
    DECLARE v_cust_role VARCHAR(20);
    DECLARE v_total_price FLOAT;
    DECLARE v_total_count INT;

    SELECT owner_id, owner_role, total_price, 
           (SELECT SUM(quantity) FROM cart_item WHERE cart_id = p_cart_id)
    INTO v_cust_id, v_cust_role, v_total_price, v_total_count
    FROM cart WHERE cart_id = p_cart_id;

    INSERT INTO orders (customer_id, customer_role, total_amount, total_items, status)
    VALUES (v_cust_id, v_cust_role, v_total_price, v_total_count, 'pending');
    
    SET v_order_id = LAST_INSERT_ID();

    INSERT INTO order_item (order_id, product_id, quantity, price_at_purchase)
    SELECT v_order_id, product_id, quantity, price_at_addition
    FROM cart_item
    WHERE cart_id = p_cart_id;

    DELETE FROM cart_item WHERE cart_id = p_cart_id;
    UPDATE cart SET total_price = 0 WHERE cart_id = p_cart_id;
END //


CREATE PROCEDURE sp_process_order(
    IN p_order_id INT,
    IN p_action ENUM('advance', 'cancel')
)
BEGIN
    DECLARE v_current_status VARCHAR(30);

    SELECT status INTO v_current_status 
    FROM orders WHERE order_id = p_order_id;

    IF p_action = 'cancel' THEN
        IF v_current_status IN ('pending', 'confirmed') THEN
            IF v_current_status = 'confirmed' THEN
                UPDATE product p
                JOIN order_item oi ON p.product_id = oi.product_id
                SET p.available = p.available + oi.quantity
                WHERE oi.order_id = p_order_id;
            END IF;
            UPDATE orders SET status = 'cancelled' WHERE order_id = p_order_id;
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order cannot be cancelled at this stage.';
        END IF;

    ELSEIF p_action = 'advance' THEN
        CASE 
            WHEN v_current_status = 'pending' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM order_item oi
                    JOIN product p ON oi.product_id = p.product_id
                    WHERE oi.order_id = p_order_id AND p.available < oi.quantity
                ) THEN
                    UPDATE orders SET status = 'confirmed', order_confirmed = TRUE WHERE order_id = p_order_id;
                    UPDATE product p
                    JOIN order_item oi ON p.product_id = oi.product_id
                    SET p.available = p.available - oi.quantity
                    WHERE oi.order_id = p_order_id;
                ELSE
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'One or more items are out of stock.';
                END IF;

            WHEN v_current_status = 'confirmed' THEN
                UPDATE orders SET status = 'handed to delivery partner' WHERE order_id = p_order_id;

            WHEN v_current_status = 'handed to delivery partner' THEN
                UPDATE orders SET status = 'shipped' WHERE order_id = p_order_id;

            WHEN v_current_status = 'shipped' THEN
                UPDATE orders SET status = 'completed' WHERE order_id = p_order_id;

            ELSE
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No further steps possible.';
        END CASE;
    END IF;
END //


CREATE PROCEDURE sp_process_claim(
    IN p_claim_id INT,
    IN p_action ENUM('confirm', 'reject', 'advance')
)
BEGIN
    DECLARE v_current_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_product_id INT;
    DECLARE v_quantity INT;

    SELECT c.status, c.product_id, oi.quantity 
    INTO v_current_status, v_product_id, v_quantity
    FROM claim c
    INNER JOIN order_item oi ON c.order_id = oi.order_id AND c.product_id = oi.product_id
    WHERE c.claim_id = p_claim_id;

    IF v_current_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Claim ID not found or No matching Order Item.';
    END IF;

    IF p_action = 'reject' THEN
        IF v_current_status = 'complete' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot reject a claim that is already complete.';
        ELSEIF v_current_status = 'rejected' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Claim is already rejected.';
        ELSE
            UPDATE claim SET status = 'rejected' WHERE claim_id = p_claim_id;
        END IF;

    ELSEIF p_action = 'confirm' THEN
        IF v_current_status = 'pending' THEN
            UPDATE claim SET status = 'confirmed' WHERE claim_id = p_claim_id;
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only pending claims can be confirmed.';
        END IF;

    ELSEIF p_action = 'advance' THEN
        IF v_current_status = 'confirmed' THEN
            UPDATE claim SET status = 'processing' WHERE claim_id = p_claim_id;
        ELSEIF v_current_status = 'processing' THEN
            UPDATE claim SET status = 'complete' WHERE claim_id = p_claim_id;
            UPDATE product SET available = available + v_quantity WHERE product_id = v_product_id;
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot advance. Must be Confirmed or Processing.';
        END IF;
    END IF;
END //


CREATE PROCEDURE sp_send_message(
    IN p_conversation_id INT,
    IN p_sender_id INT,
    IN p_content TEXT
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM participant 
        WHERE conversation_id = p_conversation_id AND account_id = p_sender_id
    ) THEN
        INSERT INTO message (conversation_id, sender_id, message_content)
        VALUES (p_conversation_id, p_sender_id, p_content);
    ELSE
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Permission Denied: Sender is not a participant in this conversation.';
    END IF;
END //


CREATE PROCEDURE sp_send_image(
    IN p_conversation_id INT,
    IN p_sender_id INT,
    IN p_image TEXT
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM participant 
        WHERE conversation_id = p_conversation_id AND account_id = p_sender_id
    ) THEN
        INSERT INTO message (conversation_id, sender_id, message_image)
        VALUES (p_conversation_id, p_sender_id, p_image);
    ELSE
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Permission Denied: Sender is not a participant in this conversation.';
    END IF;
END //

DELIMITER ;



INSERT INTO account VALUES (NULL, 'john', 'doe', 'jdoe@email', 'admin123', 'password123', 'admin', now());
INSERT INTO account VALUES (NULL, 'jane', 'doe', 'janedoe@email', 'admin456', 'password123', 'admin', now());

INSERT INTO account VALUES (NULL, 'john', 'vendor', 'jvendor@email', 'vendor123', 'password123', 'vendor', now());
INSERT INTO account VALUES (NULL, 'jane', 'vendor', 'janevendor@email', 'vendor456', 'password123', 'vendor', now());
INSERT INTO account VALUES (NULL, 'joe', 'vendor', 'joevendor@email', 'vendor789', 'password123', 'vendor', now());

INSERT INTO account VALUES (NULL, 'john', 'customer', 'jcustomer@email', 'customer123', 'password123', 'customer', now());
INSERT INTO account VALUES (NULL, 'jane', 'customer', 'janecustomer@email', 'customer456', 'password123', 'customer', now());
INSERT INTO account VALUES (NULL, 'joe', 'customer', 'joecustomer@email', 'customer789', 'password123', 'customer', now());
INSERT INTO account VALUES (NULL, 'alice', 'customer', 'alicecustomer@email', 'customer246', 'password123', 'customer', now());
INSERT INTO account VALUES (NULL, 'tom', 'customer', 'tomcustomer@email', 'customer135', 'password123', 'customer', now());



INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES (
    (SELECT account_id FROM account WHERE username = 'vendor123'), 'first product', 'the first product ever added to the storefront', 30, 14.99, 14.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor123'), 'second product', 'the second product added to the storefront', 15, 12.99, 12.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor123'), 'third product', 'the third product added to the storefront', 10, 9.99, 9.99, False
);

INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES (
    (SELECT account_id FROM account WHERE username = 'vendor456'), 'fourth party', 'a product made by a different vendor', 20, 4.99, 4.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor456'), 'item V', 'a super cool product made by a new vendor', 15, 19.99, 19.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor456'), 'Streets VI', 'a physical copy of a totally original game', 50, 7.99, 7.99, False
);

INSERT INTO product (vendor_id, name, description, available, price, original_price, is_discount)
VALUES (
    (SELECT account_id FROM account WHERE username = 'vendor789'), "Seven Eleven's Power Berry", 'Fresh from the iconic Big Gulp Cup', 25, 1.49, 1.49, False),(
    (SELECT account_id FROM account WHERE username = 'vendor789'), 'Crazy Eight', 'A 8 ball that goes kinda crazy', 45, 4.99, 4.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor789'), 'Job application', 'For those not employed enough to print one themselves', 35, 1.99, 1.99, False),(
    (SELECT account_id FROM account WHERE username = 'vendor789'), 'Ben 10 DvD', 'Totally not the reboot', 10, 3.99, 3.99, False
);

INSERT INTO product_color (product_id, color_code, color_name) VALUES
(1, '#0B8AE0', 'Light Blue'),
(2, '#DB1818', 'Red'),
(3, '#D437E6', 'Puple'),
(4, '#3BA60F', 'Lime Green'),
(5, '#CF9408', 'Dark Gold'),
(6, '#085D99', 'Dark Blue'),
(7, '#F4811F', 'Orange'),
(7, '#EE2526', 'Light Red'),
(8, '#000000', 'Black'),
(9, '#ffffff', 'White'),
(10, '#047300', 'Green');

INSERT INTO product_image (product_id, image_link) VALUES
(1, ''),
(2, ''),
(3, ''),
(4, ''),
(5, ''),
(6, ''),
(7, ''),
(7, ''),
(8, ''),
(9, 'https://eforms.com/images/2018/03/Employment-Job-Application-791x1024.png'),
(10, '');


CALL sp_apply_discount(10, 1.99, NULL, NULL);
CALL sp_apply_discount(6, 4.99, NULL, NULL);

CALL sp_apply_discount(1, 9.99, 7, 'day');
CALL sp_apply_discount(5, 14.99, 48, 'hour');


CALL sp_add_to_cart(1, 5, 2);
CALL sp_add_to_cart(1, 3, 1);
CALL sp_add_to_cart(2, 8, 1);
CALL sp_add_to_cart(2, 10, 1);
CALL sp_add_to_cart(3, 5, 10);
CALL sp_add_to_cart(3, 7, 15);
CALL sp_add_to_cart(4, 2, 2);
CALL sp_add_to_cart(4, 3, 1);
CALL sp_add_to_cart(4 ,5, 2);
CALL sp_add_to_cart(5, 6, 2);



select * from account;
select * from product;
select * from product_color;
select * from product_image;
select * from cart;
select * from cart_item;



CALL sp_checkout(1);
CALL sp_checkout(2);
CALL sp_checkout(3);    
CALL sp_checkout(4);
CALL sp_checkout(5);


CALL sp_process_order(1, 'cancel');
CALL sp_process_order(2, 'advance');
CALL sp_process_order(3, 'advance');
CALL sp_process_order(3, 'advance');
CALL sp_process_order(3, 'advance');
CALL sp_process_order(3, 'advance');
CALL sp_process_order(4, 'advance');
CALL sp_process_order(4, 'advance');
CALL sp_process_order(4, 'advance');
CALL sp_process_order(5, 'advance');
CALL sp_process_order(5, 'advance');
CALL sp_process_order(5, 'advance');



select * from orders;
select * from order_item;



INSERT INTO review(customer_id, customer_role, product_id, rating, description)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer135'), 'customer', (SELECT product_id FROM product WHERE name = 'Streets VI'), 3, "It was actually the reboot, but at least I enjoyed it."
);

INSERT INTO review(customer_id, customer_role, product_id, rating, description)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer789'), 'customer', (SELECT product_id FROM product WHERE name = 'item V'), 5, "It's way too good. Like seriously! I never thought this vendor would make something so good."
);


INSERT INTO claim(customer_id, customer_role, order_id, product_id, claim_type, reason)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer789'), 'customer', 3, 7, 'return', 'The cup is very aged, and the drink ended up leaking out one of the cups during delivery.'
);

INSERT INTO claim(customer_id, customer_role, order_id, product_id, claim_type, reason)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer135'), 'customer', 2, 10, 'warranty', 'The dvd got scratched, and the show abruptly stops in certain moments'
);


CALL sp_process_claim(1, 'confirm');
CALL sp_process_claim(2, 'reject');
CALL sp_process_claim(1, 'advance');
select * from claim;



INSERT INTO conversation VALUES();
INSERT INTO participant VALUES(
    1, (SELECT account_id FROM account WHERE username = 'customer789'), 'customer789'),
    (1, (SELECT account_id FROM account WHERE username = 'vendor456'), 'vendor456'
);
CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'customer789' AND conversation_id = 1), "Is it possible to buy Item V in bulk by any chance?");

UPDATE message SET is_read = 1 WHERE message_id = 1;

CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 1), "It is possible, however, we don't allow customers to buy all of our products at once.");
UPDATE message SET is_read = 1 WHERE message_id = 2;

CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 1), "Okay, not a problem. Thanks!");



INSERT INTO conversation VALUES();
INSERT INTO participant VALUES(
    2, (SELECT account_id FROM account WHERE username = 'customer123'), 'customer123'),
    (2, (SELECT account_id FROM account WHERE username = 'vendor456'), 'vendor456'
);
CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 2), "Unfortunately, we had to cancel your order due to a lack of availability");

UPDATE message SET is_read = 1 WHERE message_id = 4;

CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'customer123' AND conversation_id = 2), "Oh, ok. Thanks for letting me know!");

CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'customer123' AND conversation_id = 2), "Sorry to bother, but why did it cancel the order for the other product as well?");

UPDATE message SET is_read = 1 WHERE message_id = 5;
UPDATE message SET is_read = 1 WHERE message_id = 6;

CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 2), "Oh, that was probably due to how the order system was structured. We'd recommend reaching out to the website's development team, to see if that could be resolved. We'll do the same as well.");

UPDATE message SET is_read = 1 WHERE message_id = 7;

CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'customer123' AND conversation_id = 2), "Ok, thanks for the understanding. Hopefully that would be fixed soon. It's very unintuitive.");

UPDATE message SET is_read = 1 WHERE message_id = 8;



INSERT INTO conversation VALUES();
INSERT INTO participant VALUES(
    3, (SELECT account_id FROM account WHERE username = 'customer135'), 'customer135'),
    (3, (SELECT account_id FROM account WHERE username = 'admin123'), 'admin123'
);
CALL sp_send_message(3, (SELECT account_id FROM participant WHERE username = 'admin123' AND conversation_id = 3), "Hello, customer135. Unfortunately, this product's warranty expired about a week ago. Because of this, the claim will unfortunately be rejected. Sorry for the inconvenience.");

UPDATE message SET is_read = 1 WHERE message_id = 9;

CALL sp_send_message(3, (SELECT account_id FROM participant WHERE username = 'customer135' AND conversation_id = 3), "I see... Not a major issue! I'm still enjoying the show regarless.");

UPDATE message SET is_read = 1 WHERE message_id = 10;

CALL sp_send_message(3, (SELECT account_id FROM participant WHERE username = 'admin123' AND conversation_id = 3), "Glad to know the damage is not causing any issues. Have a good day.");

UPDATE message SET is_read = 1 WHERE message_id = 11;



INSERT INTO conversation VALUES();
INSERT INTO participant VALUES(
    4, (SELECT account_id FROM account WHERE username = 'customer789'), 'customer789'),
    (4, (SELECT account_id FROM account WHERE username = 'admin456'), 'admin456'
);
CALL sp_send_message(4, (SELECT account_id FROM participant WHERE username = 'admin456' AND conversation_id = 4), "Hello, customer135. Sorry to hear that the delivery process wasn't as effective. Do you still have the package that came with it?");

UPDATE message SET is_read = 1 WHERE message_id = 12;

CALL sp_send_message(4, (SELECT account_id FROM participant WHERE username = 'customer789' AND conversation_id = 4), "Yeah, I still have it with me");

CALL sp_send_image(4, (SELECT account_id FROM participant WHERE username = 'customer789' AND conversation_id = 4), "[image url]");

UPDATE message SET is_read = 1 WHERE message_id = 13;
UPDATE message SET is_read = 1 WHERE message_id = 14;

CALL sp_send_message(4, (SELECT account_id FROM participant WHERE username = 'admin456' AND conversation_id = 4), "Yeah, the package does appear damaged. Thankfully, you should be approved for a return. I'll go ahead and take care of that for you...");

UPDATE message SET is_read = 1 WHERE message_id = 15;

CALL sp_send_message(4, (SELECT account_id FROM participant WHERE username = 'admin456' AND conversation_id = 4), "Okay, here's the tag that you'll need for the return. Just print it and stick it to that box, and it'll be shipped back to the vendor. You should have about 5 days to mail the package back.");

CALL sp_send_image(4, (SELECT account_id FROM participant WHERE username = 'admin456' AND conversation_id = 4), "[image url]");

UPDATE message SET is_read = 1 WHERE message_id = 16;
UPDATE message SET is_read = 1 WHERE message_id = 17;



select * from conversation;
select * from participant;
select * from message;



select * from message where conversation_id = 1;
select * from message where conversation_id = 2;
select * from message where conversation_id = 3;
select * from message where conversation_id = 4;