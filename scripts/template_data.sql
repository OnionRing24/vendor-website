use storedb;



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