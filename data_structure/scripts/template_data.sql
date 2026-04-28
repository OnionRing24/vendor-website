use storedb;

-- 1. CLEAR PREVIOUS ATTEMPTS (Optional, but recommended for a clean slate)
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE message; TRUNCATE TABLE participant; TRUNCATE TABLE conversation;
TRUNCATE TABLE claim; TRUNCATE TABLE review; TRUNCATE TABLE order_item;
TRUNCATE TABLE orders; TRUNCATE TABLE cart_item; TRUNCATE TABLE cart;
TRUNCATE TABLE product_image; TRUNCATE TABLE product_variant; TRUNCATE TABLE product;
TRUNCATE TABLE account;
SET FOREIGN_KEY_CHECKS = 1;

-- 2. ACCOUNTS
INSERT INTO account (first_name, last_name, email, username, password_hash, role) VALUES 
('john', 'doe', 'jdoe@email', 'admin123', 'password123', 'admin'),
('jane', 'doe', 'janedoe@email', 'admin456', 'password123', 'admin'),
('john', 'vendor', 'jvendor@email', 'vendor123', 'password123', 'vendor'),
('jane', 'vendor', 'janevendor@email', 'vendor456', 'password123', 'vendor'),
('joe', 'vendor', 'joevendor@email', 'vendor789', 'password123', 'vendor'),
('john', 'customer', 'jcustomer@email', 'customer123', 'password123', 'customer'),
('jane', 'customer', 'janecustomer@email', 'customer456', 'password123', 'customer'),
('joe', 'customer', 'joecustomer@email', 'customer789', 'password123', 'customer'),
('alice', 'customer', 'alicecustomer@email', 'customer246', 'password123', 'customer'),
('tom', 'customer', 'tomcustomer@email', 'customer135', 'password123', 'customer');

-- 3. PRODUCTS
INSERT INTO product (vendor_id, name, description, available, price, original_price, rating) VALUES 
((SELECT account_id FROM account WHERE username = 'vendor123'), 'first product', 'the first product', 30, 14.99, 14.99, 5),
((SELECT account_id FROM account WHERE username = 'vendor123'), 'second product', 'the second product', 15, 12.99, 12.99, 4),
((SELECT account_id FROM account WHERE username = 'vendor123'), 'third product', 'the third product', 10, 9.99, 9.99, 3),
((SELECT account_id FROM account WHERE username = 'vendor456'), 'fourth party', 'different vendor product', 20, 4.99, 4.99, 4),
((SELECT account_id FROM account WHERE username = 'vendor456'), 'item V', 'super cool product', 15, 19.99, 19.99, 5),
((SELECT account_id FROM account WHERE username = 'vendor456'), 'Streets VI', 'physical game', 50, 7.99, 7.99, 2),
((SELECT account_id FROM account WHERE username = 'vendor789'), "Seven Eleven's Power Berry", 'Iconic drink', 25, 1.49, 1.49, 5),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Crazy Eight', '8 ball', 45, 4.99, 4.99, 1),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Job application', 'Printable app', 35, 1.99, 1.99, 4),
((SELECT account_id FROM account WHERE username = 'vendor789'), 'Ben 10 DvD', 'Not the reboot', 10, 3.99, 3.99, 3);

-- publishing the products
CALL sp_update_product_visibility(1, 'public');
CALL sp_update_product_visibility(2, 'public');
CALL sp_update_product_visibility(3, 'public');
CALL sp_update_product_visibility(4, 'public');
CALL sp_update_product_visibility(5, 'public');
CALL sp_update_product_visibility(6, 'public');
CALL sp_update_product_visibility(7, 'public');
CALL sp_update_product_visibility(8, 'public');
CALL sp_update_product_visibility(9, 'public');
CALL sp_update_product_visibility(10, 'public');

-- 4. VARIANTS & DISCOUNTS --
INSERT INTO product_variant (product_id, color_code, color_name) VALUES
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

CALL sp_apply_discount(10, 1.99, NULL, NULL);
CALL sp_apply_discount(6, 4.99, NULL, NULL);
CALL sp_apply_discount((SELECT product_id FROM product WHERE name = 'Ben 10 DvD'), 1.99, 7, 'day');
CALL sp_apply_discount((SELECT product_id FROM product WHERE name = 'item V'), 14.99, 48, 'hour');

-- 5. ADD TO CART (Using subqueries for Cart IDs based on owner)
-- customer123 (Cart 1)
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer123')), 5, 2);
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer123')), 3, 1);
-- customer456 (Cart 2)
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer456')), 8, 1);
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer456')), 10, 1);
-- customer789 (Cart 3)
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer789')), 5, 10);
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer789')), 7, 15);
-- customer246 (Cart 4)
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer246')), 2, 2);
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer246')), 3, 1);
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer246')), 5, 2);
-- customer135 (Cart 5)
CALL sp_add_to_cart((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer135')), 6, 2);

-- Preview Shopping Cart --
SELECT * FROM account;
SELECT * FROM product;
SELECT * FROM product_variant;
SELECT * FROM cart;
SELECT * FROM cart_item;

-- 6. CHECKOUT
CALL sp_checkout((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer123'))); -- Order 1
CALL sp_checkout((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer456'))); -- Order 2
CALL sp_checkout((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer789'))); -- Order 3
CALL sp_checkout((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer246'))); -- Order 4
CALL sp_checkout((SELECT cart_id FROM cart WHERE owner_id = (SELECT account_id FROM account WHERE username = 'customer135'))); -- Order 5

-- 7. PROCESS ORDERS
CALL sp_process_order(1, 'cancel'); -- cancelled
CALL sp_process_order(5, 'advance'); -- confirmed
CALL sp_process_order(7, 'advance'); -- confirmed
CALL sp_process_order(7, 'advance'); -- handed_to_delivery_partner
CALL sp_process_order(7, 'advance'); -- shipped
CALL sp_process_order(7, 'advance'); -- completed
CALL sp_process_order(8, 'advance'); -- confirmed
CALL sp_process_order(8, 'advance'); -- handed_to_delivery_partner
CALL sp_process_order(8, 'advance'); -- shipped
CALL sp_process_order(8, 'advance'); -- completed
CALL sp_process_order(11, 'advance'); -- confirmed
CALL sp_process_order(13, 'advance'); -- confirmed

INSERT INTO review(customer_id, customer_role, product_id, rating, description)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer135'), 'customer', (SELECT product_id FROM product WHERE name = 'Streets VI'), 3, "It was actually the reboot, but at least I enjoyed it."
);

INSERT INTO review(customer_id, customer_role, product_id, rating, description)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer789'), 'customer', (SELECT product_id FROM product WHERE name = 'item V'), 5, "It's way too good. Like seriously! I never thought this vendor would make something so good."
);

-- FIXES NEEDED FOR CLAIMS --
/*
INSERT INTO claim(customer_id, customer_role, order_item_id, product_id, claim_type, reason)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer789'), 'customer', 3, 8, 'return', 'The cup is very aged, and the drink ended up leaking out one of the cups during delivery.'
);

INSERT INTO claim(customer_id, customer_role, order_item_id, product_id, claim_type, reason)
VALUES(
    (SELECT account_id FROM account WHERE username = 'customer456'), 'customer', 2, 7, 'warranty', 'The dvd got scratched, and the show abruptly stops in certain moments'
);
*/

-- 9. PROCESS CLAIMS
/*  CALL sp_process_claim(1, 'confirm'); */
/*  CALL sp_process_claim(2, 'reject'); */

-- 8. Messaging (FIXES NEEDED)

/*
INSERT INTO conversation (product_id) VALUES(5);
INSERT INTO participant VALUES(
    1, (SELECT account_id FROM account WHERE username = 'customer789'), 'customer789'),
    (1, (SELECT account_id FROM account WHERE username = 'vendor456'), 'vendor456'
);
CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'customer789' AND conversation_id = 1), "Is it possible to buy Item V in bulk by any chance?");

UPDATE message SET is_read = 1 WHERE message_id = 1;

CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 1), "It is possible, however, we don't allow customers to buy all of our products at once.");
UPDATE message SET is_read = 1 WHERE message_id = 2;

CALL sp_send_message(1, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 1), "Okay, not a problem. Thanks!");



INSERT INTO conversation (product_id) VALUES(5);
INSERT INTO participant VALUES(
    2, (SELECT account_id FROM account WHERE username = 'customer123'), 'customer123'),
    (2, (SELECT account_id FROM account WHERE username = 'vendor456'), 'vendor456'
);
CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'vendor456' AND conversation_id = 2), "Unfortunately, we had to cancel your order due to a lack of availability");

UPDATE message SET is_read = 1 WHERE message_id = 4;

CALL sp_send_message(2, (SELECT account_id FROM participant WHERE username = 'customer123' AND conversation_id = 2), "Oh, ok. Thanks for letting me know!");

UPDATE message SET is_read = 1 WHERE message_id = 5;


INSERT INTO conversation (product_id, order_item_id, claim_id) VALUES(10, 4, 2);
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



INSERT INTO conversation (product_id, order_item_id, claim_id) VALUES(7, 3, 1);
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
*/

-- Final selects to verify
SELECT * FROM orders;
SELECT * FROM order_item;
SELECT * FROM claim;


select * from conversation;
select * from participant;
select * from message;



select * from message where conversation_id = 1;
select * from message where conversation_id = 2;
select * from message where conversation_id = 3;
select * from message where conversation_id = 4;