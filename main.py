from flask import Flask, render_template, request, redirect, url_for, session
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import event, CheckConstraint, func
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash
import enum

app = Flask(__name__)
app.config['SECRET_KEY'] = 'dev'
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

class DiscountRequestStatus(enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"

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
    name = db.Column(db.String(255), unique=True)
    description = db.Column(db.Text)
    rating = db.Column(db.Float, nullable=False, default = 0)
    price = db.Column(db.Float)
    original_price = db.Column(db.Float)
    is_discount = db.Column(db.Boolean, default=False)
    discount_start = db.Column(db.DateTime)
    discount_end = db.Column(db.DateTime)
    warranty_period = db.Column(db.DateTime)
    visibility = db.Column(db.Enum(VisibilityEnum), default=VisibilityEnum.private)
    vendor = db.relationship('Account', backref='vendor', lazy=True)
    variant = db.relationship('ProductVariant', backref='product', lazy=True)
    
    __table_args__ = (CheckConstraint('discount_end > discount_start', name='discount_date_check'),)

class ProductVariant(db.Model):
    product_variant_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    color_code = db.Column(db.String(50))
    color_name = db.Column(db.String(50))
    
    product_width = db.Column(db.Float)
    unit_width = db.Column(db.String(10)) 
    
    product_height = db.Column(db.Float)
    unit_height = db.Column(db.String(10))
    
    available = db.Column(db.Integer, nullable=False, default=0)

class ProductImage(db.Model):
    product_image_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    product_variant_id = db.Column(db.Integer, db.ForeignKey('product_variant.product_variant_id'), nullable=False)
    image_link = db.Column(db.String(255))

class Cart(db.Model):
    cart_id = db.Column(db.Integer, primary_key=True)
    owner_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    items = db.relationship('CartItem', backref='item', lazy=True, cascade="all, delete-orphan")

class CartItem(db.Model):
    cart_item_id = db.Column(db.Integer, primary_key=True)
    cart_id = db.Column(db.Integer, db.ForeignKey('cart.cart_id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    variant_id = db.Column(db.Integer, db.ForeignKey('product_variant.product_variant_id'), nullable=False)
    quantity = db.Column(db.Integer, default=1)
    price_at_addition = db.Column(db.Float)
    visibility = db.Column(db.Enum(VisibilityEnum), nullable=False)
    product = db.relationship('Product', backref='product', lazy=True)
    variant = db.relationship('ProductVariant', backref='variant', lazy=True)

class Orders(db.Model):
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
    variant_id = db.Column(db.Integer, db.ForeignKey('product_variant.product_variant_id'), nullable=False)
    quantity = db.Column(db.Integer, default=1)
    price_at_purchase = db.Column(db.Float, nullable=False)
    warranty_deadline = db.Column(db.DateTime)
    status = db.Column(db.Enum(OrderStatus), default=OrderStatus.pending)
    product = db.relationship('Product', backref='order_product', lazy=True)
    variant = db.relationship('ProductVariant', backref='order_variant', lazy=True)
    order_review = db.relationship('Review', backref='order_item', uselist=False)

class Review(db.Model):
    review_id = db.Column(db.Integer, primary_key=True)
    customer_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    order_item_id = db.Column(db.Integer, db.ForeignKey('order_item.order_item_id'), unique=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    rating = db.Column(db.Float)
    description = db.Column(db.Text)
    customer = db.relationship('Account', backref='reviews', lazy=True)
    review_order = db.relationship('OrderItem', backref='review', lazy=True)
    
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

class DiscountRequest(db.Model):
    __tablename__ = 'discount_request'
    request_id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.product_id'), nullable=False)
    vendor_id = db.Column(db.Integer, db.ForeignKey('account.account_id'), nullable=False)
    requested_price = db.Column(db.Float, nullable=False)
    discount_end = db.Column(db.DateTime, nullable=False)
    reason = db.Column(db.Text)
    status = db.Column(db.Enum(DiscountRequestStatus), default=DiscountRequestStatus.pending, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    reviewed_at = db.Column(db.DateTime)
    reviewed_by = db.Column(db.Integer, db.ForeignKey('account.account_id'))
    admin_note = db.Column(db.Text)

    product = db.relationship('Product', backref='discount_requests', lazy=True)
    vendor = db.relationship('Account', foreign_keys=[vendor_id], backref='submitted_discounts', lazy=True)
    reviewer = db.relationship('Account', foreign_keys=[reviewed_by], backref='reviewed_discounts', lazy=True)
    # helper
def expire_active_discounts():
    """Revert products whose discount window has passed."""
    now = datetime.utcnow()
    expired = Product.query.filter(
        Product.is_discount == True,
        Product.discount_end != None,
        Product.discount_end <= now
    ).all()
    for p in expired:
        p.price = p.original_price
        p.is_discount = False
        p.discount_start = None
        p.discount_end = None
    if expired:
        db.session.commit()


# Creates SQL Tables if not in database
with app.app_context():
    db.create_all()

# Sends user to index.html
@app.route('/')
def index():
    return render_template('index.html')

# Creates an account
@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        # Ensures both password boxes match before addng tables
        check_password=request.form.get('password')
        confirm_password=request.form.get('confirm_password')

        if check_password != confirm_password:
            return render_template('register.html', error='Passwords do not match', success=None)
        
        # hashes the password for encryption
        password_hash = generate_password_hash(request.form['password'])
        
        # Adds the account to the database
        new_user = Account(
            first_name=request.form['first_name'],
            last_name=request.form['last_name'],
            email=request.form['email'],
            username=request.form['username'],
            password_hash=password_hash,
            role=request.form['role']
        )
        db.session.add(new_user)
        db.session.commit()

        # Automatically generates shopping cart if account is customer
        if new_user.role.name == 'customer':
            new_cart = Cart(
                owner_id=new_user.account_id
            )
            db.session.add(new_cart)
            db.session.commit()
        
        return render_template('register.html', error=None, success="Account Created!")
    return render_template('register.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        # Using email since that's a unique attribute
        email = request.form['email']
        password = request.form['password']
        # Checks to see if account exists
        user = Account.query.filter_by(email=email).first()
        if user and check_password_hash(user.password_hash, password):

            # Saves information as a session
            session['first_name'] = user.first_name
            session['last_name'] = user.last_name
            session['user_id'] = user.account_id
            session['username'] = user.username
            session['email'] = user.email
            session['role'] = user.role.name

            # Sends user to their respective home pages
            if session['role'] == 'vendor':
                return redirect('/vendor')
            if session['role'] == 'admin':  
                return redirect('/admin') 
            return redirect('/')
        else:
            return render_template('login.html', error='Invalid email or password')
    return render_template('login.html')

@app.route('/logout')
def logout():
    # Clears session and logs out user entirely
    session.clear()
    return redirect('/login')

@app.route('/settings', methods=['GET', 'POST'])
def edit_account():
    if request.method == 'POST':
        user = Account.query.filter_by(email=session['email'], account_id=session['user_id']).first()

        if request.form['first_name']:
            user.first_name = request.form['first_name']
            session['first_name'] = user.first_name
        if request.form['last_name']:
            user.last_name = request.form['last_name']
            session['last_name'] = user.last_name
        if request.form['email']:
            user.email = request.form['email']
            session['email'] = user.email
        if request.form['username']:
            user.username = request.form['username']
            session['username'] = user.username
        if request.form['password']:
            check_password=request.form.get('password')
            confirm_password=request.form.get('confirm_password')
            if check_password != confirm_password:
                return render_template('settings.html', error='Passwords do not match', success=None)
            user.password_hash = generate_password_hash(request.form['password'])
        
        db.session.commit()
        return render_template('settings.html', error=None, success='Changes Saved')
    return render_template('settings.html')

# Sends to vendor's homepage
@app.route('/vendor')
def vendor_dashboard():
    return render_template('vendor.html')

# Displays all public products in pages
@app.route('/products')
@app.route('/products/<page>')
def get_products(page=1):
    expire_active_discounts()
    page = int(page)
    per_page = 10
    paginated = db.session.query(Product).paginate(page=page, per_page=per_page, error_out=False)
    products = paginated.items

    for product in products:
        avg = db.session.query(func.avg(Review.rating)).filter(Review.product_id == product.product_id).scalar()
        product.avg_review = avg if avg else 0
        
        count = db.session.query(func.count(Review.review_id)).filter(Review.product_id == product.product_id).scalar()
        product.review_count = count if count else 0

    print(products)
    return render_template('products.html', products=products, page=page, per_page=per_page)

@app.route('/add_product', methods=['GET', 'POST'])
def add_product():
    if request.method == 'POST':
        # Creates a new product tale
        new_product = Product(
            vendor_id=session['user_id'],
            name=request.form['name'],
            description=request.form['description'],
            price=float(request.form['price']),
            original_price=float(request.form['price'])
        )
        db.session.add(new_product)
        db.session.commit()

        # Add the product's first variant
        product = Product.query.filter_by(vendor_id=session['user_id'], name=request.form['name']).first()

        new_variant = ProductVariant(
            product_id=product.product_id,
            color_code=f"{request.form['color_code']}",
            color_name=request.form['color_name'],
            product_width=request.form['product_width'],
            unit_width=request.form['unit_width'],
            product_height=request.form['product_height'],
            unit_height=request.form['unit_height'],
            available=request.form['available']
        )
        db.session.add(new_variant)
        db.session.commit()
        # Sends to manage product for convenience
        return redirect('/manage_product')
    return render_template('add_product.html')

@app.route('/manage_product')
@app.route('/manage_product/<page>')
def my_products(page=1):
    account_id = session.get('user_id')
    page = int(page)
    # Ensures that user is the vendor
    if not account_id:
        return redirect('/login')
    
    per_page = 10
    # Displays all products made by the vendor
    paginated = db.session.query(Product).filter_by(vendor_id=account_id).paginate(page=page, per_page=per_page, error_out=False)
    products = paginated.items

    for product in products:
        avg = db.session.query(func.avg(Review.rating)).filter(Review.product_id == product.product_id).scalar()
        product.avg_review = avg if avg else 0
        
        count = db.session.query(func.count(Review.review_id)).filter(Review.product_id == product.product_id).scalar()
        product.review_count = count if count else 0

    print(products)
    return render_template('manage_product.html', products=products, page=page, per_page=per_page)

@app.route('/edit_product/<int:product_id>', methods=['GET', 'POST'])
def edit_product(product_id):
    product = Product.query.get_or_404(product_id)
    # Get current variants from DB
    existing_variants = ProductVariant.query.filter_by(product_id=product_id).all()

    if product.vendor_id != session.get('user_id'):
        return redirect('/')
    
    if request.method == 'POST':
        try:
            # 1. Update Main Product Details
            product.name = request.form.get('name')
            product.description = request.form.get('description')
            product.price = float(request.form.get('price'))
            product.visibility = request.form.get('visibility')

            # 2. Get data from form
            color_codes = request.form.getlist('color_code[]')
            color_names = request.form.getlist('color_name[]')
            availables = request.form.getlist('available[]')
            widths = request.form.getlist('product_width[]')
            unit_widths = request.form.getlist('unit_width[]')
            heights = request.form.getlist('product_height[]')
            unit_heights = request.form.getlist('unit_height[]')

            # 3. Synchronize Variants
            num_form_variants = len(color_codes)
            num_existing_variants = len(existing_variants)

            for i in range(max(num_form_variants, num_existing_variants)):
                if i < num_form_variants and i < num_existing_variants:
                    # UPDATE existing variant
                    v = existing_variants[i]
                    v.color_code = color_codes[i]
                    v.color_name = color_names[i]
                    v.available = int(availables[i])
                    v.product_width = float(widths[i])
                    v.unit_width = unit_widths[i]
                    v.product_height = float(heights[i])
                    v.unit_height = unit_heights[i]
                
                elif i < num_form_variants:
                    # ADD new variant (form has more than DB)
                    new_variant = ProductVariant(
                        product_id=product.product_id,
                        color_code=color_codes[i],
                        color_name=color_names[i],
                        available=int(availables[i]),
                        product_width=float(widths[i]),
                        unit_width=unit_widths[i],
                        product_height=float(heights[i]),
                        unit_height=unit_heights[i]
                    )
                    db.session.add(new_variant)
                
                elif i < num_existing_variants:
                    # DELETE removed variant (DB has more than form)
                    # Note: This will STILL fail if this specific variant is in a cart.
                    db.session.delete(existing_variants[i])

            db.session.commit()
            return redirect(url_for('edit_product', product_id=product.product_id))

        except Exception as e:
            db.session.rollback()
            # If a delete fails here, it's because that specific variant is in a cart
            return render_template('edit_product.html', product=product, variants=existing_variants, error=f"Update failed: {str(e)}")

    return render_template('edit_product.html', product=product, variants=existing_variants)

@app.route('/delete_variant/<int:variant_id>', methods=['DELETE'])
def delete_variant(variant_id):
    variant = ProductVariant.query.get_or_404(variant_id)
    product = Product.query.get_or_404(variant.product_id)
    if product.vendor_id != session.get('user_id'):
        return '', 403

    db.session.delete(variant)
    db.session.commit()
    return '', 204

@app.route('/view_product/<int:product_id>')
def view_product(product_id):
    expire_active_discounts()
    product = Product.query.get_or_404(product_id)
    variants = ProductVariant.query.filter_by(product_id=product_id).all()
    reviews = Review.query.filter_by(product_id=product_id).all()
    query = Orders.query.options(joinedload(Orders.items))
    avg_review = db.session.query(func.avg(Review.rating)).filter(Review.product_id==product_id).scalar()

    count = db.session.query(func.count(Review.review_id)).filter(Review.product_id == product.product_id).scalar()
    product.review_count = count if count else 0

    if session['role'] == 'customer':
        orders = query.filter_by(customer_id=session['user_id']).all()

    elif session['role'] == 'vendor':
        orders = query.join(OrderItem).join(Product)\
                      .filter(Product.vendor_id == session['user_id']).all()

    return render_template('view_product.html', product=product, variants=variants, reviews=reviews, orders=orders, avg_review=avg_review)

@app.route('/add_to_cart/<int:product_id>', methods=['POST'])
def add_to_cart(product_id):
    product = Product.query.get_or_404(product_id)
    variant_id = request.form.get('user_choice', 0, type=int)
    cart = db.session.query(Cart).filter_by(owner_id=session['user_id']).first()

    # Makes sure that product (and it's variant) doesn't already exist in the cart
    cart_check = db.session.query(CartItem).filter_by(cart_id=cart.cart_id, product_id=product_id, variant_id=variant_id).all()

    # If it does, it increases the quantity instead
    if cart_check:
        item = db.session.query(CartItem).filter_by(cart_id=cart.cart_id, product_id=product_id, variant_id=variant_id).first()
        item.quantity += 1

    # Adds product as a cart item to database
    else:
        new_item = CartItem (
            cart_id=cart.cart_id,
            product_id=product.product_id,
            variant_id=variant_id,
            quantity=1,
            price_at_addition=product.price,
            visibility=product.visibility
        )
        db.session.add(new_item)
    db.session.commit()
    return redirect(f'/view_product/{product.product_id}')

# Displays Cart items
@app.route('/cart')
def view_cart():
    
    cart = db.session.query(Cart).filter_by(owner_id=session['user_id']).first()
    cart_items = CartItem.query.filter_by(cart_id=cart.cart_id).all()

    total_price = sum(item.product.price * item.quantity for item in cart_items)

    return render_template('cart.html', cart=cart, cart_items=cart_items, total_price=total_price)

@app.route('/update_cart/<int:cart_item_id>/<action>')
def update_cart(cart_item_id, action):
    item = CartItem.query.get_or_404(cart_item_id)

    if action == 'increase':
        item.quantity += 1
        db.session.commit()
    elif action == 'decrease' and item.quantity > 1:
        item.quantity -= 1
        db.session.commit()
    elif action == 'decrease' and item.quantity <= 1:
        db.session.delete(item)
        db.session.commit()
    
    return redirect('/cart')

@app.route('/checkout/<int:cart_id>', methods=['GET', 'POST'])
def checkout(cart_id):
    cart = Cart.query.get_or_404(cart_id)

    if cart.owner_id != session['user_id']:
        return redirect('/')
    
    if request.method == 'POST':
        cart_items = CartItem.query.filter_by(cart_id=cart_id).all()

        total_items = sum(1 * item.quantity for item in cart_items)
        total_amount = sum(item.product.price * item.quantity for item in cart_items)

        new_order = Orders(
            customer_id = session['user_id'],
            total_items = total_items,
            total_amount = total_amount
        )

        db.session.add(new_order)
        db.session.commit()
        
        for item in cart_items:
            if item.product.visibility.name == 'public':
                product_variant = db.session.query(ProductVariant).filter_by(product_variant_id=item.variant_id).first()
                if product_variant.available > 1:
                    new_order_items = OrderItem(
                        order_id = new_order.order_id,
                        product_id = item.product_id,
                        variant_id = item.variant_id,
                        quantity = item.quantity,
                        price_at_purchase = item.price_at_addition * item.quantity,
                        warranty_deadline = item.product.warranty_period
                    )
                    product_variant.available -= item.quantity

                    db.session.add(new_order_items)
        
        clear_items = db.session.query(CartItem).filter_by(cart_id=cart_id).delete()
        db.session.commit()
        return redirect(f'/order_placed/{new_order.order_id}')
    return render_template('payment.html', cart=cart, cart_id=cart_id)

@app.route('/order_placed/<int:order_id>')
def order_confirmed(order_id):
    return render_template('order_confirmed.html')

from sqlalchemy.orm import joinedload

@app.route('/orders')
def get_orders():
    query = Orders.query.options(joinedload(Orders.items))

    if session['role'] == 'customer':
        orders = query.filter_by(customer_id=session['user_id']).all()

    elif session['role'] == 'vendor':
        orders = query.join(OrderItem).join(Product)\
                      .filter(Product.vendor_id == session['user_id']).all()
        
    return render_template('orders.html', orders=orders)

@app.route('/view_order/<int:order_item_id>')
def view_order(order_item_id):
    order_item = OrderItem.query.get_or_404(order_item_id)

    if order_item.order.customer_id == session['user_id']:
        return render_template('view_order.html', order_item=order_item)
    
    elif order_item.product.vendor_id == session['user_id']:
        return render_template('view_order.html', order_item=order_item)
    
    return redirect('/orders')
    
@app.route('/publish_review/<int:order_item_id>/<action>', methods=['POST'])
def publish_review(order_item_id, action):
    order_check = OrderItem.query.get_or_404(order_item_id)
    product_tempoary = Product.query.filter_by(product_id = order_check.product.product_id).first()

    if order_check:
        new_review = Review(
            customer_id = session['user_id'],
            order_item_id = order_item_id,
            product_id = product_tempoary.product_id,
            rating = float(request.form.get('rating')),
            description = str(request.form.get('description'))
        )
        db.session.add(new_review)
        db.session.commit()
    
    if action == 'order_display':
        return redirect(f'/view_order/{order_item_id}')
    elif action == 'product_display':
        return redirect(f'/view_product/{product_tempoary.product_id}')

@app.route('/request_discount/<int:product_id>', methods=['POST'])
def request_discount(product_id):
    if session.get('role') != 'vendor':
        return redirect('/')
    product = Product.query.get_or_404(product_id)
    if product.vendor_id != session['user_id']:
        return redirect('/')

    existing = DiscountRequest.query.filter_by(
        product_id=product_id,
        status=DiscountRequestStatus.pending
    ).first()
    if existing:
        variants = ProductVariant.query.filter_by(product_id=product_id).all()
        return render_template('edit_product.html', product=product, variants=variants,
                               pending_discount=existing,
                               error="A discount request is already pending admin approval.")
    try:
        requested_price = float(request.form['requested_price'])
        discount_end = datetime.strptime(request.form['discount_end'], '%Y-%m-%dT%H:%M')
        reason = request.form.get('reason', '')

        if requested_price <= 0:
            raise ValueError("Price must be positive.")
        if requested_price >= product.price:
            raise ValueError("Discount price must be lower than the current price.")
        if discount_end <= datetime.utcnow():
            raise ValueError("Expiration date must be in the future.")

        new_request = DiscountRequest(
            product_id=product_id,
            vendor_id=session['user_id'],
            requested_price=requested_price,
            discount_end=discount_end,
            reason=reason,
            status=DiscountRequestStatus.pending
        )
        db.session.add(new_request)
        db.session.commit()

        variants = ProductVariant.query.filter_by(product_id=product_id).all()
        return render_template('edit_product.html', product=product, variants=variants,
                               pending_discount=new_request,
                               success="Discount request submitted! Awaiting admin approval.")
    except ValueError as e:
        variants = ProductVariant.query.filter_by(product_id=product_id).all()
        pending_discount = DiscountRequest.query.filter_by(
            product_id=product_id, status=DiscountRequestStatus.pending).first()
        return render_template('edit_product.html', product=product, variants=variants,
                               pending_discount=pending_discount, error=str(e))


@app.route('/cancel_discount_request/<int:request_id>', methods=['POST'])
def cancel_discount_request(request_id):
    if session.get('role') != 'vendor':
        return redirect('/')
    dr = DiscountRequest.query.get_or_404(request_id)
    if dr.vendor_id != session['user_id']:
        return redirect('/')
    if dr.status == DiscountRequestStatus.pending:
        db.session.delete(dr)
        db.session.commit()
    return redirect(f'/edit_product/{dr.product_id}')


@app.route('/admin')
def admin_dashboard():
    if session.get('role') != 'admin':
        return redirect('/')
    pending_count = DiscountRequest.query.filter_by(status=DiscountRequestStatus.pending).count()
    return render_template('admin.html', pending_count=pending_count)


@app.route('/admin/discounts')
def admin_discounts():
    if session.get('role') != 'admin':
        return redirect('/')
    expire_active_discounts()

    status_filter = request.args.get('status', 'pending')
    try:
        status_enum = DiscountRequestStatus[status_filter]
    except KeyError:
        status_enum = DiscountRequestStatus.pending

    requests = (
        DiscountRequest.query
        .filter_by(status=status_enum)
        .order_by(DiscountRequest.created_at.desc())
        .all()
    )
    return render_template('admin_discounts.html', requests=requests,
                           status_filter=status_filter, now=datetime.utcnow())


@app.route('/admin/discounts/<int:request_id>/approve', methods=['POST'])
def approve_discount(request_id):
    if session.get('role') != 'admin':
        return redirect('/')
    dr = DiscountRequest.query.get_or_404(request_id)
    if dr.status != DiscountRequestStatus.pending:
        return redirect('/admin/discounts')

    product = Product.query.get(dr.product_id)
    product.original_price = product.original_price or product.price
    product.price = dr.requested_price
    product.is_discount = True
    product.discount_start = datetime.utcnow()
    product.discount_end = dr.discount_end

    dr.status = DiscountRequestStatus.approved
    dr.reviewed_at = datetime.utcnow()
    dr.reviewed_by = session['user_id']
    dr.admin_note = request.form.get('admin_note', '')

    db.session.commit()
    return redirect('/admin/discounts')


@app.route('/admin/discounts/<int:request_id>/reject', methods=['POST'])
def reject_discount(request_id):
    if session.get('role') != 'admin':
        return redirect('/')
    dr = DiscountRequest.query.get_or_404(request_id)
    if dr.status != DiscountRequestStatus.pending:
        return redirect('/admin/discounts')

    dr.status = DiscountRequestStatus.rejected
    dr.reviewed_at = datetime.utcnow()
    dr.reviewed_by = session['user_id']
    dr.admin_note = request.form.get('admin_note', '')

    db.session.commit()
    return redirect('/admin/discounts')

if __name__ == '__main__':
    app.run(debug=True)