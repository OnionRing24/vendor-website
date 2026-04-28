DELIMITER //

-- 1. Updated Trigger: Simplified and matches schema
CREATE TRIGGER tr_create_cart_after_customer_insert
AFTER INSERT ON account
FOR EACH ROW
BEGIN
    -- Ensure the cart is created only for customers
    IF NEW.role = 'customer' THEN
        INSERT INTO cart (owner_id, owner_role)
        VALUES (NEW.account_id, NEW.role);
    END IF;
END //

-- 2. Update the product's visibility
CREATE PROCEDURE sp_update_product_visibility(
    IN p_product_id INT,
    IN p_new_visibility ENUM('private', 'unlisted', 'public')
)
BEGIN
    -- Error Handler: Rollback if any SQL error occurs
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
    END;

    START TRANSACTION;

    -- 1. Update the primary product record
    UPDATE product 
    SET visibility = p_new_visibility 
    WHERE product_id = p_product_id;

    -- 2. Sync the visibility in the cart_item table
    -- This keeps the user's cart reflective of current product status
    UPDATE cart_item 
    SET visibility = p_new_visibility 
    WHERE product_id = p_product_id;

    COMMIT;
END //

-- 3. Apply discount
CREATE PROCEDURE sp_apply_discount(
    IN p_product_id INT,
    IN p_new_price FLOAT,
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
        is_discount = TRUE,
        discount_start = NOW(),
        discount_end = v_end_time
    WHERE product_id = p_product_id;
END //

-- 4. Add to cart
CREATE PROCEDURE sp_add_to_cart(
    IN p_cart_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_current_price FLOAT;
    DECLARE v_visibility ENUM('private', 'unlisted', 'public');
    
    -- Fetch current product data
    SELECT price, visibility INTO v_current_price, v_visibility 
    FROM product WHERE product_id = p_product_id;

    -- Update existing item or insert new one
    IF v_visibility = 'public' THEN
        INSERT INTO cart_item (cart_id, product_id, quantity, price_at_addition, visibility)
        VALUES (p_cart_id, p_product_id, p_quantity, v_current_price, v_visibility)
        ON DUPLICATE KEY UPDATE 
            quantity = quantity + p_quantity,
            price_at_addition = v_current_price;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot add an unlisted product.';
    END IF;
END //

-- 5. Checkout cart items
CREATE PROCEDURE sp_checkout(
    IN p_cart_id INT
)
BEGIN
    DECLARE v_order_id INT;
    DECLARE v_cust_id INT;
    DECLARE v_cust_role ENUM('customer', 'vendor', 'admin');
    DECLARE v_total_amt FLOAT DEFAULT 0;
    DECLARE v_total_qty INT DEFAULT 0;

    -- 1. Get the account info
    SELECT owner_id, owner_role 
    INTO v_cust_id, v_cust_role
    FROM cart 
    WHERE cart_id = p_cart_id;

    -- 2. Calculate totals
    SELECT 
        SUM(quantity * price_at_addition), 
        SUM(quantity)
    INTO v_total_amt, v_total_qty
    FROM cart_item
    WHERE cart_id = p_cart_id;

    -- 3. Safety check: Don't create an order if the cart is empty
    IF v_total_qty > 0 THEN
        -- REMOVED 'status' from the INSERT columns and VALUES below
        INSERT INTO orders (customer_id, customer_role, total_amount, total_items)
        VALUES (v_cust_id, v_cust_role, v_total_amt, v_total_qty);
        
        SET v_order_id = LAST_INSERT_ID();

        -- 4. Move items to order_item (status here is handled by table default 'pending')
        INSERT INTO order_item (order_id, product_id, quantity, price_at_purchase, warranty_deadline)
        SELECT v_order_id, ci.product_id, ci.quantity, ci.price_at_addition, p.warranty_period
        FROM cart_item ci
        JOIN product p ON ci.product_id = p.product_id
        WHERE ci.cart_id = p_cart_id;

        -- 5. Clear the cart items
        DELETE FROM cart_item WHERE cart_id = p_cart_id;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot checkout an empty cart.';
    END IF;
END //

-- 6. Process order, and update status
CREATE PROCEDURE sp_process_order(
    IN p_order_item_id INT,
    IN p_action ENUM('advance', 'cancel')
)
proc_label: BEGIN 
    DECLARE v_item_status ENUM('pending', 'confirmed', 'handed_to_delivery_partner', 'shipped', 'completed', 'cancelled');
    DECLARE v_product_id INT;
    DECLARE v_qty INT;

    -- 1. Fetch current state
    SELECT status, product_id, quantity 
    INTO v_item_status, v_product_id, v_qty
    FROM order_item WHERE order_item_id = p_order_item_id;

    -- 2. Exit if the order is already finished or cancelled
    IF v_item_status IN ('completed', 'cancelled') THEN
        LEAVE proc_label; 
    END IF;

    -- 3. Logic for 'cancel'
    IF p_action = 'cancel' THEN
        IF v_item_status IN ('pending', 'confirmed') THEN
            IF v_item_status = 'confirmed' THEN
                UPDATE product SET available = available + v_qty WHERE product_id = v_product_id;
            END IF;
            UPDATE order_item SET status = 'cancelled' WHERE order_item_id = p_order_item_id;
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item cannot be cancelled at this stage.';
        END IF;

    -- 4. Logic for 'advance'
    ELSEIF p_action = 'advance' THEN
        CASE 
            WHEN v_item_status = 'pending' THEN
                IF (SELECT available FROM product WHERE product_id = v_product_id) >= v_qty THEN
                    UPDATE order_item SET status = 'confirmed' WHERE order_item_id = p_order_item_id;
                    UPDATE product SET available = available - v_qty WHERE product_id = v_product_id;
                ELSE
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insufficient for this item.';
                END IF;

            WHEN v_item_status = 'confirmed' THEN
                UPDATE order_item SET status = 'handed_to_delivery_partner' WHERE order_item_id = p_order_item_id;
            WHEN v_item_status = 'handed_to_delivery_partner' THEN
                UPDATE order_item SET status = 'shipped' WHERE order_item_id = p_order_item_id;
            WHEN v_item_status = 'shipped' THEN
                UPDATE order_item SET status = 'completed' WHERE order_item_id = p_order_item_id;
            
            -- Adding this ELSE prevents Error 1339
            ELSE 
                BEGIN END; -- Do nothing if it doesn't match
        END CASE;
    END IF;
END //

-- 7. Process claim and update status
CREATE PROCEDURE sp_process_claim(
    IN p_claim_id INT,
    IN p_action ENUM('confirm', 'reject', 'advance')
)
BEGIN
    DECLARE v_status ENUM('pending', 'rejected', 'confirmed', 'processing', 'complete');
    DECLARE v_prod_id INT;
    DECLARE v_qty INT;

    -- Use the direct order_item_id relationship from our schema
    SELECT c.status, c.product_id, oi.quantity 
    INTO v_status, v_prod_id, v_qty
    FROM claim c
    JOIN order_item oi ON c.order_item_id = oi.order_item_id
    WHERE c.claim_id = p_claim_id;

    IF p_action = 'reject' AND v_status != 'complete' THEN
        UPDATE claim SET status = 'rejected' WHERE claim_id = p_claim_id;
    ELSEIF p_action = 'confirm' AND v_status = 'pending' THEN
        UPDATE claim SET status = 'confirmed' WHERE claim_id = p_claim_id;
    ELSEIF p_action = 'advance' THEN
        IF v_status = 'confirmed' THEN
            UPDATE claim SET status = 'processing' WHERE claim_id = p_claim_id;
        ELSEIF v_status = 'processing' THEN
            UPDATE claim SET status = 'complete' WHERE claim_id = p_claim_id;
            -- Return item to inventory on completed return
            UPDATE product SET available = available + v_qty WHERE product_id = v_prod_id;
        END IF;
    END IF;
END //

-- 8. Sending a message
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

-- 9. Sending an image instead of a message
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