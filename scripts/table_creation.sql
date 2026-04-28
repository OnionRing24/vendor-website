use storedb;



-- 1. Create Account first (base table)
CREATE TABLE `account` (
  `account_id` int PRIMARY KEY AUTO_INCREMENT,
  `first_name` varchar(50),
  `last_name` varchar(50),
  `email` varchar(50) UNIQUE,
  `username` varchar(50),
  `password_hash` varchar(255),
  `role` ENUM ('customer', 'vendor', 'admin') NOT NULL
) COMMENT = 'Core user accounts. Composite key (account_id, role) should be unique per vendor relationship.';

-- 2. Create Product
CREATE TABLE `product` (
  `product_id` int PRIMARY KEY AUTO_INCREMENT,
  `vendor_id` int NOT NULL,
  `vendor_role` ENUM ('customer', 'vendor', 'admin') NOT NULL DEFAULT 'vendor',
  `name` varchar(255),
  `description` text,
  `available` int,
  `rating` int NOT NULL,
  `price` float,
  `original_price` float,
  `is_discount` boolean DEFAULT false,
  `discount_start` datetime,
  `discount_end` datetime,
  `warranty_period` datetime,
  `visibility` ENUM ('private', 'unlisted', 'public') DEFAULT 'public',
  CONSTRAINT `discount_date_check` CHECK (discount_end > discount_start),
  FOREIGN KEY (`vendor_id`) REFERENCES `account` (`account_id`)
) COMMENT = 'Composite FK (vendor_id, vendor_role) references account.';

-- 3. Product Details
CREATE TABLE `product_variant` (
  `product_variant_id` int PRIMARY KEY AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `color_code` varchar(50),
  `color_name` varchar(50),
  `product_width` varchar(50),
  `product_height` varchar(50),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`)
);

CREATE TABLE `product_image` (
  `product_image_id` int PRIMARY KEY AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `product_variant_id` int NOT NULL,
  `image_link` varchar(255),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`),
  FOREIGN KEY (`product_variant_id`) REFERENCES `product_variant` (`product_variant_id`)
);

-- 4. Cart System
CREATE TABLE `cart` (
  `cart_id` int UNIQUE PRIMARY KEY AUTO_INCREMENT,
  `owner_id` int NOT NULL,
  `owner_role` ENUM ('customer', 'vendor', 'admin') NOT NULL DEFAULT 'customer',
  FOREIGN KEY (`owner_id`) REFERENCES `account` (`account_id`)
) COMMENT = 'Composite FK (owner_id, owner_role) references account.';

CREATE TABLE `cart_item` (
  `cart_item_id` int PRIMARY KEY AUTO_INCREMENT,
  `cart_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int DEFAULT 1,
  `price_at_addition` float,
  `visibility` ENUM ('private', 'unlisted', 'public') NOT NULL,
  FOREIGN KEY (`cart_id`) REFERENCES `cart` (`cart_id`),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`)
);

-- 5. Orders
CREATE TABLE `orders` (
  `order_id` int PRIMARY KEY AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `customer_role` ENUM ('customer', 'vendor', 'admin') NOT NULL DEFAULT 'customer',
  `order_date` timestamp DEFAULT (now()),
  `total_items` int DEFAULT 0,
  `total_amount` float,
  `order_confirmed` boolean DEFAULT false,
  FOREIGN KEY (`customer_id`) REFERENCES `account` (`account_id`)
);

CREATE TABLE `order_item` (
  `order_item_id` int PRIMARY KEY AUTO_INCREMENT,
  `order_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int DEFAULT 1,
  `price_at_purchase` float NOT NULL,
  `warranty_deadline` datetime,
  `status` ENUM ('pending', 'confirmed', 'handed_to_delivery_partner', 'shipped', 'completed', 'cancelled') DEFAULT 'pending',
  FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`)
);

-- 6. Social and Support
CREATE TABLE `review` (
  `review_id` int UNIQUE PRIMARY KEY AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `customer_role` ENUM ('customer', 'vendor', 'admin') NOT NULL DEFAULT 'customer',
  `order_item_id` int,
  `product_id` int NOT NULL,
  `rating` int,
  `description` text,
  CONSTRAINT `valid_rating` CHECK (rating >= 1 AND rating <= 5),
  FOREIGN KEY (`customer_id`) REFERENCES `account` (`account_id`),
  FOREIGN KEY (`order_item_id`) REFERENCES `order_item` (`order_item_id`),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`)
) COMMENT = 'Composite FK (customer_id, customer_role) references account.';

CREATE TABLE `claim` (
  `claim_id` int PRIMARY KEY AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `customer_role` ENUM ('customer', 'vendor', 'admin') NOT NULL DEFAULT 'customer',
  `order_item_id` int NOT NULL,
  `product_id` int NOT NULL,
  `claim_type` ENUM ('return', 'warranty') NOT NULL,
  `reason` text,
  `status` ENUM ('pending', 'rejected', 'confirmed', 'processing', 'complete') DEFAULT 'pending',
  `warranty_period` datetime,
  FOREIGN KEY (`customer_id`) REFERENCES `account` (`account_id`),
  FOREIGN KEY (`order_item_id`) REFERENCES `order_item` (`order_item_id`),
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`)
) COMMENT = 'Composite FK (customer_id, customer_role) references account.';

-- 7. Communications
CREATE TABLE `conversation` (
  `conversation_id` int PRIMARY KEY AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `order_item_id` int,
  `claim_id` int,
  FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`),
  FOREIGN KEY (`order_item_id`) REFERENCES `order_item` (`order_item_id`),
  FOREIGN KEY (`claim_id`) REFERENCES `claim` (`claim_id`)
);

CREATE TABLE `participant` (
  `conversation_id` int NOT NULL,
  `account_id` int NOT NULL,
  `username` varchar(50),
  UNIQUE (`conversation_id`, `account_id`),
  FOREIGN KEY (`conversation_id`) REFERENCES `conversation` (`conversation_id`),
  FOREIGN KEY (`account_id`) REFERENCES `account` (`account_id`)
) COMMENT = 'Composite primary key prevents same user joining conversation twice.';

CREATE TABLE `message` (
  `message_id` int PRIMARY KEY AUTO_INCREMENT,
  `conversation_id` int NOT NULL,
  `sender_id` int NOT NULL,
  `message_content` text,
  `message_image` text,
  `sent_at` timestamp DEFAULT (now()),
  `is_read` boolean DEFAULT false,
  FOREIGN KEY (`conversation_id`) REFERENCES `conversation` (`conversation_id`),
  FOREIGN KEY (`sender_id`) REFERENCES `account` (`account_id`)
);