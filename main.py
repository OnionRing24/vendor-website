from flask import Flask, render_template, request, redirect, url_for, session
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import event, CheckConstraint
from datetime import datetime, timedelta
import enum

app = Flask(__name__)
# Replace with your actual credentials
app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql://root:cset155@localhost/storedb'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# --- Enums ---
class RoleEnum(enum.Enum):
    customer = "customer"
    vendor = "vendor"
    admin = "admin"

class VisibilityEnum(enum.Enum):
    private = "private"
    unlisted = "unlisted"
    public = "public"

class OrderStatus(enum.Enum):
    pending = "pending"
    confirmed = "confirmed"
    handed_to_delivery_partner = "handed_to_delivery_partner"
    shipped = "shipped"
    completed = "completed"
    cancelled = "cancelled"

class ClaimStatus(enum.Enum):
    pending = "pending"
    rejected = "rejected"
    confirmed = "confirmed"
    processing = "processing"
    complete = "complete"

# --- Models ---

class Account(db.Model):
    account_id = db.Column(db.Integer, primary_key=True)
    first_name = db.Column(db.String(50))
    last_name = db.Column(db.String(50))
    email = db.Column(db.String(50), unique=True)
    username = db.Column(db.String(50))
    password_hash = db.Column(db.String(255))
    role = db.Column(db.Enum(RoleEnum), nullable=False)

class Product(db.Model):
    product_id = db.Column(db.Integer, primary_key=True)
    vendor_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    name = db.Column(db.String(255))
    description = db.Column(db.Text)
    available = db.Column(db.Integer, default=0)
    rating = db.Column(db.Integer, nullable=False)
    price = db.Column(db.Float)
    original_price = db.Column(db.Float)
    is_discount = db.Column(db.Boolean, default=False)
    discount_start = db.Column(db.DateTime)
    discount_end = db.Column(db.DateTime)
    warranty_period = db.Column(db.DateTime)
    visibility = db.Column(db.Enum(VisibilityEnum), default=VisibilityEnum.public)
    
    __table_args__ = (CheckConstraint('discount_end > discount_start', name='discount_date_check'),)

class ProductVariant(db.Model):
    product_variant_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    color_code = db.Column(db.String(50))
    color_name = db.Column(db.String(50))
    product_width = db.Column(db.String(50))
    product_height = db.Column(db.String(50))

class ProductImage(db.Model):
    product_image_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    product_variant_id = db.Column(db.Integer, db.ForeignKey('product_variant.product_variant_id'), nullable=False)
    image_link = db.Column(db.String(255))

class Cart(db.Model):
    cart_id = db.Column(db.Integer, primary_key=True)
    owner_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    items = db.relationship('CartItem', backref='cart', lazy=True, cascade="all, delete-orphan")

class CartItem(db.Model):
    cart_item_id = db.Column(db.Integer, primary_key=True)
    cart_id = db.Column(db.Integer, db.ForeignKey('cart.cart_id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    quantity = db.Column(db.Integer, default=1)
    price_at_addition = db.Column(db.Float)
    visibility = db.Column(db.Enum(VisibilityEnum), nullable=False)

class Order(db.Model):
    __tablename__ = 'orders'
    order_id = db.Column(db.Integer, primary_key=True)
    customer_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    order_date = db.Column(db.DateTime, default=datetime.utcnow)
    total_items = db.Column(db.Integer, default=0)
    total_amount = db.Column(db.Float)
    order_confirmed = db.Column(db.Boolean, default=False)
    items = db.relationship('OrderItem', backref='order', lazy=True)

class OrderItem(db.Model):
    order_item_id = db.Column(db.Integer, primary_key=True)
    order_id = db.Column(db.Integer, db.ForeignKey('orders.order_id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    quantity = db.Column(db.Integer, default=1)
    price_at_purchase = db.Column(db.Float, nullable=False)
    warranty_deadline = db.Column(db.DateTime)
    status = db.Column(db.Enum(OrderStatus), default=OrderStatus.pending)

class Review(db.Model):
    review_id = db.Column(db.Integer, primary_key=True)
    customer_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    order_item_id = db.Column(db.Integer, db.ForeignKey('order_item.order_item_id'))
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    rating = db.Column(db.Integer)
    description = db.Column(db.Text)
    
    __table_args__ = (CheckConstraint('rating >= 1 AND rating <= 5', name='valid_rating'),)

class Claim(db.Model):
    claim_id = db.Column(db.Integer, primary_key=True)
    customer_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    order_item_id = db.Column(db.Integer, db.ForeignKey('order_item.order_item_id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    claim_type = db.Column(db.Enum('return', 'warranty'), nullable=False)
    reason = db.Column(db.Text)
    status = db.Column(db.Enum(ClaimStatus), default=ClaimStatus.pending)
    warranty_period = db.Column(db.DateTime)

class Conversation(db.Model):
    conversation_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    order_item_id = db.Column(db.Integer, db.ForeignKey('order_item.order_item_id'))
    claim_id = db.Column(db.Integer, db.ForeignKey('claim.claim_id'))
    participants = db.relationship('Participant', backref='conversation', lazy=True)

class Participant(db.Model):
    conversation_id = db.Column(db.Integer, db.ForeignKey('conversation.conversation_id'), primary_key=True)
    account_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), primary_key=True)
    username = db.Column(db.String(50))

class Message(db.Model):
    message_id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey('conversation.conversation_id'), nullable=False)
    sender_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    message_content = db.Column(db.Text)
    message_image = db.Column(db.Text)
    sent_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_read = db.Column(db.Boolean, default=False)



@app.route('/')
def index():
    return render_template('index.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        check_password=request.form.get('password')
        confirm_password=request.form.get('confirm_password')

        if check_password != confirm_password:
            return render_template('register.html', error='Passwords do not match', success=None)
        
        new_user = Account(
            first_name=request.form['first_name'],
            last_name=request.form['last_name'],
            email=request.form['email'],
            username=request.form['username'],
            password=request.form['password'],
            role=request.form['role']
        )
        db.session.add(new_user)
        db.session.commit()
        return render_template('register.html', error=None, success="Registration successful! Pending admin approval.")
    return render_template('register.html')




if __name__ == '__main__':
    app.run(debug=True)