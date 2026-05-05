from flask import Flask, render_template, request, redirect, url_for, session
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import event, CheckConstraint
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
            price=request.form['price']
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

    print(products)
    return render_template('manage_product.html', products=products, page=page, per_page=per_page)

@app.route('/edit_product/<int:product_id>', methods=['GET', 'POST'])
def edit_product(product_id):
    product = Product.query.get_or_404(product_id)

    if product.vendor_id != session['user_id']:
        redirect('/')
    
    if request.method == 'POST':
        try:
            # 1. Update Main Product Details
            product.name = request.form.get('name')
            product.description = request.form.get('description')
            product.price = float(request.form.get('price'))
            product.visibility = request.form.get('visibility')
            
            # 2. Handle Variants
            # We get lists for every field
            color_codes = request.form.getlist('color_code')
            color_names = request.form.getlist('color_name')
            availables = request.form.getlist('available')
            widths = request.form.getlist('product_width')
            unit_widths = request.form.getlist('unit_width')
            heights = request.form.getlist('product_height')
            unit_heights = request.form.getlist('unit_height')

            # Delete existing variants associated with this product
            ProductVariant.query.filter_by(product_id=product_id).delete()

            # Re-add variants from the form data
            for i in range(len(color_codes)):
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

            db.session.commit()
            
            # Refresh data for the template
            variants = ProductVariant.query.filter_by(product_id=product_id).all()
            return render_template('edit_product.html', product=product, variants=variants, success="Product updated successfully!")

        except Exception as e:
            db.session.rollback()
            print(f"Error: {e}")
            variants = ProductVariant.query.filter_by(product_id=product_id).all()
            return render_template('edit_product.html', product=product, variants=variants, error=f"Update failed: {str(e)}")

    # GET Request Logic
    variants = ProductVariant.query.filter_by(product_id=product_id).all()
    return render_template('edit_product.html', product=product, variants=variants)

# A dedicated product page for a specific product
@app.route('/view_product/<int:product_id>')
def view_product(product_id):
    expire_active_discounts()
    product = Product.query.get_or_404(product_id)
    variants = ProductVariant.query.filter_by(product_id=product_id).all()
    reviews = Review.query.filter_by(product_id=product_id).all()
    return render_template('view_product.html', product=product, variants=variants, reviews=reviews)

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
    return redirect(f'/view_product/{product.product_id}', success='Item Added to Cart')

# Displays Cart items
@app.route('/cart')
def view_cart():
    cart = db.session.query(Cart).filter_by(owner_id=session['user_id']).first()
    cart_items = CartItem.query.filter_by(cart_id=cart.cart_id).all()
    return render_template('cart.html', cart=cart, cart_items=cart_items)

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