use storedb;



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