from datetime import date, datetime, timedelta, timezone
from email.message import EmailMessage
from functools import lru_cache
import hmac
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import smtplib
import ssl
from urllib.parse import quote, urlencode, urlparse
from urllib.error import HTTPError, URLError
from urllib.request import Request as UrlRequest, urlopen
from uuid import uuid4

from dotenv import load_dotenv
from flask import Flask, flash, g, redirect, render_template, request, send_from_directory, session, url_for
from werkzeug.utils import secure_filename
from werkzeug.security import check_password_hash, generate_password_hash

try:
    from supabase import create_client
    from supabase_auth.errors import AuthApiError, AuthSessionMissingError
except ImportError:
    create_client = None
    AuthApiError = None
    AuthSessionMissingError = None

BASE_DIR = Path(__file__).resolve().parent
DATABASE = BASE_DIR / "instance" / "booking_os.sqlite3"
ROOM_PHOTO_DIRECTORY = BASE_DIR / "instance" / "room_photos"
ROOM_PHOTO_BUCKET = "room-photos"
ONLINE_HOLD_MINUTES = 30
TRIAL_DAYS = 30
MONTHLY_PLAN_AMOUNT = 80_000
ANNUAL_PLAN_AMOUNT = 800_000
PAYSTACK_API_BASE = "https://api.paystack.co"
DEFAULT_HOTEL_ID = "00000000-0000-0000-0000-000000000001"
MAX_ROOM_PHOTO_BYTES = 5 * 1024 * 1024
MAX_ROOM_PHOTOS = 3
ALLOWED_ROOM_PHOTO_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
NIGERIAN_STATES = (
    "Abia", "Adamawa", "Akwa Ibom", "Anambra", "Bauchi", "Bayelsa",
    "Benue", "Borno", "Cross River", "Delta", "Ebonyi", "Edo", "Ekiti",
    "Enugu", "Federal Capital Territory", "Gombe", "Imo", "Jigawa",
    "Kaduna", "Kano", "Katsina", "Kebbi", "Kogi", "Kwara", "Lagos",
    "Nasarawa", "Niger", "Ogun", "Ondo", "Osun", "Oyo", "Plateau",
    "Rivers", "Sokoto", "Taraba", "Yobe", "Zamfara",
)
PUBLIC_PRICE_RANGES = (
    ("10000-50000", "₦10,000–₦50,000", 10_000, 50_001),
    ("50000-100000", "Above ₦50,000–₦100,000", 50_001, 100_001),
    ("100000-200000", "Above ₦100,000–₦200,000", 100_001, 200_001),
    ("200000-plus", "Above ₦200,000", 200_001, None),
)
load_dotenv(BASE_DIR / ".env")
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://frmekmypefrwvocepjmg.supabase.co")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY", "") or os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
SUPABASE_ENABLED = bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SECRET_KEY and create_client)
FLASK_SECRET_KEY = os.getenv("FLASK_SECRET_KEY")
if os.getenv("RAILWAY_ENVIRONMENT") and not FLASK_SECRET_KEY:
    raise RuntimeError("Set FLASK_SECRET_KEY in Railway service variables before deploying.")
if os.getenv("RAILWAY_ENVIRONMENT") and SUPABASE_ANON_KEY and not SUPABASE_SECRET_KEY:
    raise RuntimeError("Set SUPABASE_SECRET_KEY in Railway service variables before enabling Supabase.")

app = Flask(__name__)
app.config["SECRET_KEY"] = FLASK_SECRET_KEY or "local-development-key-change-before-deploy"
app.config["DATABASE"] = DATABASE
app.config["SUPABASE_ENABLED"] = SUPABASE_ENABLED
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
app.config["SESSION_COOKIE_SECURE"] = bool(os.getenv("RAILWAY_ENVIRONMENT"))
app.config["MAX_CONTENT_LENGTH"] = (
    MAX_ROOM_PHOTOS * MAX_ROOM_PHOTO_BYTES + 1024 * 1024
)


class SupabaseSessionExpired(Exception):
    def __init__(self, role):
        self.role = role


@lru_cache(maxsize=1)
def get_supabase_admin():
    if not SUPABASE_ENABLED:
        return None
    return create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)


def get_supabase_auth():
    if not SUPABASE_ENABLED:
        return None
    return create_client(SUPABASE_URL, SUPABASE_ANON_KEY)


def get_request_supabase():
    if not SUPABASE_ENABLED or not session.get("supabase_access_token"):
        return None
    if g.get("supabase_client") is not None:
        return g.supabase_client
    client = get_supabase_auth()
    try:
        auth_response = client.auth.set_session(
            session["supabase_access_token"],
            session.get("supabase_refresh_token", ""),
        )
    except (AuthApiError, AuthSessionMissingError) as error:
        role = session.get("user_role", "reception")
        session.clear()
        raise SupabaseSessionExpired(role) from error
    if not auth_response.session:
        role = session.get("user_role", "reception")
        session.clear()
        raise SupabaseSessionExpired(role)
    session["supabase_access_token"] = auth_response.session.access_token
    session["supabase_refresh_token"] = auth_response.session.refresh_token
    g.supabase_client = client
    return client


def auth_email(username):
    import hashlib

    username = username.strip().lower()
    return f"{hashlib.sha256(username.encode()).hexdigest()}@login.labim.invalid"

def get_db():
    if "db" not in g:
        DATABASE.parent.mkdir(exist_ok=True)
        g.db = sqlite3.connect(DATABASE)
        g.db.row_factory = sqlite3.Row
    return g.db


def current_hotel_id():
    return session.get("hotel_id", DEFAULT_HOTEL_ID)


def hotel_details(hotel_id=None):
    hotel_id = hotel_id or current_hotel_id()
    if SUPABASE_ENABLED:
        result = get_supabase_admin().table("hotels").select(
            "id, name, slug, address, city, state"
        ).eq("id", hotel_id).limit(1).execute().data
        return result[0] if result else None
    row = get_db().execute(
        "SELECT id, name, slug, address, city, state FROM hotels WHERE id = ?",
        (hotel_id,),
    ).fetchone()
    return dict(row) if row else None


def public_hotels():
    if SUPABASE_ENABLED:
        hotels = get_supabase_admin().table("hotels").select(
            "id, name, slug, address, city, state"
        ).eq("is_active", True).order("name").execute().data
    else:
        hotels = [
            dict(row) for row in get_db().execute(
                """SELECT id, name, slug, address, city, state FROM hotels
                WHERE is_active = 1 ORDER BY name"""
            ).fetchall()
        ]
    state_filter = request.args.get("state", "").strip()
    city_filter = request.args.get("city", "").strip().casefold()
    if state_filter in NIGERIAN_STATES:
        hotels = [hotel for hotel in hotels if hotel["state"] == state_filter]
    elif state_filter:
        hotels = []
    if city_filter:
        hotels = [
            hotel for hotel in hotels
            if city_filter in (hotel.get("city") or "").casefold()
        ]
    return hotels


def subscription_record(hotel_id):
    if SUPABASE_ENABLED:
        rows = get_supabase_admin().table("hotel_subscriptions").select(
            "*"
        ).eq("hotel_id", hotel_id).limit(1).execute().data
        return rows[0] if rows else None
    row = get_db().execute(
        "SELECT * FROM hotel_subscriptions WHERE hotel_id = ?",
        (hotel_id,),
    ).fetchone()
    return dict(row) if row else None


def subscription_access(hotel_id):
    record = subscription_record(hotel_id)
    if not record or record["status"] == "legacy":
        return {"allowed": True, "status": "legacy", "record": record}
    now = datetime.now(timezone.utc)
    if record["status"] == "trial" and record.get("trial_ends_at"):
        trial_ends = datetime.fromisoformat(record["trial_ends_at"])
        if trial_ends.tzinfo is None:
            trial_ends = trial_ends.replace(tzinfo=timezone.utc)
        return {
            "allowed": now < trial_ends,
            "status": "trial" if now < trial_ends else "expired",
            "expires_at": trial_ends,
            "record": record,
        }
    if record["status"] == "active" and record.get("paid_until"):
        paid_until = datetime.fromisoformat(record["paid_until"])
        if paid_until.tzinfo is None:
            paid_until = paid_until.replace(tzinfo=timezone.utc)
        return {
            "allowed": now < paid_until,
            "status": "active" if now < paid_until else "expired",
            "expires_at": paid_until,
            "record": record,
        }
    return {"allowed": False, "status": "expired", "record": record}


def ensure_legacy_subscription(hotel_id):
    if subscription_record(hotel_id):
        return
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    legacy_subscription = {
        "hotel_id": hotel_id,
        "plan": "legacy",
        "status": "legacy",
        "billing_email": "",
        "updated_at": now,
    }
    if SUPABASE_ENABLED:
        get_supabase_admin().table("hotel_subscriptions").insert(
            legacy_subscription
        ).execute()
        return
    db = get_db()
    db.execute(
        """INSERT OR IGNORE INTO hotel_subscriptions
        (hotel_id, plan, status, billing_email, updated_at)
        VALUES (?, 'legacy', 'legacy', '', ?)""",
        (hotel_id, now),
    )
    db.commit()


def create_hotel_subscription(hotel_id, plan, billing_email):
    now = datetime.now(timezone.utc)
    is_trial = plan == "trial"
    subscription = {
        "hotel_id": hotel_id,
        "plan": "trial" if is_trial else plan,
        "status": "trial" if is_trial else "pending",
        "trial_started_at": now.isoformat(timespec="seconds") if is_trial else None,
        "trial_ends_at": (
            (now + timedelta(days=TRIAL_DAYS)).isoformat(timespec="seconds")
            if is_trial else None
        ),
        "paid_until": None,
        "billing_email": billing_email,
        "pending_reference": None,
        "pending_plan": None if is_trial else plan,
        "updated_at": now.isoformat(timespec="seconds"),
    }
    if SUPABASE_ENABLED:
        get_supabase_admin().table("hotel_subscriptions").upsert(
            subscription
        ).execute()
    else:
        get_db().execute(
            """INSERT INTO hotel_subscriptions
            (hotel_id, plan, status, trial_started_at, trial_ends_at, paid_until,
             billing_email, pending_reference, pending_plan, updated_at)
            VALUES (:hotel_id, :plan, :status, :trial_started_at, :trial_ends_at,
             :paid_until, :billing_email, :pending_reference, :pending_plan, :updated_at)
            ON CONFLICT(hotel_id) DO UPDATE SET plan = excluded.plan,
             status = excluded.status, trial_started_at = excluded.trial_started_at,
             trial_ends_at = excluded.trial_ends_at, paid_until = excluded.paid_until,
             billing_email = excluded.billing_email,
             pending_reference = excluded.pending_reference,
             pending_plan = excluded.pending_plan, updated_at = excluded.updated_at""",
            subscription,
        )
        get_db().commit()


def paystack_secret_key():
    key = os.getenv("PAYSTACK_SECRET_KEY", "").strip()
    if not key:
        raise ValueError("Paystack payments are not configured yet. Please contact the hotel platform administrator.")
    return key


def paystack_request(path, method="GET", payload=None):
    key = paystack_secret_key()
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = UrlRequest(
        f"{PAYSTACK_API_BASE}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    req.headers["Authorization"] = "Bearer " + key
    try:
        with urlopen(req, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        app.logger.warning("Paystack API returned HTTP %s for %s", error.code, path)
        raise ValueError("Paystack could not process the request. Please try again.") from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        app.logger.exception("Paystack request failed for %s", path)
        raise ValueError("Could not reach Paystack. Please try again.") from error
    if not result.get("status") or not isinstance(result.get("data"), dict):
        app.logger.error("Paystack returned an unsuccessful response for %s", path)
        raise ValueError("Paystack could not process the request. Please try again.")
    return result["data"]


def initialize_subscription_payment(hotel_id, plan):
    if plan not in {"monthly", "annual"}:
        raise ValueError("Choose a valid subscription plan.")
    subscription = subscription_record(hotel_id)
    if not subscription or not subscription.get("billing_email"):
        raise ValueError("Add a valid billing email before subscribing.")
    amount = MONTHLY_PLAN_AMOUNT if plan == "monthly" else ANNUAL_PLAN_AMOUNT
    reference = f"hotel-{uuid4().hex}"
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if SUPABASE_ENABLED:
        admin = get_supabase_admin()
        admin.table("hotel_subscription_payments").insert({
            "reference": reference,
            "hotel_id": hotel_id,
            "plan": plan,
            "amount": amount * 100,
            "status": "pending",
            "created_at": now,
        }).execute()
        admin.table("hotel_subscriptions").update({
            "pending_reference": reference,
            "pending_plan": plan,
            "updated_at": now,
        }).eq("hotel_id", hotel_id).execute()
    else:
        db = get_db()
        db.execute("BEGIN IMMEDIATE")
        db.execute(
            """INSERT INTO hotel_subscription_payments
            (reference, hotel_id, plan, amount, status, created_at)
            VALUES (?, ?, ?, ?, 'pending', ?)""",
            (reference, hotel_id, plan, amount * 100, now),
        )
        db.execute(
            """UPDATE hotel_subscriptions SET pending_reference = ?,
            pending_plan = ?, updated_at = ? WHERE hotel_id = ?""",
            (reference, plan, now, hotel_id),
        )
        db.commit()
    try:
        data = paystack_request("/transaction/initialize", "POST", {
            "email": subscription["billing_email"],
            "amount": amount * 100,
            "currency": "NGN",
            "reference": reference,
            "callback_url": url_for("paystack_callback", _external=True),
            "metadata": {
                "hotel_id": hotel_id,
                "plan": plan,
                "custom_fields": [{
                    "display_name": "Hotel",
                    "variable_name": "hotel_id",
                    "value": hotel_id,
                }],
            },
        })
    except ValueError:
        fail_subscription_payment(reference, hotel_id)
        raise
    authorization_url = data.get("authorization_url")
    checkout = urlparse(authorization_url or "")
    if checkout.scheme != "https" or checkout.hostname != "checkout.paystack.com":
        fail_subscription_payment(reference, hotel_id)
        raise RuntimeError("Paystack did not return a secure checkout URL.")
    return authorization_url


def fail_subscription_payment(reference, hotel_id):
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if SUPABASE_ENABLED:
        admin = get_supabase_admin()
        admin.table("hotel_subscription_payments").update({
            "status": "failed",
        }).eq("reference", reference).eq("hotel_id", hotel_id).eq(
            "status", "pending"
        ).execute()
        admin.table("hotel_subscriptions").update({
            "pending_reference": None,
            "pending_plan": None,
            "updated_at": now,
        }).eq("hotel_id", hotel_id).eq(
            "pending_reference", reference
        ).execute()
        return
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    db.execute(
        """UPDATE hotel_subscription_payments SET status = 'failed'
        WHERE reference = ? AND hotel_id = ? AND status = 'pending'""",
        (reference, hotel_id),
    )
    db.execute(
        """UPDATE hotel_subscriptions SET pending_reference = NULL,
        pending_plan = NULL, updated_at = ?
        WHERE hotel_id = ? AND pending_reference = ?""",
        (now, hotel_id, reference),
    )
    db.commit()


def activate_subscription_payment(reference, transaction_id, amount, currency):
    if SUPABASE_ENABLED:
        result = get_supabase_admin().rpc(
            "activate_hotel_subscription_payment",
            {
                "p_reference": reference,
                "p_transaction_id": str(transaction_id),
                "p_amount": amount,
                "p_currency": currency,
            },
        ).execute().data
        if not result:
            raise ValueError("The Paystack payment does not match a pending hotel subscription.")
        return result
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    payment = db.execute(
        "SELECT * FROM hotel_subscription_payments WHERE reference = ?",
        (reference,),
    ).fetchone()
    if not payment:
        db.rollback()
        raise ValueError("No subscription payment exists for this reference.")
    if payment["status"] == "paid":
        db.commit()
        return True
    expected_amount = (
        MONTHLY_PLAN_AMOUNT * 100
        if payment["plan"] == "monthly"
        else ANNUAL_PLAN_AMOUNT * 100
    )
    if (
        payment["status"] != "pending"
        or payment["amount"] != amount
        or payment["amount"] != expected_amount
        or currency != "NGN"
    ):
        db.rollback()
        raise ValueError("The Paystack payment does not match the pending subscription.")
    now = datetime.now(timezone.utc)
    subscription = db.execute(
        """SELECT paid_until, pending_reference, pending_plan
        FROM hotel_subscriptions WHERE hotel_id = ?""",
        (payment["hotel_id"],),
    ).fetchone()
    if not subscription:
        db.rollback()
        raise ValueError("The hotel subscription record could not be found.")
    current_expiry = subscription["paid_until"]
    start = now
    if current_expiry:
        parsed_expiry = datetime.fromisoformat(current_expiry)
        if parsed_expiry.tzinfo is None:
            parsed_expiry = parsed_expiry.replace(tzinfo=timezone.utc)
        if parsed_expiry > start:
            start = parsed_expiry
    paid_until = start + timedelta(days=30 if payment["plan"] == "monthly" else 365)
    db.execute(
        """UPDATE hotel_subscription_payments SET status = 'paid',
        paystack_transaction_id = ?, paid_at = ? WHERE reference = ?""",
        (str(transaction_id), now.isoformat(timespec="seconds"), reference),
    )
    db.execute(
        """UPDATE hotel_subscriptions SET plan = ?, status = 'active',
        paid_until = ?,
        pending_reference = CASE WHEN pending_reference = ? THEN NULL
            ELSE pending_reference END,
        pending_plan = CASE WHEN pending_reference = ? THEN NULL
            ELSE pending_plan END,
        updated_at = ? WHERE hotel_id = ?""",
        (
            payment["plan"], paid_until.isoformat(timespec="seconds"),
            reference, reference,
            now.isoformat(timespec="seconds"), payment["hotel_id"],
        ),
    )
    db.commit()
    return True


@app.teardown_appcontext
def close_db(exception=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def password_is_valid(stored_password, submitted_password):
    if stored_password.startswith(("scrypt:", "pbkdf2:", "argon2:")):
        return check_password_hash(stored_password, submitted_password)
    return stored_password == submitted_password


def init_db():
    db = get_db()
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS hotels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            slug TEXT NOT NULL UNIQUE,
            address TEXT NOT NULL DEFAULT '',
            city TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT '',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS rooms (
            number TEXT NOT NULL,
            hotel_id TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
            name TEXT NOT NULL,
            beds INTEGER NOT NULL,
            rate INTEGER NOT NULL,
            status TEXT NOT NULL,
            PRIMARY KEY (hotel_id, number)
        );
        CREATE TABLE IF NOT EXISTS reservations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hotel_id TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
            guest_name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT NOT NULL,
            room_number TEXT NOT NULL,
            check_in TEXT NOT NULL,
            check_out TEXT NOT NULL,
            amount INTEGER NOT NULL,
            amount_paid INTEGER NOT NULL DEFAULT 0,
            payment_method TEXT NOT NULL,
            payment_status TEXT NOT NULL DEFAULT 'pending',
            status TEXT NOT NULL DEFAULT 'checked_in',
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hotel_id TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
            role TEXT NOT NULL,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(hotel_id, role)
        );
        CREATE TABLE IF NOT EXISTS payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hotel_id TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
            reservation_id INTEGER NOT NULL,
            room_number TEXT NOT NULL,
            amount INTEGER NOT NULL,
            balance INTEGER NOT NULL,
            method TEXT NOT NULL,
            received_by TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS app_migrations (
            name TEXT PRIMARY KEY
        );
        CREATE TABLE IF NOT EXISTS online_room_listings (
            hotel_id TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000001',
            room_number TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            photo_path TEXT NOT NULL DEFAULT '',
            photo_paths TEXT NOT NULL DEFAULT '[]',
            enabled INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (hotel_id, room_number)
        );
        CREATE TABLE IF NOT EXISTS online_booking_settings (
            hotel_id TEXT PRIMARY KEY,
            bank_name TEXT NOT NULL DEFAULT '',
            account_name TEXT NOT NULL DEFAULT '',
            account_number TEXT NOT NULL DEFAULT '',
            reception_whatsapp TEXT NOT NULL DEFAULT '',
            reception_email TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS hotel_subscriptions (
            hotel_id TEXT PRIMARY KEY,
            plan TEXT NOT NULL,
            status TEXT NOT NULL,
            trial_started_at TEXT,
            trial_ends_at TEXT,
            paid_until TEXT,
            billing_email TEXT NOT NULL DEFAULT '',
            pending_reference TEXT,
            pending_plan TEXT,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS hotel_subscription_payments (
            reference TEXT PRIMARY KEY,
            hotel_id TEXT NOT NULL,
            plan TEXT NOT NULL,
            amount INTEGER NOT NULL,
            status TEXT NOT NULL,
            paystack_transaction_id TEXT,
            created_at TEXT NOT NULL,
            paid_at TEXT
        );
        """
    )
    db.execute(
        """CREATE UNIQUE INDEX IF NOT EXISTS hotel_subscription_transaction_idx
        ON hotel_subscription_payments(paystack_transaction_id)
        WHERE paystack_transaction_id IS NOT NULL"""
    )
    hotel_columns = {
        column["name"] for column in db.execute("PRAGMA table_info(hotels)")
    }
    for column in ("address", "city", "state"):
        if column not in hotel_columns:
            db.execute(
                f"ALTER TABLE hotels ADD COLUMN {column} TEXT NOT NULL DEFAULT ''"
            )
    db.execute(
        """INSERT OR IGNORE INTO hotels (id, name, slug, is_active, created_at)
        VALUES (?, 'Labim Hotel and Suite', 'labim-hotel-and-suite', 1, CURRENT_TIMESTAMP)""",
        (DEFAULT_HOTEL_ID,),
    )
    for table in ("rooms", "reservations", "payments", "online_room_listings"):
        columns = {column[1] for column in db.execute(f"PRAGMA table_info({table})")}
        if "hotel_id" not in columns:
            db.execute(
                f"ALTER TABLE {table} ADD COLUMN hotel_id TEXT NOT NULL DEFAULT '{DEFAULT_HOTEL_ID}'"
            )
    users_info = list(db.execute("PRAGMA table_info(users)"))
    users_indexes = db.execute("PRAGMA index_list(users)").fetchall()
    if "hotel_id" not in {column[1] for column in users_info} or any(
        index["unique"] and index["origin"] == "u"
        and [
            column["name"] for column in db.execute(
                f"PRAGMA index_info({index['name']})"
            )
        ] == ["role"]
        for index in users_indexes
    ):
        db.execute("ALTER TABLE users RENAME TO users_legacy")
        db.execute(
            """CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hotel_id TEXT NOT NULL,
                role TEXT NOT NULL,
                username TEXT NOT NULL UNIQUE,
                password TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(hotel_id, role)
            )"""
        )
        legacy_columns = {column[1] for column in db.execute("PRAGMA table_info(users_legacy)")}
        legacy_hotel_expr = "hotel_id" if "hotel_id" in legacy_columns else "?"
        copy_values = (
            "SELECT id, hotel_id, role, username, password, created_at FROM users_legacy"
            if legacy_hotel_expr == "hotel_id"
            else "SELECT id, ?, role, username, password, created_at FROM users_legacy"
        )
        db.execute(
            "INSERT INTO users (id, hotel_id, role, username, password, created_at) "
            + copy_values,
            () if legacy_hotel_expr == "hotel_id" else (DEFAULT_HOTEL_ID,),
        )
        db.execute("DROP TABLE users_legacy")
    room_info = list(db.execute("PRAGMA table_info(rooms)"))
    if not any(column["name"] == "hotel_id" and column["pk"] for column in room_info):
        db.execute("ALTER TABLE rooms RENAME TO rooms_legacy")
        db.execute(
            """CREATE TABLE rooms (
                number TEXT NOT NULL, hotel_id TEXT NOT NULL, name TEXT NOT NULL,
                beds INTEGER NOT NULL, rate INTEGER NOT NULL, status TEXT NOT NULL,
                PRIMARY KEY (hotel_id, number)
            )"""
        )
        db.execute(
            """INSERT INTO rooms (number, hotel_id, name, beds, rate, status)
            SELECT number, hotel_id, name, beds, rate, status FROM rooms_legacy"""
        )
        db.execute("DROP TABLE rooms_legacy")
    listing_info = list(db.execute("PRAGMA table_info(online_room_listings)"))
    if not any(
        column["name"] == "hotel_id" and column["pk"] for column in listing_info
    ):
        db.execute("ALTER TABLE online_room_listings RENAME TO online_room_listings_legacy")
        db.execute(
            """CREATE TABLE online_room_listings (
                hotel_id TEXT NOT NULL, room_number TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '', photo_path TEXT NOT NULL DEFAULT '',
                enabled INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
                PRIMARY KEY (hotel_id, room_number)
            )"""
        )
        db.execute(
            """INSERT INTO online_room_listings
            (hotel_id, room_number, description, photo_path, enabled, updated_at)
            SELECT hotel_id, room_number, description, photo_path, enabled, updated_at
            FROM online_room_listings_legacy"""
        )
        db.execute("DROP TABLE online_room_listings_legacy")
    if "photo_paths" not in {
        column[1] for column in db.execute("PRAGMA table_info(online_room_listings)")
    }:
        db.execute(
            "ALTER TABLE online_room_listings ADD COLUMN photo_paths TEXT NOT NULL DEFAULT '[]'"
        )
    settings_info = list(db.execute("PRAGMA table_info(online_booking_settings)"))
    if "hotel_id" not in {column[1] for column in settings_info}:
        db.execute("ALTER TABLE online_booking_settings RENAME TO online_booking_settings_legacy")
        db.execute(
            """CREATE TABLE online_booking_settings (
                hotel_id TEXT PRIMARY KEY, bank_name TEXT NOT NULL DEFAULT '',
                account_name TEXT NOT NULL DEFAULT '', account_number TEXT NOT NULL DEFAULT '',
                reception_whatsapp TEXT NOT NULL DEFAULT '',
                reception_email TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL
            )"""
        )
        db.execute(
            """INSERT INTO online_booking_settings
            (hotel_id, bank_name, account_name, account_number, reception_whatsapp, updated_at)
            SELECT ?, bank_name, account_name, account_number, reception_whatsapp, updated_at
            FROM online_booking_settings_legacy WHERE id = 1""",
            (DEFAULT_HOTEL_ID,),
        )
        db.execute("DROP TABLE online_booking_settings_legacy")
    if "reception_email" not in {column[1] for column in db.execute(
        "PRAGMA table_info(online_booking_settings)"
    )}:
        db.execute(
            "ALTER TABLE online_booking_settings ADD COLUMN reception_email TEXT NOT NULL DEFAULT ''"
        )
    db.execute(
        """INSERT OR IGNORE INTO online_booking_settings (hotel_id, updated_at)
        VALUES (?, CURRENT_TIMESTAMP)""",
        (DEFAULT_HOTEL_ID,),
    )
    reservation_columns = {column[1] for column in db.execute("PRAGMA table_info(reservations)")}
    if "amount_paid" not in reservation_columns:
        db.execute("ALTER TABLE reservations ADD COLUMN amount_paid INTEGER NOT NULL DEFAULT 0")
    if "booking_source" not in reservation_columns:
        db.execute(
            "ALTER TABLE reservations ADD COLUMN booking_source TEXT NOT NULL DEFAULT 'reception'"
        )
    if "hold_expires_at" not in reservation_columns:
        db.execute("ALTER TABLE reservations ADD COLUMN hold_expires_at TEXT")
    db.execute(
        """CREATE INDEX IF NOT EXISTS reservations_room_stay_idx
        ON reservations (room_number, status, check_in, check_out)"""
    )
    db.execute("UPDATE reservations SET amount_paid = amount WHERE payment_status = 'paid' AND amount_paid = 0")
    if not db.execute("SELECT 1 FROM app_migrations WHERE name = 'remove_seeded_demo_data'").fetchone():
        demo_reservations = db.execute(
            """SELECT id FROM reservations
            WHERE hotel_id = ? AND guest_name = 'Amara Okafor' AND email = 'amara@example.com'
              AND phone = '+234 803 555 0121' AND room_number = '301'
              AND check_in = '2026-10-02' AND check_out = '2026-10-05'
              AND amount = 555 AND payment_method = 'Card'""",
            (DEFAULT_HOTEL_ID,),
        ).fetchall()
        if demo_reservations:
            reservation_ids = [reservation["id"] for reservation in demo_reservations]
            placeholders = ",".join("?" for _ in reservation_ids)
            db.execute(
                f"DELETE FROM payments WHERE reservation_id IN ({placeholders})",
                reservation_ids,
            )
            db.execute(
                f"DELETE FROM reservations WHERE id IN ({placeholders})",
                reservation_ids,
            )
        for number, name, beds, rate in [
            ("101", "Standard", 1, 45000),
            ("102", "Standard", 1, 45000),
            ("103", "Deluxe", 2, 60000),
            ("104", "Deluxe", 2, 60000),
            ("105", "Suite", 3, 85000),
            ("106", "Standard", 1, 45000),
            ("201", "Standard", 1, 45000),
            ("202", "Deluxe", 2, 60000),
            ("203", "Suite", 3, 85000),
            ("204", "Standard", 1, 45000),
            ("205", "Standard", 1, 45000),
            ("206", "Deluxe", 2, 60000),
        ]:
            db.execute(
                """DELETE FROM rooms WHERE number = ? AND name = ? AND beds = ? AND rate = ?
                AND hotel_id = ?
                AND NOT EXISTS (SELECT 1 FROM reservations WHERE hotel_id = ? AND room_number = ?)
                AND NOT EXISTS (SELECT 1 FROM payments WHERE hotel_id = ? AND room_number = ?)""",
                (number, name, beds, rate, DEFAULT_HOTEL_ID,
                 DEFAULT_HOTEL_ID, number, DEFAULT_HOTEL_ID, number),
            )
        db.execute("INSERT INTO app_migrations (name) VALUES ('remove_seeded_demo_data')")
    db.commit()


def reference_rooms(hotel_id=None, as_of_date=None):
    hotel_id = hotel_id or current_hotel_id()
    as_of_date = as_of_date or date.today()
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rows = client.table("rooms").select("*").eq(
            "hotel_id", hotel_id
        ).order("number").execute().data
        bookings = client.table("reservations").select(
            "room_number, guest_name, status, check_in, check_out"
        ).eq("hotel_id", hotel_id).in_(
            "status", ["booked", "checked_in"]
        ).execute().data
        room_rows = rows
        booking_rows = bookings
    else:
        booking_rows = get_db().execute(
            """SELECT room_number, guest_name, status, check_in, check_out
            FROM reservations
            WHERE hotel_id = ? AND status IN ('booked', 'checked_in')
            ORDER BY created_at""",
            (hotel_id,),
        ).fetchall()
        room_rows = get_db().execute(
            "SELECT number, name, beds, rate, status FROM rooms WHERE hotel_id = ? ORDER BY number",
            (hotel_id,),
        ).fetchall()

    bookings_by_room = {}
    for booking in booking_rows:
        check_in = date.fromisoformat(str(booking["check_in"])[:10])
        check_out = date.fromisoformat(str(booking["check_out"])[:10])
        if check_in <= as_of_date < check_out:
            bookings_by_room.setdefault(booking["room_number"], []).append(
                (dict(booking), check_in)
            )

    rooms = []
    for row in room_rows:
        matching_bookings = bookings_by_room.get(row["number"], [])
        manual_status = str(row["status"]).lower()
        if manual_status in {"cleaning", "unavailable"} or not matching_bookings:
            status = manual_status
        elif manual_status == "occupied" or any(
            booking["status"] == "checked_in"
            and check_in <= date.today() < date.fromisoformat(
                str(booking["check_out"])[:10]
            )
            for booking, check_in in matching_bookings
        ):
            status = "occupied"
        else:
            status = "booked"
        rooms.append({
            "number": row["number"],
            "type": row["name"],
            "beds": row["beds"],
            "rate": row["rate"],
            "status": status.capitalize(),
            "guest": " / ".join(dict.fromkeys(
                booking["guest_name"]
                for booking, _ in matching_bookings
                if booking.get("guest_name")
            )),
            "active_booking": bool(matching_bookings),
        })
    return rooms


def reference_room_metrics():
    rooms = reference_rooms()
    values = {}
    for room in rooms:
        status = room["status"].lower()
        values[status] = values.get(status, 0) + 1
    return [
        ("Total Rooms", len(rooms)),
        ("Available", values.get("available", 0)),
        ("Booked", values.get("booked", 0)),
        ("Occupied", values.get("occupied", 0)),
        ("Cleaning", values.get("cleaning", 0)),
    ]


def reference_reservations():
    if SUPABASE_ENABLED:
        return get_request_supabase().table("reservations").select("*").eq(
            "hotel_id", current_hotel_id()
        ).order("check_in").execute().data
    rows = get_db().execute(
        "SELECT * FROM reservations WHERE hotel_id = ? ORDER BY check_in, id DESC",
        (current_hotel_id(),),
    ).fetchall()
    return [dict(row) for row in rows]


def reference_payments():
    if SUPABASE_ENABLED:
        rows = get_request_supabase().table("payments").select("*").eq(
            "hotel_id", current_hotel_id()
        ).order("created_at", desc=True).execute().data
        return [
            (row["room_number"], row["method"], row["amount"], row["balance"], row["received_by"], row["created_at"][:10])
            for row in rows
        ]
    rows = get_db().execute(
        """SELECT room_number, method, amount, balance, received_by, created_at
        FROM payments WHERE hotel_id = ? ORDER BY id DESC""",
        (current_hotel_id(),),
    ).fetchall()
    if rows:
        return [
            (row["room_number"], row["method"], row["amount"], row["balance"], row["received_by"], row["created_at"][:10])
            for row in rows
        ]
    return [
        (row["room_number"], row["method"], row["amount"], row["balance"], row["received_by"], row["created_at"][:10])
        for row in rows
    ]


def reference_bookings(reservations, rooms):
    room_types = {room["number"]: room["type"] for room in rooms}
    status_labels = {
        "booked": "Active",
        "checked_in": "Occupied",
        "checked_out": "Checked out",
        "cancelled": "Cancelled",
        "pending_payment": "Awaiting transfer",
    }
    return [
        {
            **row,
            "room_type": room_types.get(row["room_number"], "Unknown"),
            "status_label": status_labels.get(
                row["status"], row["status"].replace("_", " ").capitalize()
            ),
            "balance": row["amount"] - row.get("amount_paid", 0),
        }
        for row in reservations
    ]


def reference_finance(reservations, payments):
    active = [
        row for row in reservations
        if row["status"] not in {"checked_out", "cancelled", "pending_payment"}
    ]
    total = sum(row["amount"] for row in active)
    paid = sum(row.get("amount_paid", 0) for row in reservations)
    active_paid = sum(row.get("amount_paid", 0) for row in active)
    return {
        "booking_value": total,
        "collected": paid,
        "outstanding": total - active_paid,
        "stay_records": len(reservations),
    }


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def timestamp_is_future(value):
    if not value:
        return False
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.astimezone()
    return parsed > datetime.now().astimezone()


def expire_online_booking_holds():
    now = now_iso()
    if SUPABASE_ENABLED:
        get_supabase_admin().table("reservations").update({
            "status": "cancelled",
            "hold_expires_at": None,
        }).eq("status", "pending_payment").lte("hold_expires_at", now).execute()
        return
    get_db().execute(
        """UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL
        WHERE status = 'pending_payment' AND hold_expires_at <= ?""",
        (now,),
    )
    get_db().commit()


def online_booking_settings(public=False, hotel_id=None):
    hotel_id = hotel_id or current_hotel_id()
    if SUPABASE_ENABLED:
        client = get_supabase_admin() if public else get_request_supabase()
        rows = client.table("online_booking_settings").select("*").eq(
            "hotel_id", hotel_id
        ).limit(1).execute().data
        return rows[0] if rows else {}
    row = get_db().execute(
        "SELECT * FROM online_booking_settings WHERE hotel_id = ?", (hotel_id,)
    ).fetchone()
    return dict(row) if row else {}


def online_room_listings(manager=False, hotel_id=None):
    hotel_id = hotel_id or current_hotel_id()
    if SUPABASE_ENABLED:
        client = get_request_supabase() if manager else get_supabase_admin()
        room_rows = client.table("rooms").select("*").eq(
            "hotel_id", hotel_id
        ).order("number").execute().data
        query = client.table("online_room_listings").select("*").eq(
            "hotel_id", hotel_id
        )
        if not manager:
            query = query.eq("enabled", True)
        listings = query.execute().data
        rooms = [
            {
                "number": row["number"],
                "type": row["name"],
                "beds": row["beds"],
                "rate": row["rate"],
                "status": row["status"].capitalize(),
                "guest": "",
                "active_booking": False,
            }
            for row in room_rows
        ]
    else:
        rooms = reference_rooms(hotel_id=hotel_id)
        query = "SELECT * FROM online_room_listings WHERE hotel_id = ?"
        params = [hotel_id]
        if not manager:
            query += " AND enabled = 1"
        listings = [
            dict(row) for row in get_db().execute(query, params).fetchall()
        ]
    listing_by_room = {item["room_number"]: item for item in listings}
    result = []
    for room in rooms:
        listing = listing_by_room.get(room["number"])
        photo_paths = room_photo_paths(listing)
        if manager:
            result.append({
                **room,
                "description": listing["description"] if listing else "",
                "photo_paths": photo_paths,
                "photo_urls": [online_photo_url(path) for path in photo_paths],
                "photo_url": online_photo_url(photo_paths[0]) if photo_paths else "",
                "enabled": bool(listing and listing["enabled"] and photo_paths),
            })
        elif listing:
            result.append({
                **room,
                **listing,
                "photo_paths": photo_paths,
                "photo_urls": [online_photo_url(path) for path in photo_paths],
            })
    return result


def room_photo_paths(listing):
    if not listing:
        return []
    photo_paths = listing.get("photo_paths") or []
    if isinstance(photo_paths, str):
        try:
            photo_paths = json.loads(photo_paths)
        except json.JSONDecodeError:
            photo_paths = []
    if not isinstance(photo_paths, list):
        photo_paths = []
    paths = []
    for path in [listing.get("photo_path", ""), *photo_paths]:
        if path and path not in paths:
            paths.append(path)
    return paths[:MAX_ROOM_PHOTOS]


def online_photo_url(photo_path):
    if not photo_path:
        return ""
    if SUPABASE_ENABLED:
        return get_supabase_admin().storage.from_(ROOM_PHOTO_BUCKET).get_public_url(
            photo_path
        )
    return url_for("online_room_photo", photo_path=photo_path)


def available_online_rooms(check_in, check_out, hotel_id=None):
    hotel_id = hotel_id or current_hotel_id()
    expire_online_booking_holds()
    listings = online_room_listings(hotel_id=hotel_id)
    available = []
    for room in listings:
        if room["status"].lower() != "available":
            continue
        if not room.get("photo_urls"):
            continue
        if SUPABASE_ENABLED:
            stays = get_supabase_admin().table("reservations").select(
                "id, check_in, check_out, status, hold_expires_at"
            ).eq("hotel_id", hotel_id).eq("room_number", room["number"]).in_(
                "status", ["booked", "checked_in", "pending_payment"]
            ).execute().data
        else:
            stays = [
                dict(row) for row in get_db().execute(
                    """SELECT id, check_in, check_out, status, hold_expires_at
                    FROM reservations WHERE hotel_id = ? AND room_number = ?
                    AND status IN ('booked', 'checked_in', 'pending_payment')""",
                    (hotel_id, room["number"]),
                ).fetchall()
            ]
        collision = False
        for stay in stays:
            if stay["status"] == "pending_payment" and (
                not timestamp_is_future(stay.get("hold_expires_at"))
            ):
                continue
            if check_in < date.fromisoformat(stay["check_out"]) and (
                check_out > date.fromisoformat(stay["check_in"])
            ):
                collision = True
                break
        if not collision:
            available.append(room)
    return available


def price_range_bounds(price_range):
    for key, _label, minimum, maximum_exclusive in PUBLIC_PRICE_RANGES:
        if price_range == key:
            return minimum, maximum_exclusive
    return None


def filter_rooms_by_price_range(rooms, price_range):
    bounds = price_range_bounds(price_range)
    if bounds is None:
        return rooms
    minimum, maximum_exclusive = bounds
    return [
        room for room in rooms
        if room["rate"] >= minimum
        and (maximum_exclusive is None or room["rate"] < maximum_exclusive)
    ]


def save_online_booking_settings(form, hotel_id=None):
    hotel_id = hotel_id or current_hotel_id()
    bank_name = form.get("bank_name", "").strip()
    account_name = form.get("account_name", "").strip()
    account_number = re.sub(r"\s", "", form.get("account_number", ""))
    whatsapp = form.get("reception_whatsapp", "").strip()
    reception_email = form.get("reception_email", "").strip().lower()
    whatsapp_digits = re.sub(r"\D", "", whatsapp)
    if not bank_name or not account_name:
        raise ValueError("Enter the bank and account holder name.")
    if not re.fullmatch(r"\d{6,20}", account_number):
        raise ValueError("Enter a valid bank account number.")
    if not 8 <= len(whatsapp_digits) <= 15 or whatsapp_digits.startswith("0"):
        raise ValueError("Enter the Reception WhatsApp number with its country code.")
    if len(reception_email) > 254 or not re.fullmatch(
        r"[^\s@]+@[^\s@]+\.[^\s@]+", reception_email
    ):
        raise ValueError("Enter a valid Reception notification email address.")
    settings = {
        "bank_name": bank_name[:100],
        "account_name": account_name[:120],
        "account_number": account_number,
        "reception_whatsapp": "+" + whatsapp_digits,
        "reception_email": reception_email,
        "updated_at": now_iso(),
    }
    if SUPABASE_ENABLED:
        get_request_supabase().table("online_booking_settings").upsert({
            "hotel_id": hotel_id,
            **settings,
        }).execute()
    else:
        get_db().execute(
            """INSERT INTO online_booking_settings
            (hotel_id, bank_name, account_name, account_number, reception_whatsapp, reception_email, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(hotel_id) DO UPDATE SET
            bank_name = excluded.bank_name, account_name = excluded.account_name,
            account_number = excluded.account_number,
            reception_whatsapp = excluded.reception_whatsapp,
            reception_email = excluded.reception_email,
            updated_at = excluded.updated_at""",
            (
                hotel_id, settings["bank_name"], settings["account_name"],
                settings["account_number"], settings["reception_whatsapp"],
                settings["reception_email"], settings["updated_at"],
            ),
        )
        get_db().commit()


def send_reception_booking_email(recipient, hotel_name, reference, guest_name,
                                 guest_email, guest_phone, room_number,
                                 check_in, check_out, amount):
    host = os.getenv("SMTP_HOST", "").strip()
    sender = os.getenv("SMTP_FROM_EMAIL", "").strip()
    if not host or not sender:
        raise ValueError("SMTP_HOST and SMTP_FROM_EMAIL must be configured.")
    try:
        port = int(os.getenv("SMTP_PORT", "587"))
    except ValueError as error:
        raise ValueError("SMTP_PORT must be a valid port number.") from error
    if not 1 <= port <= 65535:
        raise ValueError("SMTP_PORT must be between 1 and 65535.")

    username = os.getenv("SMTP_USERNAME", "")
    password = os.getenv("SMTP_PASSWORD", "")
    if bool(username) != bool(password):
        raise ValueError("Configure both SMTP_USERNAME and SMTP_PASSWORD.")

    reception_url = url_for(
        "reference_workspace", role="reception", page="online", _external=True
    )
    message = EmailMessage()
    message["Subject"] = f"Online booking request {reference} - {hotel_name}"
    message["From"] = sender
    message["To"] = recipient
    message.set_content(
        f"""A guest submitted an online room booking request for {hotel_name}.

Booking reference: {reference}
Guest: {guest_name}
Guest email: {guest_email}
Guest phone: {guest_phone}
Room: {room_number}
Stay: {check_in} to {check_out}
Amount due: NGN {amount:,.0f}

The room is held for {ONLINE_HOLD_MINUTES} minutes pending transfer verification.
Sign in as Reception and open Online Requests to review the request. Verify
payment before confirming the reservation:
{reception_url}
"""
    )

    timeout = 15
    context = ssl.create_default_context()
    if port == 465:
        with smtplib.SMTP_SSL(host, port, timeout=timeout, context=context) as smtp:
            if username:
                smtp.login(username, password)
            smtp.send_message(message)
    else:
        with smtplib.SMTP(host, port, timeout=timeout) as smtp:
            smtp.ehlo()
            smtp.starttls(context=context)
            smtp.ehlo()
            if username:
                smtp.login(username, password)
            smtp.send_message(message)


def save_online_room_listing(room_number, form):
    hotel_id = current_hotel_id()
    if SUPABASE_ENABLED:
        room = get_request_supabase().table("rooms").select("number").eq(
            "hotel_id", hotel_id
        ).eq("number", room_number
        ).limit(1).execute().data
    else:
        room = get_db().execute(
            "SELECT number FROM rooms WHERE hotel_id = ? AND number = ?",
            (hotel_id, room_number),
        ).fetchone()
    if not room:
        raise ValueError("Room not found.")
    description = form.get("description", "").strip()
    if len(description) > 1200:
        raise ValueError("Room description must be 1,200 characters or fewer.")
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        old = client.table("online_room_listings").select(
            "photo_path, photo_paths"
        ).eq(
            "hotel_id", hotel_id
        ).eq("room_number", room_number
        ).limit(1).execute().data
        photo_paths = room_photo_paths(old[0] if old else None)
        client.table("online_room_listings").upsert({
            "hotel_id": hotel_id,
            "room_number": room_number,
            "description": description,
            "photo_path": photo_paths[0] if photo_paths else "",
            "photo_paths": photo_paths,
            "enabled": bool(photo_paths),
            "updated_at": now_iso(),
        }).execute()
    else:
        db = get_db()
        old = db.execute(
            "SELECT photo_path, photo_paths FROM online_room_listings WHERE hotel_id = ? AND room_number = ?",
            (hotel_id, room_number),
        ).fetchone()
        photo_paths = room_photo_paths(dict(old) if old else None)
        db.execute(
            """INSERT INTO online_room_listings
            (hotel_id, room_number, description, photo_path, photo_paths, enabled, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(hotel_id, room_number) DO UPDATE SET description = excluded.description,
            photo_path = excluded.photo_path, photo_paths = excluded.photo_paths,
            enabled = excluded.enabled, updated_at = excluded.updated_at""",
            (
                hotel_id, room_number, description,
                photo_paths[0] if photo_paths else "",
                json.dumps(photo_paths), int(bool(photo_paths)), now_iso(),
            ),
        )
        db.commit()


def save_room_photos(room_number, uploaded_files):
    uploads = [uploaded for uploaded in uploaded_files if uploaded and uploaded.filename]
    if not uploads:
        raise ValueError("Choose one to three room photos to upload.")
    if len(uploads) > MAX_ROOM_PHOTOS:
        raise ValueError(f"Upload no more than {MAX_ROOM_PHOTOS} room photos.")
    expected_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }
    validated_uploads = []
    for uploaded_file in uploads:
        extension = Path(secure_filename(uploaded_file.filename)).suffix.lower()
        if extension not in ALLOWED_ROOM_PHOTO_EXTENSIONS:
            raise ValueError("Use JPG, PNG, or WebP room photos.")
        content = uploaded_file.stream.read(MAX_ROOM_PHOTO_BYTES + 1)
        if not content or len(content) > MAX_ROOM_PHOTO_BYTES:
            raise ValueError("Each room photo must be between 1 byte and 5 MB.")
        if uploaded_file.mimetype != expected_types[extension]:
            raise ValueError("A selected photo's file type does not match its extension.")
        valid_signature = (
            extension in {".jpg", ".jpeg"} and content.startswith(b"\xff\xd8\xff")
            or extension == ".png" and content.startswith(b"\x89PNG\r\n\x1a\n")
            or extension == ".webp" and content.startswith(b"RIFF")
            and content[8:12] == b"WEBP"
        )
        if not valid_signature:
            raise ValueError("A selected file is not a valid JPG, PNG, or WebP image.")
        validated_uploads.append((extension, content, expected_types[extension]))

    hotel_id = current_hotel_id()
    if SUPABASE_ENABLED:
        admin = get_supabase_admin()
        room = admin.table("rooms").select("number").eq(
            "hotel_id", hotel_id
        ).eq("number", room_number
        ).limit(1).execute().data
        if not room:
            raise ValueError("Room not found.")
        existing = admin.table("online_room_listings").select(
            "photo_path, photo_paths, description"
        ).eq("hotel_id", hotel_id).eq(
            "room_number", room_number
        ).limit(1).execute().data
        photo_paths = []
        try:
            for extension, content, content_type in validated_uploads:
                photo_path = f"{hotel_id}/{uuid4().hex}{extension}"
                admin.storage.from_(ROOM_PHOTO_BUCKET).upload(
                    photo_path,
                    content,
                    {"content-type": content_type, "upsert": "true"},
                )
                photo_paths.append(photo_path)
        except Exception:
            app.logger.exception(
                "Could not upload room photos for hotel %s room %s",
                hotel_id, room_number,
            )
            if photo_paths:
                admin.storage.from_(ROOM_PHOTO_BUCKET).remove(photo_paths)
            raise
        admin.table("online_room_listings").upsert({
            "hotel_id": hotel_id,
            "room_number": room_number,
            "photo_path": photo_paths[0],
            "photo_paths": photo_paths,
            "description": existing[0]["description"] if existing else "",
            "enabled": True,
            "updated_at": now_iso(),
        }).execute()
        old_photo_paths = room_photo_paths(existing[0] if existing else None)
        if old_photo_paths:
            admin.storage.from_(ROOM_PHOTO_BUCKET).remove(
                old_photo_paths
            )
        return

    db = get_db()
    room = db.execute(
        "SELECT number FROM rooms WHERE hotel_id = ? AND number = ?",
        (hotel_id, room_number),
    ).fetchone()
    if not room:
        raise ValueError("Room not found.")
    ROOM_PHOTO_DIRECTORY.mkdir(parents=True, exist_ok=True)
    existing = db.execute(
        """SELECT description, photo_path, photo_paths FROM online_room_listings
        WHERE hotel_id = ? AND room_number = ?""",
        (hotel_id, room_number),
    ).fetchone()
    photo_paths = []
    try:
        for extension, content, _ in validated_uploads:
            photo_path = f"{hotel_id}/{uuid4().hex}{extension}"
            destination = ROOM_PHOTO_DIRECTORY / photo_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
            photo_paths.append(photo_path)
    except OSError:
        app.logger.exception(
            "Could not save room photos for hotel %s room %s",
            hotel_id, room_number,
        )
        for photo_path in photo_paths:
            destination = ROOM_PHOTO_DIRECTORY / photo_path
            if destination.is_file():
                destination.unlink()
        raise
    db.execute(
        """INSERT INTO online_room_listings
        (hotel_id, room_number, description, photo_path, photo_paths, enabled, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(hotel_id, room_number) DO UPDATE SET
        photo_path = excluded.photo_path, photo_paths = excluded.photo_paths,
        enabled = excluded.enabled, updated_at = excluded.updated_at""",
        (
            hotel_id, room_number,
            existing["description"] if existing else "",
            photo_paths[0],
            json.dumps(photo_paths),
            1,
            now_iso(),
        ),
    )
    db.commit()
    for previous_path in room_photo_paths(dict(existing) if existing else None):
        previous = ROOM_PHOTO_DIRECTORY / previous_path
        if previous.is_file():
            previous.unlink()


def create_online_booking(form):
    try:
        check_in = date.fromisoformat(form.get("check_in", ""))
        check_out = date.fromisoformat(form.get("check_out", ""))
    except ValueError as error:
        raise ValueError("Choose valid arrival and departure dates.") from error
    today = date.today()
    if check_in < today:
        raise ValueError("Arrival date cannot be in the past.")
    if check_out <= check_in:
        raise ValueError("Departure must be after arrival.")
    guest_name = form.get("guest_name", "").strip()
    phone = form.get("phone", "").strip()
    email = form.get("email", "").strip()
    room_number = form.get("room_number", "").strip()
    hotel_id = form.get("hotel_id", "").strip()
    price_range = form.get("price_range", "").strip()
    if price_range and price_range_bounds(price_range) is None:
        raise ValueError("Choose a valid room price range.")
    if not guest_name or len(guest_name) > 160 or not phone or len(phone) > 40:
        raise ValueError("Enter a guest name and valid phone number.")
    if len(email) > 254 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise ValueError("Enter a valid email address.")
    if form.get("website", "").strip():
        raise ValueError("Booking could not be submitted.")

    hotel = None
    if SUPABASE_ENABLED:
        hotel_rows = get_supabase_admin().table("hotels").select(
            "id, name, slug"
        ).eq("id", hotel_id).eq("is_active", True).limit(1).execute().data
        hotel = hotel_rows[0] if hotel_rows else None
    else:
        row = get_db().execute(
            "SELECT id, name, slug FROM hotels WHERE id = ? AND is_active = 1",
            (hotel_id,),
        ).fetchone()
        hotel = dict(row) if row else None
    if not hotel:
        raise ValueError("Choose a hotel that is currently accepting bookings.")
    settings = online_booking_settings(public=True, hotel_id=hotel_id)
    if not all(settings.get(key) for key in (
        "bank_name", "account_name", "account_number", "reception_whatsapp",
        "reception_email",
    )):
        raise ValueError(
            "Online booking setup is incomplete. Please contact the hotel."
        )
    available = filter_rooms_by_price_range(
        available_online_rooms(check_in, check_out, hotel_id=hotel_id),
        price_range,
    )
    room = next((item for item in available if item["number"] == room_number), None)
    if not room:
        raise ValueError("That room is no longer available for the selected dates.")

    hold_expires_at = (
        datetime.now().astimezone() + timedelta(minutes=ONLINE_HOLD_MINUTES)
    ).isoformat(timespec="seconds")
    if SUPABASE_ENABLED:
        from postgrest.exceptions import APIError

        try:
            result = get_supabase_admin().rpc("create_online_booking", {
                "p_hotel_id": hotel_id,
                "p_guest_name": guest_name,
                "p_email": email,
                "p_phone": phone,
                "p_room_number": room_number,
                "p_check_in": check_in.isoformat(),
                "p_check_out": check_out.isoformat(),
            }).execute().data
        except APIError as error:
            if error.code == "P0001" and error.message and (
                "already has a booking" in error.message
                or "no longer listed or available" in error.message
            ):
                raise ValueError(
                    "That room is no longer available for those dates. "
                    "Reception may have changed its status or another guest may have booked it."
                ) from error
            raise
        reservation_id = result[0] if isinstance(result, list) else result
    else:
        db = get_db()
        db.execute("BEGIN IMMEDIATE")
        room_status = db.execute(
            "SELECT status FROM rooms WHERE hotel_id = ? AND number = ?",
            (hotel_id, room_number),
        ).fetchone()
        if not room_status or room_status["status"] != "available":
            db.rollback()
            raise ValueError(
                "Reception has changed this room's availability. Choose another room."
            )
        overlap = db.execute(
            """SELECT 1 FROM reservations WHERE hotel_id = ? AND room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')
            AND check_in < ? AND check_out > ?
            AND (status != 'pending_payment' OR hold_expires_at > ?)
            LIMIT 1""",
            (hotel_id, room_number, check_out.isoformat(), check_in.isoformat(), now_iso()),
        ).fetchone()
        if overlap:
            db.rollback()
            raise ValueError("That room was just booked for the selected dates.")
        cursor = db.execute(
            """INSERT INTO reservations
            (hotel_id, guest_name, email, phone, room_number, check_in, check_out, amount,
             amount_paid, payment_method, payment_status, status, created_at,
             booking_source, hold_expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'Transfer', 'pending',
                    'pending_payment', ?, 'online', ?)""",
            (
                hotel_id, guest_name, email, phone, room_number, check_in.isoformat(),
                check_out.isoformat(), (check_out - check_in).days * room["rate"],
                now_iso(), hold_expires_at,
            ),
        )
        reservation_id = cursor.lastrowid
        db.commit()
    amount = (check_out - check_in).days * room["rate"]
    try:
        send_reception_booking_email(
            settings["reception_email"],
            hotel["name"],
            str(reservation_id),
            guest_name,
            email,
            phone,
            room_number,
            check_in.isoformat(),
            check_out.isoformat(),
            amount,
        )
        email_notification_sent = True
    except (OSError, smtplib.SMTPException, ValueError):
        app.logger.exception(
            "Could not email Reception about online booking %s for hotel %s",
            reservation_id, hotel_id,
        )
        email_notification_sent = False
    message = (
        f"Hello, I submitted online booking request {reservation_id} for "
        f"{hotel['name']}, "
        f"{guest_name}, room {room_number}, {check_in.isoformat()} to "
        f"{check_out.isoformat()}. I am sending the bank transfer for "
        f"NGN {amount:,.0f}. "
        "Please confirm once received."
    )
    wa_number = re.sub(r"\D", "", settings["reception_whatsapp"])
    session["online_booking_confirmation"] = {
        "reference": str(reservation_id),
        "hotel_id": hotel_id,
        "hotel_name": hotel["name"],
        "hotel_slug": hotel["slug"],
        "room_number": room_number,
        "room_type": room["type"],
        "check_in": check_in.isoformat(),
        "check_out": check_out.isoformat(),
        "amount": amount,
        "bank_name": settings["bank_name"],
        "account_name": settings["account_name"],
        "account_number": settings["account_number"],
        "hold_expires_at": hold_expires_at,
        "email_notification_sent": email_notification_sent,
        "whatsapp_url": f"https://wa.me/{wa_number}?{urlencode({'text': message})}",
    }
    return reservation_id


def confirm_online_booking(reservation_id, received_by):
    if SUPABASE_ENABLED:
        from postgrest.exceptions import APIError

        try:
            confirmed = get_request_supabase().rpc("confirm_online_booking", {
                "p_reservation_id": reservation_id,
                "p_received_by": received_by[:120],
            }).execute().data
        except APIError as error:
            raise_supabase_reservation_conflict(error)
        if not confirmed:
            raise ValueError("This online request expired or is no longer awaiting confirmation.")
        return
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    reservation = db.execute(
        "SELECT * FROM reservations WHERE id = ? AND hotel_id = ? AND status = 'pending_payment'",
        (reservation_id, current_hotel_id()),
    ).fetchone()
    if not reservation:
        db.rollback()
        raise ValueError("This online request is no longer awaiting confirmation.")
    if not reservation["hold_expires_at"] or reservation["hold_expires_at"] <= now_iso():
        db.execute(
            "UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL WHERE id = ? AND hotel_id = ?",
            (reservation_id, current_hotel_id()),
        )
        db.commit()
        raise ValueError("The 30-minute room hold expired. Ask the guest to submit a new request.")
    conflict = db.execute(
        """SELECT 1 FROM reservations
        WHERE hotel_id = ? AND room_number = ? AND id != ?
          AND status IN ('booked', 'checked_in', 'pending_payment')
          AND (status != 'pending_payment' OR hold_expires_at > ?)
          AND check_in < ? AND check_out > ? LIMIT 1""",
        (
            reservation["hotel_id"], reservation["room_number"], reservation_id,
            now_iso(), reservation["check_out"], reservation["check_in"],
        ),
    ).fetchone()
    if conflict:
        db.execute(
            """UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL
            WHERE id = ? AND hotel_id = ?""",
            (reservation_id, reservation["hotel_id"]),
        )
        db.commit()
        raise ValueError("That room already has a booking during the selected dates.")
    db.execute(
        """UPDATE reservations SET status = 'booked', amount_paid = amount,
        payment_status = 'paid', hold_expires_at = NULL WHERE id = ? AND hotel_id = ?""",
        (reservation_id, current_hotel_id()),
    )
    if reservation["amount"] > 0:
        db.execute(
            """INSERT INTO payments
            (hotel_id, reservation_id, room_number, amount, balance, method, received_by, created_at)
            VALUES (?, ?, ?, ?, 0, 'Transfer', ?, ?)""",
            (
                reservation["hotel_id"], reservation_id, reservation["room_number"], reservation["amount"],
                received_by[:120], now_iso(),
            ),
        )
    db.commit()


def pending_online_bookings():
    now = now_iso()
    if SUPABASE_ENABLED:
        return get_request_supabase().table("reservations").select("*").eq(
            "hotel_id", current_hotel_id()
        ).eq("booking_source", "online"
        ).eq("status", "pending_payment").gt(
            "hold_expires_at", now
        ).order("created_at").execute().data
    return [
        dict(row) for row in get_db().execute(
            """SELECT * FROM reservations WHERE booking_source = 'online'
            AND hotel_id = ? AND status = 'pending_payment' AND hold_expires_at > ?
            ORDER BY created_at""",
            (current_hotel_id(), now),
        ).fetchall()
    ]


def reference_calendar(rooms, reservations, reference_date=None):
    reference_date = reference_date or date.today()
    start = reference_date - timedelta(days=reference_date.weekday())
    days = [start + timedelta(days=offset) for offset in range(7)]
    active_reservations = []
    for reservation in reservations:
        status = str(reservation.get("status", "")).lower()
        if status not in {"booked", "checked_in", "pending_payment"}:
            continue
        if status == "pending_payment" and not timestamp_is_future(
            reservation.get("hold_expires_at")
        ):
            continue
        try:
            check_in = date.fromisoformat(str(reservation["check_in"])[:10])
            check_out = date.fromisoformat(str(reservation["check_out"])[:10])
        except (KeyError, TypeError, ValueError):
            app.logger.warning(
                "Skipping reservation %s with invalid calendar dates",
                reservation.get("id", "unknown"),
            )
            continue
        active_reservations.append({
            **reservation,
            "status": (
                "booked" if status == "checked_in" and check_in > date.today()
                else status
            ),
            "_room_number": str(reservation.get("room_number", "")).strip(),
            "_check_in": check_in,
            "_check_out": check_out,
        })

    rows = []
    for room in rooms:
        cells = []
        for current_day in days:
            matching_reservations = [
                reservation for reservation in active_reservations
                if reservation["_room_number"] == str(room["number"]).strip()
                and reservation["_check_in"] <= current_day < reservation["_check_out"]
            ]
            booking = matching_reservations[0] if matching_reservations else None
            conflict = len(matching_reservations) > 1
            status = booking["status"] if booking else ""
            guest_names = list(dict.fromkeys(
                reservation.get("guest_name", "")
                for reservation in matching_reservations
                if reservation.get("guest_name")
            ))
            sources = {
                reservation.get("booking_source")
                for reservation in matching_reservations
            }
            cells.append({
                "status": "conflict" if conflict
                else "pending-payment" if status == "pending_payment"
                else "occupied" if status == "checked_in" else "booked" if booking else "",
                "guest": " / ".join(guest_names),
                "source": (
                    "Conflict" if conflict
                    else "Online" if sources == {"online"} else ""
                ),
                "reservation_id": booking.get("id") if booking else None,
                "selected": current_day == reference_date,
            })
        rows.append({"room": room["number"], "cells": cells})
    return [
        {"label": f"{day.strftime('%a %b')} {day.day}", "selected": day == reference_date}
        for day in days
    ], rows


def create_reference_room(form):
    number = form.get("number", "").strip()
    name = form.get("name", "").strip()
    try:
        beds = int(form.get("beds", ""))
        rate = int(form.get("rate", ""))
    except ValueError as error:
        raise ValueError("Enter a valid number of beds and nightly rate.") from error
    if not number or not name:
        raise ValueError("Room number and room type are required.")
    if beds < 1 or rate < 0:
        raise ValueError("Beds must be at least one and the nightly rate cannot be negative.")

    if SUPABASE_ENABLED:
        client = get_request_supabase()
        existing = client.table("rooms").select("number").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", number).limit(1).execute().data
        if existing:
            raise ValueError("A room with that number is already registered.")
        client.table("rooms").insert({
            "hotel_id": current_hotel_id(),
            "number": number,
            "name": name,
            "beds": beds,
            "rate": rate,
            "status": "unavailable",
        }).execute()
        return

    db = get_db()
    existing = db.execute(
        "SELECT 1 FROM rooms WHERE hotel_id = ? AND number = ?",
        (current_hotel_id(), number),
    ).fetchone()
    if existing:
        raise ValueError("A room with that number is already registered.")
    db.execute(
        """INSERT INTO rooms (number, hotel_id, name, beds, rate, status)
        VALUES (?, ?, ?, ?, ?, 'unavailable')""",
        (number, current_hotel_id(), name, beds, rate),
    )
    db.commit()


def update_reference_room(room_number, form):
    name = form.get("name", "").strip()
    try:
        beds = int(form.get("beds", ""))
        rate = int(form.get("rate", ""))
    except ValueError as error:
        raise ValueError("Enter a valid number of beds and nightly rate.") from error
    if not name:
        raise ValueError("Room category is required.")
    if beds < 1 or rate < 0:
        raise ValueError("Beds must be at least one and the nightly rate cannot be negative.")

    if SUPABASE_ENABLED:
        client = get_request_supabase()
        existing = client.table("rooms").select("number").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).limit(1).execute().data
        if not existing:
            raise ValueError("Room not found.")
        client.table("rooms").update({
            "name": name,
            "beds": beds,
            "rate": rate,
            "updated_at": datetime.now().isoformat(),
        }).eq("hotel_id", current_hotel_id()).eq("number", room_number).execute()
        return

    db = get_db()
    existing = db.execute(
        "SELECT 1 FROM rooms WHERE hotel_id = ? AND number = ?",
        (current_hotel_id(), room_number),
    ).fetchone()
    if not existing:
        raise ValueError("Room not found.")
    db.execute(
        "UPDATE rooms SET name = ?, beds = ?, rate = ? WHERE hotel_id = ? AND number = ?",
        (name, beds, rate, current_hotel_id(), room_number),
    )
    db.commit()


def room_has_history(room_number):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        reservations = client.table("reservations").select("id").eq(
            "hotel_id", current_hotel_id()
        ).eq("room_number", room_number
        ).limit(1).execute().data
        payments = client.table("payments").select("id").eq(
            "hotel_id", current_hotel_id()
        ).eq("room_number", room_number
        ).limit(1).execute().data
        return bool(reservations or payments)
    db = get_db()
    reservation = db.execute(
        "SELECT 1 FROM reservations WHERE hotel_id = ? AND room_number = ? LIMIT 1",
        (current_hotel_id(), room_number),
    ).fetchone()
    payment = db.execute(
        "SELECT 1 FROM payments WHERE hotel_id = ? AND room_number = ? LIMIT 1",
        (current_hotel_id(), room_number),
    ).fetchone()
    return bool(reservation or payment)


def room_has_active_booking(room_number):
    if SUPABASE_ENABLED:
        bookings = get_request_supabase().table("reservations").select(
            "status, hold_expires_at"
        ).eq(
            "hotel_id", current_hotel_id()
        ).eq("room_number", room_number
        ).in_("status", ["booked", "checked_in", "pending_payment"]).execute().data
    else:
        bookings = [
            dict(row) for row in get_db().execute(
                "SELECT status, hold_expires_at FROM reservations WHERE hotel_id = ? AND room_number = ? "
                "AND status IN ('booked', 'checked_in', 'pending_payment')",
                (current_hotel_id(), room_number),
            ).fetchall()
        ]
    return any(
        booking.get("status") in {"booked", "checked_in"}
        or booking.get("status") == "pending_payment"
        and timestamp_is_future(booking.get("hold_expires_at"))
        for booking in bookings
    )


def remove_reference_room(room_number):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        existing = client.table("rooms").select("number").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).limit(1).execute().data
        if not existing:
            raise ValueError("Room not found.")
    else:
        db = get_db()
        existing = db.execute(
            "SELECT 1 FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        ).fetchone()
        if not existing:
            raise ValueError("Room not found.")

    if room_has_active_booking(room_number):
        raise ValueError("A room with a current booking cannot be removed or marked unavailable.")

    if room_has_history(room_number):
        if SUPABASE_ENABLED:
            get_request_supabase().table("rooms").update({
                "status": "unavailable",
                "updated_at": datetime.now().isoformat(),
            }).eq("hotel_id", current_hotel_id()).eq(
                "number", room_number
            ).execute()
        else:
            db.execute(
                "UPDATE rooms SET status = 'unavailable' WHERE hotel_id = ? AND number = ?",
                (current_hotel_id(), room_number),
            )
            db.commit()
        return False

    if SUPABASE_ENABLED:
        listings = get_request_supabase().table("online_room_listings").select(
            "photo_path"
        ).eq("hotel_id", current_hotel_id()).eq(
            "room_number", room_number
        ).limit(1).execute().data
        if listings:
            photo_path = listings[0].get("photo_path")
            if photo_path:
                get_supabase_admin().storage.from_(ROOM_PHOTO_BUCKET).remove(
                    [photo_path]
                )
            get_request_supabase().table("online_room_listings").delete().eq(
                "hotel_id", current_hotel_id()
            ).eq("room_number", room_number
            ).execute()
        get_request_supabase().table("rooms").delete().eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).execute()
    else:
        listing = db.execute(
            """SELECT photo_path FROM online_room_listings
            WHERE hotel_id = ? AND room_number = ?""",
            (current_hotel_id(), room_number),
        ).fetchone()
        if listing:
            photo_path = listing["photo_path"]
            if photo_path and re.fullmatch(
                rf"(?:{re.escape(current_hotel_id())}/)?[a-f0-9]{{32}}\.(?:jpg|jpeg|png|webp)",
                photo_path,
            ):
                photo = ROOM_PHOTO_DIRECTORY / photo_path
                if photo.is_file():
                    photo.unlink()
            db.execute(
                "DELETE FROM online_room_listings WHERE hotel_id = ? AND room_number = ?",
                (current_hotel_id(), room_number),
            )
        db.execute(
            "DELETE FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        )
        db.commit()
    return True


def rooms_with_history(rooms):
    return {
        room["number"]
        for room in rooms
        if room_has_history(room["number"])
    }


def dashboard_stats():
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("*").eq(
            "hotel_id", current_hotel_id()
        ).order("number").execute().data
        reservations = client.table("reservations").select(
            "amount_paid, payment_status, status, check_in, check_out"
        ).eq("hotel_id", current_hotel_id()).execute().data
        today = date.today().isoformat()
        reservation_count = sum(
            row["status"] not in {"checked_out", "cancelled"} for row in reservations
        )
        revenue = sum(row["amount_paid"] for row in reservations)
        pending = sum(
            row["payment_status"] == "pending" and row["status"] != "cancelled"
            for row in reservations
        )
        occupied = sum(room["status"] == "occupied" for room in rooms)
        occupancy = round(occupied * 100 / len(rooms)) if rooms else 0
        arrivals_today = sum(
            row["check_in"] == today and row["status"] != "cancelled"
            for row in reservations
        )
        check_outs = sum(
            row["status"] in {"booked", "checked_in"} and row["check_out"] == today
            for row in reservations
        )
        return rooms, {
            "reservations": reservation_count,
            "revenue": revenue,
            "pending": pending,
            "occupancy": occupancy,
            "arrivals_today": arrivals_today,
            "check_outs": check_outs,
        }
    db = get_db()
    hotel_id = current_hotel_id()
    rooms = db.execute(
        "SELECT * FROM rooms WHERE hotel_id = ? ORDER BY number", (hotel_id,)
    ).fetchall()
    reservation_count = db.execute(
        """SELECT COUNT(*) FROM reservations WHERE hotel_id = ?
        AND status NOT IN ('checked_out', 'cancelled')""",
        (hotel_id,),
    ).fetchone()[0]
    revenue = db.execute(
        "SELECT COALESCE(SUM(amount_paid), 0) FROM reservations WHERE hotel_id = ?",
        (hotel_id,),
    ).fetchone()[0]
    pending = db.execute(
        """SELECT COUNT(*) FROM reservations WHERE hotel_id = ?
        AND payment_status = 'pending' AND status != 'cancelled'""",
        (hotel_id,),
    ).fetchone()[0]
    occupied = sum(room["status"] == "occupied" for room in rooms)
    occupancy = round(occupied * 100 / len(rooms)) if rooms else 0
    today = date.today().isoformat()
    arrivals_today = db.execute(
        """SELECT COUNT(*) FROM reservations
        WHERE hotel_id = ? AND check_in = ? AND status != 'cancelled'""",
        (hotel_id, today),
    ).fetchone()[0]
    check_outs = db.execute(
        """SELECT COUNT(*) FROM reservations WHERE hotel_id = ?
        AND status IN ('booked', 'checked_in') AND check_out = ?""",
        (hotel_id, today),
    ).fetchone()[0]
    return rooms, {
        "reservations": reservation_count,
        "revenue": revenue,
        "pending": pending,
        "occupancy": occupancy,
        "arrivals_today": arrivals_today,
        "check_outs": check_outs,
    }


@app.context_processor
def inject_globals():
    hotel = hotel_details(session.get("hotel_id")) if session.get("hotel_id") else None
    return {
        "today": date.today().isoformat(),
        "active_role": request.args.get("role", "reception"),
        "hotel_name": hotel["name"] if hotel else "Hotel Booking Platform",
        "hotel_slug": hotel["slug"] if hotel else "",
    }


@app.errorhandler(SupabaseSessionExpired)
def handle_supabase_session_expired(error):
    flash("Your session has expired. Please sign in again.", "error")
    return redirect(url_for("login", role=error.role))


@app.before_request
def require_workspace_login():
    endpoint = request.endpoint
    if endpoint in {
        "home", "health", "login", "manager_signup", "logout", "static",
        "billing", "start_subscription_payment", "save_billing_email",
        "paystack_callback", "paystack_webhook",
    }:
        return None
    if request.path.startswith("/workspace/"):
        required_role = (request.view_args or {}).get("role")
        if required_role is None:
            required_role = request.path.split("/", 3)[2]
    elif endpoint == "reference_workspace":
        required_role = (request.view_args or {}).get("role")
    elif endpoint == "update_room":
        required_role = "reception"
    elif endpoint in {"manage_room", "manage_online_room"}:
        required_role = "manager"
    elif endpoint in {
        "confirm_online_booking_route", "cancel_online_booking_route"
    }:
        required_role = "reception"
    elif endpoint in {"dashboard", "reservations", "new_reservation"}:
        required_role = request.args.get("role", "reception")
    elif endpoint == "update_reservation":
        required_role = request.form.get("role", "reception")
    else:
        required_role = None
    if required_role and (
        session.get("user_role") != required_role or not session.get("hotel_id")
    ):
        return redirect(url_for("login", role=required_role))
    if required_role and session.get("hotel_id"):
        access = subscription_access(session["hotel_id"])
        if not access["allowed"]:
            return redirect(url_for("billing"))
    return None


@app.route("/book", methods=["GET", "POST"])
def public_booking():
    today = date.today()
    default_check_in = today + timedelta(days=1)
    default_check_out = default_check_in + timedelta(days=1)
    hotels = public_hotels()
    requested_hotel_slug = (
        request.form.get("hotel_slug", "") if request.method == "POST"
        else request.args.get("hotel", "")
    )
    selected_hotel = next(
        (hotel for hotel in hotels if hotel["slug"] == requested_hotel_slug),
        None,
    )
    submitted_filters = request.form if request.method == "POST" else request.args
    selected_price_range = submitted_filters.get("price_range", "").strip()
    if selected_price_range and price_range_bounds(selected_price_range) is None:
        selected_price_range = ""
    try:
        check_in = date.fromisoformat(submitted_filters.get(
            "check_in", default_check_in.isoformat()
        ))
        check_out = date.fromisoformat(submitted_filters.get(
            "check_out", default_check_out.isoformat()
        ))
    except ValueError:
        flash("Choose valid arrival and departure dates.", "error")
        check_in, check_out = default_check_in, default_check_out

    if request.method == "POST":
        csrf_token = session.get("public_booking_csrf", "")
        if not csrf_token or not hmac.compare_digest(
            csrf_token, request.form.get("csrf_token", "")
        ):
            flash("This booking form expired. Refresh the page and try again.", "error")
        else:
            session["public_booking_csrf"] = secrets.token_urlsafe(32)
            try:
                if not selected_hotel or request.form.get(
                    "hotel_id"
                ) != selected_hotel["id"]:
                    raise ValueError("Choose the hotel you want to book.")
                create_online_booking(request.form)
                return redirect(url_for("online_booking_confirmation"))
            except ValueError as error:
                flash(str(error), "error")
    session.setdefault("public_booking_csrf", secrets.token_urlsafe(32))

    rooms = []
    if selected_hotel and check_in >= today and check_out > check_in:
        rooms = filter_rooms_by_price_range(
            available_online_rooms(
                check_in, check_out, hotel_id=selected_hotel["id"]
            ),
            selected_price_range,
        )
    hotel_cards = hotels
    if not selected_hotel and selected_price_range:
        matching_hotels = []
        if check_in >= today and check_out > check_in:
            for hotel in hotels:
                matching_rooms = filter_rooms_by_price_range(
                    available_online_rooms(
                        check_in, check_out, hotel_id=hotel["id"]
                    ),
                    selected_price_range,
                )
                if matching_rooms:
                    matching_hotels.append({
                        **hotel,
                        "matching_room_count": len(matching_rooms),
                        "lowest_matching_rate": min(
                            room["rate"] for room in matching_rooms
                        ),
                    })
        hotel_cards = matching_hotels
    state_filter = request.args.get("state", "").strip()
    if state_filter not in NIGERIAN_STATES:
        state_filter = ""
    return render_template(
        "public_booking.html",
        hotels=hotel_cards,
        selected_hotel=selected_hotel,
        rooms=rooms,
        check_in=check_in.isoformat(),
        check_out=check_out.isoformat(),
        today=today.isoformat(),
        csrf_token=session["public_booking_csrf"],
        nigerian_states=NIGERIAN_STATES,
        selected_state=state_filter,
        city_query=request.args.get("city", "").strip(),
        price_ranges=PUBLIC_PRICE_RANGES,
        selected_price_range=selected_price_range,
    )


@app.get("/booking/confirmation")
def online_booking_confirmation():
    confirmation = session.get("online_booking_confirmation")
    if not confirmation:
        return redirect(url_for("public_booking"))
    return render_template("online_booking_confirmation.html", confirmation=confirmation)


@app.get("/room-photos/<path:photo_path>")
def online_room_photo(photo_path):
    valid_path = re.fullmatch(
        r"(?:[0-9a-f-]{36}/)?[a-f0-9]{32}\.(?:jpg|jpeg|png|webp)",
        photo_path,
    )
    if SUPABASE_ENABLED or not valid_path:
        return "", 404
    return send_from_directory(ROOM_PHOTO_DIRECTORY, photo_path)


@app.post("/rooms/<room_number>/online")
def manage_online_room(room_number):
    try:
        uploaded_files = request.files.getlist("photos")
        if not any(uploaded_file.filename for uploaded_file in uploaded_files):
            uploaded_files = [request.files.get("photo")]
        save_room_photos(room_number, uploaded_files)
        flash(f"Room photos for {room_number} uploaded.", "success")
    except ValueError as error:
        flash(str(error), "error")
    return redirect(url_for(
        "reference_workspace", role="manager", page="online-settings"
    ))


@app.post("/online-bookings/<reservation_id>/confirm")
def confirm_online_booking_route(reservation_id):
    try:
        if SUPABASE_ENABLED:
            reservations = get_request_supabase().table("reservations").select(
                "check_in"
            ).eq("hotel_id", current_hotel_id()).eq(
                "id", reservation_id
            ).eq("status", "pending_payment").limit(1).execute().data
            reservation = reservations[0] if reservations else None
        else:
            reservation = get_db().execute(
                """SELECT check_in FROM reservations
                WHERE hotel_id = ? AND id = ? AND status = 'pending_payment'""",
                (current_hotel_id(), reservation_id),
            ).fetchone()
        if not reservation:
            raise ValueError(
                "This online request is no longer awaiting confirmation."
            )
        confirm_online_booking(reservation_id, session.get("username", "Reception"))
        flash(f"Online booking {reservation_id} confirmed and payment recorded.", "success")
        return redirect(url_for(
            "reference_workspace",
            role="reception",
            page="calendar",
            reference_date=reservation["check_in"],
        ))
    except ValueError as error:
        flash(str(error), "error")
    return redirect(url_for("reference_workspace", role="reception", page="online"))


@app.post("/online-bookings/<reservation_id>/cancel")
def cancel_online_booking_route(reservation_id):
    if SUPABASE_ENABLED:
        result = get_request_supabase().table("reservations").update({
            "status": "cancelled",
            "hold_expires_at": None,
        }).eq("id", reservation_id).eq(
            "hotel_id", current_hotel_id()
        ).eq("status", "pending_payment"
        ).select("id").execute().data
        if not result:
            flash("This request has expired or is no longer awaiting payment.", "error")
            return redirect(url_for(
                "reference_workspace", role="reception", page="online"
            ))
    else:
        result = get_db().execute(
            """UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL
            WHERE hotel_id = ? AND id = ? AND status = 'pending_payment'""",
            (current_hotel_id(), reservation_id),
        )
        if not result.rowcount:
            flash("This request has expired or is no longer awaiting payment.", "error")
            return redirect(url_for(
                "reference_workspace", role="reception", page="online"
            ))
        get_db().commit()
    flash(f"Online booking request {reservation_id} was released.", "success")
    return redirect(url_for("reference_workspace", role="reception", page="online"))


@app.route("/")
def home():
    return render_template("landing.html")


@app.get("/health")
def health():
    return {"status": "ok"}, 200


@app.get("/logout")
def logout():
    if SUPABASE_ENABLED and session.get("supabase_access_token"):
        try:
            get_request_supabase().auth.sign_out()
        except Exception:
            pass
    session.clear()
    return redirect(url_for("home"))


@app.route("/login/<role>", methods=["GET", "POST"])
def login(role):
    if role not in {"director", "manager", "reception"}:
        return redirect(url_for("home"))
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        submitted_password = request.form.get("password", "")
        if SUPABASE_ENABLED:
            try:
                client = get_supabase_auth()
                auth_response = client.auth.sign_in_with_password(
                    {"email": auth_email(username), "password": submitted_password}
                )
                user = auth_response.user
                profiles = client.table("profiles").select(
                    "username, role, hotel_id"
                ).eq("id", user.id).limit(1).execute().data
                profile = profiles[0] if profiles else None
                if not profile or profile["role"] != role:
                    client.auth.sign_out()
                    raise ValueError("Role does not match this login.")
                session.clear()
                session["user_role"] = profile["role"]
                session["username"] = profile["username"]
                session["hotel_id"] = profile["hotel_id"]
                session["supabase_user_id"] = user.id
                session["supabase_access_token"] = auth_response.session.access_token
                session["supabase_refresh_token"] = auth_response.session.refresh_token
                return redirect(url_for("reference_workspace", role=role, page="dashboard"))
            except Exception:
                return render_template("login.html", role=role, account_exists=True, error="Invalid login details.")
        user = get_db().execute(
            "SELECT * FROM users WHERE role = ? AND username = ?",
            (role, username),
        ).fetchone()
        if user and password_is_valid(user["password"], submitted_password):
            if not user["password"].startswith("scrypt:"):
                get_db().execute(
                    "UPDATE users SET password = ? WHERE id = ?",
                    (generate_password_hash(submitted_password), user["id"]),
                )
                get_db().commit()
            session["user_role"] = role
            session["username"] = user["username"]
            session["hotel_id"] = user["hotel_id"]
            return redirect(url_for("reference_workspace", role=role, page="dashboard"))
        return render_template("login.html", role=role, account_exists=True, error="Invalid login details.")
    if SUPABASE_ENABLED:
        account_exists = bool(
            get_supabase_admin().table("profiles").select("id").eq(
                "role", role
            ).limit(1).execute().data
        )
    else:
        account_exists = get_db().execute(
            "SELECT 1 FROM users WHERE role = ?", (role,),
        ).fetchone() is not None
    return render_template("login.html", role=role, account_exists=account_exists)


def hotel_slug_from_name(name, hotel_id):
    base = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:70].strip("-")
    suffix = (
        "" if hotel_id == DEFAULT_HOTEL_ID
        else f"-{hotel_id.replace('-', '')[:8]}"
    )
    return f"{base or 'hotel'}{suffix}"


@app.route("/signup/manager", methods=["GET", "POST"])
def manager_signup():
    editing = session.get("user_role") == "manager" and bool(session.get("hotel_id"))
    hotel_id = current_hotel_id() if editing else None
    if editing and not subscription_access(hotel_id)["allowed"]:
        return redirect(url_for("billing"))
    if SUPABASE_ENABLED:
        supabase_admin = get_supabase_admin()
        existing_profiles = (
            supabase_admin.table("profiles").select("id, role, username").eq(
                "hotel_id", hotel_id
            ).execute().data if editing else []
        )
    else:
        supabase_admin = None
        existing_profiles = []
        if editing:
            existing_profiles = [
                dict(row) for row in get_db().execute(
                    "SELECT id, role, username FROM users WHERE hotel_id = ?",
                    (hotel_id,),
                ).fetchall()
            ]
    account_map = {profile["role"]: profile["username"] for profile in existing_profiles}
    current_hotel = hotel_details(hotel_id) if editing else None
    hotel_name = current_hotel["name"] if current_hotel else ""
    hotel_location = {
        "address": current_hotel.get("address", "") if current_hotel else "",
        "city": current_hotel.get("city", "") if current_hotel else "",
        "state": current_hotel.get("state", "") if current_hotel else "",
    }
    selected_plan = "trial"
    billing_email = ""

    def render_signup_page(error=None):
        return render_template(
            "manager_signup.html",
            error=error,
            account_map=account_map,
            editing=editing,
            hotel_name=hotel_name,
            hotel_id=hotel_id,
            hotel_location=hotel_location,
            nigerian_states=NIGERIAN_STATES,
            selected_plan=selected_plan,
            billing_email=billing_email,
        )

    if request.method == "POST":
        hotel_name = request.form.get("hotel_name", "").strip()
        hotel_location = {
            "address": request.form.get("hotel_address", "").strip(),
            "city": request.form.get("hotel_city", "").strip(),
            "state": request.form.get("hotel_state", "").strip(),
        }
        selected_plan = request.form.get("plan", "trial").strip().lower()
        billing_email = request.form.get("billing_email", "").strip().lower()
        fields = {
            "director": (request.form.get("director_username", "").strip(), request.form.get("director_password", "")),
            "reception": (request.form.get("reception_username", "").strip(), request.form.get("reception_password", "")),
        }
        if not editing:
            fields["manager"] = (request.form.get("manager_username", "").strip(), request.form.get("manager_password", ""))
        if not 2 <= len(hotel_name) <= 120:
            return render_signup_page("Enter a hotel name between 2 and 120 characters.")
        if not 3 <= len(hotel_location["address"]) <= 300:
            return render_signup_page(
                "Enter a hotel street address between 3 and 300 characters."
            )
        if not 2 <= len(hotel_location["city"]) <= 100:
            return render_signup_page("Enter a city between 2 and 100 characters.")
        if hotel_location["state"] not in NIGERIAN_STATES:
            return render_signup_page("Choose a valid Nigerian state or the FCT.")
        if not editing and selected_plan not in {"trial", "monthly", "annual"}:
            return render_signup_page("Choose a valid subscription plan.")
        if not editing and (
            len(billing_email) > 254
            or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", billing_email)
        ):
            return render_signup_page("Enter a valid billing email address.")
        if any(not username or not password for username, password in fields.values()):
            return render_signup_page("Complete every required hotel team account.")
        if SUPABASE_ENABLED:
            try:
                if editing:
                    saved_hotel_id = hotel_id
                elif existing_profiles:
                    raise ValueError("This hotel already has a Manager account.")
                else:
                    saved_hotel_id = str(uuid4())
                    if not supabase_admin.table("profiles").select(
                        "id"
                    ).eq("hotel_id", DEFAULT_HOTEL_ID).limit(1).execute().data:
                        saved_hotel_id = DEFAULT_HOTEL_ID
                    supabase_admin.table("hotels").upsert({
                        "id": saved_hotel_id,
                        "name": hotel_name,
                        "slug": hotel_slug_from_name(hotel_name, saved_hotel_id),
                        **hotel_location,
                        "is_active": True,
                    }).execute()
                    supabase_admin.table("online_booking_settings").upsert({
                        "hotel_id": saved_hotel_id,
                        "bank_name": "",
                        "account_name": "",
                        "account_number": "",
                        "reception_whatsapp": "",
                        "reception_email": "",
                        "updated_at": now_iso(),
                    }).execute()
                supabase_admin.table("hotels").update({
                    "name": hotel_name,
                    "slug": hotel_slug_from_name(hotel_name, saved_hotel_id),
                    **hotel_location,
                }).eq("id", saved_hotel_id).execute()
                existing_by_role = {profile["role"]: profile for profile in existing_profiles}
                for account_role, (username, password) in fields.items():
                    email = auth_email(username)
                    existing_profile = existing_by_role.get(account_role)
                    if existing_profile:
                        user_id = existing_profile["id"]
                        supabase_admin.auth.admin.update_user_by_id(
                            user_id,
                            {
                                "email": email,
                                "password": password,
                                "email_confirm": True,
                                "app_metadata": {
                                    "role": account_role,
                                    "hotel_id": saved_hotel_id,
                                },
                                "user_metadata": {
                                    "username": username,
                                    "hotel_id": saved_hotel_id,
                                },
                            },
                        )
                        supabase_admin.table("profiles").update({
                            "username": username,
                            "hotel_id": saved_hotel_id,
                        }).eq("id", user_id).execute()
                    else:
                        created_user = supabase_admin.auth.admin.create_user(
                            {
                                "email": email,
                                "password": password,
                                "email_confirm": True,
                                "app_metadata": {
                                    "role": account_role,
                                    "hotel_id": saved_hotel_id,
                                },
                                "user_metadata": {
                                    "username": username,
                                    "hotel_id": saved_hotel_id,
                                },
                            }
                        ).user
                        supabase_admin.table("profiles").insert(
                            {
                                "id": created_user.id,
                                "role": account_role,
                                "username": username,
                                "hotel_id": saved_hotel_id,
                                "created_by": session.get("supabase_user_id"),
                            }
                        ).execute()
                if not editing:
                    create_hotel_subscription(
                        saved_hotel_id, selected_plan, billing_email
                    )
                    if selected_plan in {"monthly", "annual"}:
                        try:
                            checkout_url = initialize_subscription_payment(
                                saved_hotel_id, selected_plan
                            )
                        except (RuntimeError, ValueError) as error:
                            app.logger.warning(
                                "Could not initialize signup subscription checkout: %s",
                                error,
                            )
                            flash(
                                "Your hotel is registered, but payment checkout "
                                "could not start. Sign in as Manager and retry from "
                                "Plan & Billing.",
                                "error",
                            )
                            return redirect(url_for("login", role="manager"))
                        return redirect(checkout_url, code=303)
                return redirect(url_for("login", role="manager"))
            except Exception:
                app.logger.exception("Failed to save hotel team accounts")
                return render_signup_page(
                    "Could not save the hotel accounts. Check usernames and try again."
                )
        db = get_db()
        try:
            if editing:
                saved_hotel_id = hotel_id
                db.execute(
                    """UPDATE hotels SET name = ?, slug = ?, address = ?, city = ?,
                    state = ? WHERE id = ?""",
                    (
                        hotel_name, hotel_slug_from_name(hotel_name, hotel_id),
                        hotel_location["address"], hotel_location["city"],
                        hotel_location["state"], hotel_id,
                    ),
                )
                for account_role, (username, password) in fields.items():
                    db.execute(
                        """UPDATE users SET username = ?, password = ?
                        WHERE hotel_id = ? AND role = ?""",
                        (
                            username, generate_password_hash(password),
                            hotel_id, account_role,
                        ),
                    )
            else:
                saved_hotel_id = str(uuid4())
                if not db.execute(
                    "SELECT 1 FROM users WHERE hotel_id = ? LIMIT 1",
                    (DEFAULT_HOTEL_ID,),
                ).fetchone():
                    saved_hotel_id = DEFAULT_HOTEL_ID
                db.execute(
                    """INSERT INTO hotels
                    (id, name, slug, address, city, state, is_active, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name,
                    slug = excluded.slug, address = excluded.address,
                    city = excluded.city, state = excluded.state""",
                    (
                        saved_hotel_id, hotel_name,
                        hotel_slug_from_name(hotel_name, saved_hotel_id),
                        hotel_location["address"], hotel_location["city"],
                        hotel_location["state"], now_iso(),
                    ),
                )
                db.execute(
                    """INSERT OR IGNORE INTO online_booking_settings
                    (hotel_id, updated_at) VALUES (?, ?)""",
                    (saved_hotel_id, now_iso()),
                )
                db.executemany(
                    """INSERT INTO users
                    (hotel_id, role, username, password, created_at)
                    VALUES (?, ?, ?, ?, ?)""",
                    [
                        (
                            saved_hotel_id, account_role, username,
                            generate_password_hash(password), now_iso(),
                        )
                        for account_role, (username, password) in fields.items()
                    ],
                )
                if not editing:
                    now = datetime.now(timezone.utc)
                    is_trial = selected_plan == "trial"
                    db.execute(
                        """INSERT INTO hotel_subscriptions
                        (hotel_id, plan, status, trial_started_at, trial_ends_at,
                         billing_email, pending_plan, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            saved_hotel_id,
                            "trial" if is_trial else selected_plan,
                            "trial" if is_trial else "pending",
                            now.isoformat(timespec="seconds") if is_trial else None,
                            (
                                (now + timedelta(days=TRIAL_DAYS)).isoformat(
                                    timespec="seconds"
                                )
                                if is_trial else None
                            ),
                            billing_email,
                            None if is_trial else selected_plan,
                            now.isoformat(timespec="seconds"),
                        ),
                    )
            db.commit()
        except sqlite3.IntegrityError:
            db.rollback()
            return render_signup_page("An account or username already exists.")
        if not editing and selected_plan in {"monthly", "annual"}:
            try:
                checkout_url = initialize_subscription_payment(
                    saved_hotel_id, selected_plan
                )
            except (RuntimeError, ValueError) as error:
                app.logger.warning(
                    "Could not initialize signup subscription checkout: %s",
                    error,
                )
                flash(
                    "Your hotel is registered, but payment checkout could not "
                    "start. Sign in as Manager and retry from Plan & Billing.",
                    "error",
                )
                return redirect(url_for("login", role="manager"))
            return redirect(checkout_url, code=303)
        return redirect(url_for("login", role="manager"))
    return render_signup_page()


@app.route("/billing")
def billing():
    hotel_id = session.get("hotel_id")
    if not hotel_id or session.get("user_role") not in {
        "manager", "director", "reception"
    }:
        return redirect(url_for("login", role="manager"))
    ensure_legacy_subscription(hotel_id)
    record = subscription_record(hotel_id)
    access = subscription_access(hotel_id)
    csrf_token = session.setdefault("billing_csrf_token", secrets.token_urlsafe(32))
    return render_template(
        "billing.html",
        role=session["user_role"],
        page="billing",
        record=record,
        access=access,
        csrf_token=csrf_token,
        is_manager=session["user_role"] == "manager",
        trial_days=TRIAL_DAYS,
        monthly_amount=MONTHLY_PLAN_AMOUNT,
        annual_amount=ANNUAL_PLAN_AMOUNT,
    )


def billing_manager_required():
    if session.get("user_role") != "manager" or not session.get("hotel_id"):
        return redirect(url_for("login", role="manager"))
    return None


def valid_billing_csrf():
    return bool(
        session.get("billing_csrf_token")
        and hmac.compare_digest(
            session["billing_csrf_token"],
            request.form.get("csrf_token", ""),
        )
    )


@app.route("/billing/email", methods=["POST"])
def save_billing_email():
    denied = billing_manager_required()
    if denied:
        return denied
    if not valid_billing_csrf():
        return "Invalid billing form. Reload the page and try again.", 400
    email = request.form.get("billing_email", "").strip().lower()
    if len(email) > 254 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        flash("Enter a valid billing email address.", "error")
        return redirect(url_for("billing"))
    hotel_id = session["hotel_id"]
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if SUPABASE_ENABLED:
        get_supabase_admin().table("hotel_subscriptions").update({
            "billing_email": email,
            "updated_at": now,
        }).eq("hotel_id", hotel_id).execute()
    else:
        db = get_db()
        db.execute(
            """UPDATE hotel_subscriptions SET billing_email = ?, updated_at = ?
            WHERE hotel_id = ?""",
            (email, now, hotel_id),
        )
        db.commit()
    flash("Billing email saved.", "success")
    return redirect(url_for("billing"))


@app.route("/billing/subscribe", methods=["POST"])
def start_subscription_payment():
    denied = billing_manager_required()
    if denied:
        return denied
    if not valid_billing_csrf():
        return "Invalid billing form. Reload the page and try again.", 400
    plan = request.form.get("plan", "").strip().lower()
    try:
        checkout_url = initialize_subscription_payment(
            session["hotel_id"], plan
        )
    except (RuntimeError, ValueError) as error:
        app.logger.warning("Could not initialize subscription checkout: %s", error)
        flash(str(error), "error")
        return redirect(url_for("billing"))
    return redirect(checkout_url, code=303)


def verify_paystack_subscription(reference):
    if not reference or len(reference) > 120:
        raise ValueError("The payment reference is invalid.")
    data = paystack_request(
        "/transaction/verify/" + quote(reference, safe="")
    )
    if (
        data.get("status") != "success"
        or data.get("reference") != reference
        or not isinstance(data.get("amount"), int)
        or data.get("currency") != "NGN"
        or data.get("id") is None
    ):
        raise ValueError("Paystack has not confirmed this subscription payment.")
    activate_subscription_payment(
        reference, data["id"], data["amount"], data["currency"]
    )


@app.route("/billing/paystack/callback")
def paystack_callback():
    reference = request.args.get("reference") or request.args.get("trxref")
    try:
        verify_paystack_subscription(reference)
    except ValueError as error:
        app.logger.warning("Subscription callback verification failed: %s", error)
        flash(str(error), "error")
    except Exception:
        app.logger.exception("Subscription callback verification failed")
        flash("Payment could not be verified yet. Please check Plan & Billing.", "error")
    else:
        flash("Payment confirmed. Your subscription is now active.", "success")
    if session.get("hotel_id"):
        return redirect(url_for("billing"))
    return redirect(url_for("login", role="manager"))


@app.route("/billing/paystack/webhook", methods=["POST"])
def paystack_webhook():
    try:
        secret = paystack_secret_key()
    except ValueError:
        app.logger.error("Paystack webhook received before payments were configured")
        return "Webhook is not configured.", 503
    raw_body = request.get_data(cache=False)
    signature = request.headers.get("x-paystack-signature", "")
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha512).hexdigest()
    if not signature or not hmac.compare_digest(signature, expected):
        return "Invalid signature.", 401
    try:
        payload = json.loads(raw_body)
    except json.JSONDecodeError:
        return "Invalid payload.", 400
    if not isinstance(payload, dict):
        return "Invalid payload.", 400
    if payload.get("event") != "charge.success":
        return "Ignored.", 200
    transaction = payload.get("data") or {}
    reference = transaction.get("reference")
    try:
        verify_paystack_subscription(reference)
    except ValueError as error:
        app.logger.warning("Paystack webhook verification failed: %s", error)
        return "Payment not verified.", 400
    except Exception:
        app.logger.exception("Paystack webhook could not verify transaction")
        return "Verification temporarily unavailable.", 503
    return "OK.", 200


def raise_supabase_reservation_conflict(error):
    if error.code == "P0001" and error.message and (
        "already has a booking" in error.message
    ):
        raise ValueError(
            "That room already has a booking during the selected dates."
        ) from error
    raise error


def create_reference_booking(form):
    check_in = datetime.strptime(form["check_in"], "%Y-%m-%d").date()
    check_out = datetime.strptime(form["check_out"], "%Y-%m-%d").date()
    nights = (check_out - check_in).days
    if nights < 1:
        raise ValueError("Check-out must be after check-in.")
    if check_in < date.today():
        raise ValueError("Arrival date cannot be in the past.")
    if check_out <= date.today():
        raise ValueError("Departure date must be in the future.")
    room_number = form["room_number"]
    payment_method = form.get("payment_method", "Cash")
    if payment_method not in {"Cash", "POS", "Transfer"}:
        raise ValueError("Choose a valid payment method.")
    guest_name = form["guest_name"].strip()
    phone = form["phone"].strip()
    if not guest_name or not phone:
        raise ValueError("Guest name and phone number are required.")

    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("rate, status").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number).limit(1).execute().data
        room = rooms[0] if rooms else None
        if not room or str(room["status"]).lower() in {"unavailable", "cleaning"}:
            raise ValueError("That room is no longer available.")
        occupied_dates = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("hotel_id", current_hotel_id()).eq("room_number", room_number).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
    else:
        db = get_db()
        db.execute("BEGIN IMMEDIATE")
        room = db.execute(
            "SELECT rate, status FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        ).fetchone()
        if not room or str(room["status"]).lower() in {"unavailable", "cleaning"}:
            db.rollback()
            raise ValueError("That room is no longer available.")
        occupied_dates = db.execute(
            """SELECT id, check_in, check_out, status, hold_expires_at
            FROM reservations WHERE hotel_id = ? AND room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')""",
            (current_hotel_id(), room_number),
        ).fetchall()
    if any(
        (
            stay["status"] != "pending_payment"
            or timestamp_is_future(stay["hold_expires_at"])
        )
        and check_in.isoformat() < stay["check_out"]
        and check_out.isoformat() > stay["check_in"]
        for stay in occupied_dates
    ):
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("That room already has a booking during the selected dates.")

    if SUPABASE_ENABLED:
        amount = int(form.get("total_amount") or nights * room["rate"])
        amount_paid = int(form.get("amount_paid") or 0)
        if amount < 0 or amount_paid < 0 or amount_paid > amount:
            raise ValueError("Check the booking amount and amount paid.")
        payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
        from postgrest.exceptions import APIError

        try:
            results = client.table("reservations").insert({
                "hotel_id": current_hotel_id(),
                "guest_name": guest_name,
                "email": form.get("email", "").strip(),
                "phone": phone,
                "room_number": room_number,
                "check_in": check_in.isoformat(),
                "check_out": check_out.isoformat(),
                "amount": amount,
                "amount_paid": amount_paid,
                "payment_method": payment_method,
                "payment_status": payment_status,
                "status": "checked_in" if check_in == date.today() else "booked",
                "created_by": session.get("supabase_user_id"),
            }).select("*").execute().data
        except APIError as error:
            raise_supabase_reservation_conflict(error)
        if not results:
            raise RuntimeError("Supabase did not return the created booking.")
        result = results[0]
        if check_in == date.today():
            client.table("rooms").update({"status": "occupied"}).eq(
                "hotel_id", current_hotel_id()
            ).eq("number", room_number).execute()
        if amount_paid:
            client.table("payments").insert({
                "hotel_id": current_hotel_id(),
                "reservation_id": result["id"],
                "room_number": room_number,
                "amount": amount_paid,
                "balance": amount - amount_paid,
                "method": payment_method,
                "received_by": session.get("username", "Reception"),
            }).execute()
        return result

    db = get_db()
    amount = int(form.get("total_amount") or nights * room["rate"])
    amount_paid = int(form.get("amount_paid") or 0)
    if amount < 0 or amount_paid < 0 or amount_paid > amount:
        db.rollback()
        raise ValueError("Check the booking amount and amount paid.")
    payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
    cursor = db.execute(
        """INSERT INTO reservations
        (hotel_id, guest_name, email, phone, room_number, check_in, check_out, amount, amount_paid,
         payment_method, payment_status, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (current_hotel_id(), guest_name, form.get("email", "").strip(), phone, room_number, check_in.isoformat(),
         check_out.isoformat(), amount, amount_paid, payment_method, payment_status,
         "checked_in" if check_in == date.today() else "booked",
         datetime.now().isoformat(timespec="seconds")),
    )
    if check_in == date.today():
        db.execute(
            "UPDATE rooms SET status = 'occupied' WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        )
    if amount_paid:
        db.execute(
            """INSERT INTO payments
            (hotel_id, reservation_id, room_number, amount, balance, method, received_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (current_hotel_id(), cursor.lastrowid, room_number, amount_paid, amount - amount_paid, payment_method,
             session.get("username", "Reception"), datetime.now().isoformat(timespec="seconds")),
        )
    db.commit()
    return {"id": cursor.lastrowid}


def extend_reference_reservation(reservation_id, form):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        results = client.table("reservations").select("*").eq(
            "hotel_id", current_hotel_id()
        ).eq("id", reservation_id).limit(1).execute().data
        reservation = results[0] if results else None
    else:
        db = get_db()
        db.execute("BEGIN IMMEDIATE")
        reservation = db.execute(
            "SELECT * FROM reservations WHERE hotel_id = ? AND id = ?",
            (current_hotel_id(), reservation_id),
        ).fetchone()
        reservation = dict(reservation) if reservation else None
    if not reservation or reservation["status"] not in {"booked", "checked_in"}:
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("Only a current stay can be extended.")

    try:
        current_departure = date.fromisoformat(str(reservation["check_out"])[:10])
        new_departure = date.fromisoformat(str(form["check_out"])[:10])
    except (KeyError, TypeError, ValueError) as error:
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("Choose a valid new departure date.") from error
    if new_departure <= current_departure:
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("The new departure date must be after the current departure.")

    if SUPABASE_ENABLED:
        other_stays = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("hotel_id", current_hotel_id()).eq(
            "room_number", reservation["room_number"]
        ).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
        has_conflict = any(
            str(stay["id"]) != str(reservation_id)
            and (
                stay["status"] != "pending_payment"
                or timestamp_is_future(stay.get("hold_expires_at"))
            )
            and date.fromisoformat(str(stay["check_in"])[:10]) < new_departure
            and date.fromisoformat(str(stay["check_out"])[:10]) > current_departure
            for stay in other_stays
        )
        room_results = client.table("rooms").select("rate").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", reservation["room_number"]
        ).limit(1).execute().data
        room = room_results[0] if room_results else None
    else:
        has_conflict = db.execute(
            """SELECT 1 FROM reservations
            WHERE hotel_id = ? AND room_number = ? AND id != ?
              AND status IN ('booked', 'checked_in', 'pending_payment')
              AND (status != 'pending_payment' OR hold_expires_at > ?)
              AND check_in < ? AND check_out > ? LIMIT 1""",
            (
                current_hotel_id(), reservation["room_number"], reservation_id,
                now_iso(), new_departure.isoformat(), current_departure.isoformat(),
            ),
        ).fetchone() is not None
        room = db.execute(
            "SELECT rate FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), reservation["room_number"]),
        ).fetchone()
    if has_conflict:
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("The room has another stay scheduled before that departure date.")
    if not room:
        if not SUPABASE_ENABLED:
            get_db().rollback()
        raise ValueError("The room rate could not be found.")

    extra_nights = (new_departure - current_departure).days
    extension_charge = extra_nights * int(room["rate"])
    updated_amount = int(reservation["amount"]) + extension_charge
    amount_paid = int(reservation["amount_paid"] or 0)
    payment_status = (
        "paid" if amount_paid >= updated_amount
        else "partial" if amount_paid
        else "pending"
    )
    updates = {
        "check_out": new_departure.isoformat(),
        "amount": updated_amount,
        "payment_status": payment_status,
        "status": "checked_in",
    }
    if SUPABASE_ENABLED:
        from postgrest.exceptions import APIError

        try:
            client.table("reservations").update(updates).eq(
                "hotel_id", current_hotel_id()
            ).eq("id", reservation_id).execute()
        except APIError as error:
            raise_supabase_reservation_conflict(error)
    else:
        db.execute(
            """UPDATE reservations SET check_out = ?, amount = ?,
            payment_status = ?, status = ?
            WHERE hotel_id = ? AND id = ?""",
            (
                updates["check_out"], updates["amount"],
                updates["payment_status"], updates["status"],
                current_hotel_id(), reservation_id,
            ),
        )
        db.commit()
    return extra_nights, extension_charge, new_departure


def get_manager_reservation(reservation_id):
    if SUPABASE_ENABLED:
        rows = get_request_supabase().table("reservations").select("*").eq(
            "hotel_id", current_hotel_id()
        ).eq("id", reservation_id
        ).limit(1).execute().data
        return rows[0] if rows else None
    row = get_db().execute(
        "SELECT * FROM reservations WHERE hotel_id = ? AND id = ?",
        (current_hotel_id(), reservation_id),
    ).fetchone()
    return dict(row) if row else None


def update_room_status_from_reservations(room_number):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("status").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).limit(1).execute().data
        room = rooms[0] if rooms else None
        stays = client.table("reservations").select(
            "status, check_in, check_out"
        ).eq(
            "hotel_id", current_hotel_id()
        ).eq("room_number", room_number
        ).in_("status", ["booked", "checked_in"]).execute().data
    else:
        db = get_db()
        room = db.execute(
            "SELECT status FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        ).fetchone()
        stays = db.execute(
            """SELECT status, check_in, check_out FROM reservations
            WHERE hotel_id = ? AND room_number = ?
            AND status IN ('booked', 'checked_in')""",
            (current_hotel_id(), room_number),
        ).fetchall()
    if not room:
        raise ValueError("The assigned room could not be found.")
    today = date.today()
    current_stays = [
        stay for stay in stays
        if date.fromisoformat(str(stay["check_in"])[:10]) <= today
        < date.fromisoformat(str(stay["check_out"])[:10])
    ]
    if current_stays:
        status = "occupied"
    elif room["status"] in {"booked", "occupied"}:
        status = "available"
    else:
        return
    if SUPABASE_ENABLED:
        get_request_supabase().table("rooms").update({"status": status}).eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).execute()
    else:
        get_db().execute(
            "UPDATE rooms SET status = ? WHERE hotel_id = ? AND number = ?",
            (status, current_hotel_id(), room_number),
        )


def update_manager_reservation(reservation_id, form):
    reservation = get_manager_reservation(reservation_id)
    if not reservation or reservation["status"] not in {"booked", "checked_in"}:
        raise ValueError("Only an active booking can be edited.")
    guest_name = form.get("guest_name", "").strip()
    phone = form.get("phone", "").strip()
    email = form.get("email", "").strip()
    room_number = form.get("room_number", "").strip()
    payment_method = form.get("payment_method", "")
    if not guest_name or not phone or not room_number:
        raise ValueError("Guest name, phone, and room are required.")
    if payment_method not in {"Cash", "POS", "Transfer"}:
        raise ValueError("Choose a valid payment method.")
    try:
        check_in = date.fromisoformat(form["check_in"])
        check_out = date.fromisoformat(form["check_out"])
        amount = int(form["amount"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("Enter valid stay dates and booking amount.") from error
    if check_out <= check_in:
        raise ValueError("Departure must be after arrival.")
    if amount < 0:
        raise ValueError("Booking amount cannot be negative.")
    amount_paid = int(reservation.get("amount_paid") or 0)
    if amount < amount_paid:
        raise ValueError("Booking amount cannot be less than the amount already paid.")

    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("number, status").eq(
            "hotel_id", current_hotel_id()
        ).eq("number", room_number
        ).limit(1).execute().data
        other_stays = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("hotel_id", current_hotel_id()).eq("room_number", room_number).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
    else:
        db = get_db()
        rooms = db.execute(
            "SELECT number, status FROM rooms WHERE hotel_id = ? AND number = ?",
            (current_hotel_id(), room_number),
        ).fetchall()
        other_stays = db.execute(
            """SELECT id, check_in, check_out, status, hold_expires_at
            FROM reservations WHERE hotel_id = ? AND room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')""",
            (current_hotel_id(), room_number),
        ).fetchall()
    room = rooms[0] if rooms else None
    if not room:
        raise ValueError("Choose a registered room.")
    if room["status"] in {"unavailable", "cleaning"} and room_number != reservation["room_number"]:
        raise ValueError("Choose a room that is not unavailable or being cleaned.")
    for stay in other_stays:
        if str(stay["id"]) == str(reservation_id):
            continue
        if (
            stay["status"] == "pending_payment"
            and not timestamp_is_future(stay["hold_expires_at"])
        ):
            continue
        other_start = date.fromisoformat(stay["check_in"])
        other_end = date.fromisoformat(stay["check_out"])
        if check_in < other_end and check_out > other_start:
            raise ValueError("That room already has a booking during the selected dates.")

    payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
    updates = {
        "guest_name": guest_name,
        "email": email,
        "phone": phone,
        "room_number": room_number,
        "check_in": check_in.isoformat(),
        "check_out": check_out.isoformat(),
        "amount": amount,
        "payment_method": payment_method,
        "payment_status": payment_status,
    }
    if SUPABASE_ENABLED:
        from postgrest.exceptions import APIError

        try:
            client.table("reservations").update(updates).eq(
                "hotel_id", current_hotel_id()
            ).eq("id", reservation_id
            ).execute()
        except APIError as error:
            raise_supabase_reservation_conflict(error)
    else:
        db.execute(
            """UPDATE reservations SET guest_name = ?, email = ?, phone = ?,
            room_number = ?, check_in = ?, check_out = ?, amount = ?,
            payment_method = ?, payment_status = ? WHERE hotel_id = ? AND id = ?""",
            (
                guest_name, email, phone, room_number, check_in.isoformat(),
                check_out.isoformat(), amount, payment_method, payment_status,
                current_hotel_id(), reservation_id,
            ),
        )
    if room_number != reservation["room_number"]:
        update_room_status_from_reservations(reservation["room_number"])
    update_room_status_from_reservations(room_number)
    if not SUPABASE_ENABLED:
        get_db().commit()


def cancel_manager_reservation(reservation_id):
    reservation = get_manager_reservation(reservation_id)
    if not reservation or reservation["status"] not in {"booked", "checked_in"}:
        raise ValueError("Only an active booking can be cancelled.")
    if SUPABASE_ENABLED:
        get_request_supabase().table("reservations").update(
            {"status": "cancelled"}
        ).eq("hotel_id", current_hotel_id()).eq("id", reservation_id).execute()
    else:
        get_db().execute(
            "UPDATE reservations SET status = 'cancelled' WHERE hotel_id = ? AND id = ?",
            (current_hotel_id(), reservation_id),
        )
    update_room_status_from_reservations(reservation["room_number"])
    if not SUPABASE_ENABLED:
        get_db().commit()


@app.route("/workspace/<role>/<page>", methods=["GET", "POST"])
def reference_workspace(role, page):
    if role == "reception" and page == "checkin":
        return redirect(url_for("reference_workspace", role=role, page="checkout"))
    pages = {
        "director": {"dashboard", "rooms", "finance"},
        "manager": {"dashboard", "rooms", "bookings", "calendar", "finance", "online-settings"},
        "reception": {"dashboard", "calendar", "new", "checkout", "roomstatus", "payments", "online"},
    }
    if role not in pages or page not in pages[role]:
        return redirect(url_for("home"))
    expire_online_booking_holds()
    reference_date = date.today()
    if page == "calendar":
        try:
            reference_date = date.fromisoformat(
                request.args.get("reference_date", reference_date.isoformat())
            )
        except ValueError:
            flash("Choose a valid calendar date.", "error")
    if request.method == "POST":
        if role == "manager" and page == "rooms":
            try:
                create_reference_room(request.form)
                flash(f"Room {request.form['number'].strip()} registered.", "success")
                return redirect(url_for("reference_workspace", role=role, page=page))
            except (KeyError, ValueError) as error:
                flash(str(error) or "Complete all room details.", "error")
        elif role == "manager" and page == "online-settings":
            try:
                action = request.form.get("action")
                if action == "settings":
                    save_online_booking_settings(request.form)
                    flash("Online payment and Reception contact details saved.", "success")
                elif action == "listing":
                    room_number = request.form.get("room_number", "").strip()
                    save_online_room_listing(room_number, request.form)
                    flash(f"Online room listing for {room_number} saved.", "success")
                else:
                    raise ValueError("Choose a valid online booking setting.")
                return redirect(url_for(
                    "reference_workspace", role=role, page=page
                ))
            except ValueError as error:
                flash(str(error), "error")
        elif role != "reception" or page != "new":
            return redirect(url_for("reference_workspace", role=role, page=page))
        else:
            try:
                create_reference_booking(request.form)
                flash(f"Booking created for {request.form['guest_name']}.", "success")
                return redirect(url_for("reference_workspace", role=role, page="calendar"))
            except (KeyError, ValueError) as error:
                flash(str(error) or "Complete all booking details.", "error")
    reservations = reference_reservations()
    payments = reference_payments()
    rooms = reference_rooms()
    room_history_numbers = (
        rooms_with_history(rooms) if role == "manager" and page == "rooms" else set()
    )
    online_listings = (
        online_room_listings(manager=True)
        if role == "manager" and page == "online-settings" else []
    )
    booking_settings = (
        online_booking_settings()
        if role == "manager" and page == "online-settings" else {}
    )
    available_rooms = [room for room in rooms if room["status"].lower() == "available"]
    calendar_days, calendar_rows = reference_calendar(rooms, reservations, reference_date)
    calendar_week_start = reference_date - timedelta(days=reference_date.weekday())
    return render_template(
        "reference_workspace.html",
        role=role,
        page=page,
        rooms=rooms,
        room_metrics=reference_room_metrics(),
        payment_records=payments,
        bookings=reference_bookings(reservations, rooms),
        booking_rooms=rooms,
        reservations=reservations,
        available_rooms=available_rooms,
        finance=reference_finance(reservations, payments),
        calendar_days=calendar_days,
        calendar_rows=calendar_rows,
        reference_date=reference_date,
        previous_calendar_date=(calendar_week_start - timedelta(days=7)).isoformat(),
        next_calendar_date=(calendar_week_start + timedelta(days=7)).isoformat(),
        room_rates={room["number"]: room["rate"] for room in rooms},
        rooms_with_history=room_history_numbers,
        online_listings=online_listings,
        booking_settings=booking_settings,
        pending_online_bookings=(
            pending_online_bookings()
            if role == "reception" and page == "online" else []
        ),
    )


@app.route("/dashboard")
def dashboard():
    role = request.args.get("role", "reception")
    if role not in {"director", "manager", "reception"}:
        role = "reception"
    rooms, stats = dashboard_stats()
    return render_template("dashboard.html", role=role, rooms=rooms, stats=stats)


@app.route("/reservations")
def reservations():
    role = request.args.get("role", "reception")
    rows = get_db().execute(
        "SELECT * FROM reservations WHERE hotel_id = ? ORDER BY check_in ASC, id DESC",
        (current_hotel_id(),),
    ).fetchall()
    return render_template("reservations.html", reservations=rows, role=role)


@app.route("/reservations/new", methods=["GET", "POST"])
def new_reservation():
    role = request.args.get("role", "reception")
    db = get_db()
    rooms = db.execute(
        """SELECT * FROM rooms WHERE hotel_id = ?
        AND lower(status) NOT IN ('unavailable', 'cleaning') ORDER BY number""",
        (current_hotel_id(),),
    ).fetchall()
    if request.method == "POST":
        try:
            create_reference_booking(request.form)
            flash(f"Reservation created for {request.form['guest_name']}.", "success")
            return redirect(url_for("reservations", role=role))
        except (KeyError, ValueError) as error:
            flash(str(error) or "Please complete all reservation details.", "error")
    return render_template("reservation_form.html", role=role, rooms=rooms)


@app.post("/reservations/<reservation_id>/status")
def update_reservation(reservation_id):
    action = request.form["action"]
    role = request.form.get("role", "reception")
    if action in {"manager_edit", "manager_cancel"}:
        if role != "manager":
            return redirect(url_for("home"))
        try:
            if action == "manager_edit":
                update_manager_reservation(reservation_id, request.form)
                flash("Booking details updated.", "success")
            else:
                cancel_manager_reservation(reservation_id)
                flash("Booking cancelled. Payment records have been retained.", "success")
        except (KeyError, ValueError) as error:
            flash(str(error) or "Check the booking details and try again.", "error")
        return redirect(url_for("reference_workspace", role="manager", page="bookings"))
    if role != "reception" or action not in {"check_out", "mark_paid", "extend"}:
        return redirect(url_for("home"))
    if action == "extend":
        try:
            extra_nights, extension_charge, new_departure = extend_reference_reservation(
                reservation_id, request.form
            )
            flash(
                f"Stay extended by {extra_nights} night(s) through {new_departure.isoformat()}. "
                f"Additional charge: ₦{extension_charge:,.0f}.",
                "success",
            )
        except (KeyError, ValueError) as error:
            flash(str(error) or "Enter a valid new departure date.", "error")
        return redirect(url_for("reference_workspace", role="reception", page="checkout"))
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        reservations = client.table("reservations").select("*").eq(
            "hotel_id", current_hotel_id()
        ).eq("id", reservation_id).limit(1).execute().data
        reservation = reservations[0] if reservations else None
        if reservation:
            if action == "check_out" and reservation["status"] in {"booked", "checked_in"}:
                client.table("reservations").update({"status": "checked_out"}).eq(
                    "hotel_id", current_hotel_id()
                ).eq("id", reservation_id).execute()
                client.table("rooms").update({"status": "cleaning"}).eq(
                    "hotel_id", current_hotel_id()
                ).eq("number", reservation["room_number"]).execute()
            elif action == "mark_paid":
                if reservation["status"] == "cancelled":
                    flash("Cancelled bookings cannot receive additional payments.", "error")
                    return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "payments")))
                balance = reservation["amount"] - reservation.get("amount_paid", 0)
                amount = int(request.form.get("amount", balance))
                if amount < 1 or amount > balance:
                    flash("Enter a payment amount within the outstanding balance.", "error")
                    return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "payments")))
                new_paid = reservation.get("amount_paid", 0) + amount
                client.table("reservations").update({
                    "amount_paid": new_paid,
                    "payment_status": "paid" if new_paid == reservation["amount"] else "partial",
                }).eq("hotel_id", current_hotel_id()).eq("id", reservation_id).execute()
                client.table("payments").insert({
                    "hotel_id": current_hotel_id(),
                    "reservation_id": reservation_id,
                    "room_number": reservation["room_number"],
                    "amount": amount,
                    "balance": reservation["amount"] - new_paid,
                    "method": request.form.get("payment_method", reservation["payment_method"]),
                    "received_by": session.get("username", "Reception"),
                }).execute()
        if request.form.get("reference") == "true":
            return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "dashboard")))
        return redirect(url_for("reservations", role=role))

    db = get_db()
    reservation = db.execute(
        "SELECT * FROM reservations WHERE hotel_id = ? AND id = ?",
        (current_hotel_id(), reservation_id),
    ).fetchone()
    if reservation:
        if action == "check_out" and reservation["status"] in {"booked", "checked_in"}:
            db.execute(
                "UPDATE reservations SET status = 'checked_out' WHERE hotel_id = ? AND id = ?",
                (current_hotel_id(), reservation_id),
            )
            db.execute(
                "UPDATE rooms SET status = 'cleaning' WHERE hotel_id = ? AND number = ?",
                (current_hotel_id(), reservation["room_number"]),
            )
        elif action == "mark_paid":
            if reservation["status"] == "cancelled":
                flash("Cancelled bookings cannot receive additional payments.", "error")
                return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "payments")))
            balance = reservation["amount"] - reservation["amount_paid"]
            amount = int(request.form.get("amount", balance))
            if amount < 1 or amount > balance:
                flash("Enter a payment amount within the outstanding balance.", "error")
                return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "payments")))
            new_paid = reservation["amount_paid"] + amount
            db.execute(
                """UPDATE reservations SET amount_paid = ?, payment_status = ?
                WHERE hotel_id = ? AND id = ?""",
                (new_paid, "paid" if new_paid == reservation["amount"] else "partial",
                 current_hotel_id(), reservation_id),
            )
            db.execute(
                """INSERT INTO payments
                (hotel_id, reservation_id, room_number, amount, balance, method, received_by, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (current_hotel_id(), reservation_id, reservation["room_number"], amount, reservation["amount"] - new_paid,
                 request.form.get("payment_method", reservation["payment_method"]), session.get("username", "Reception"),
                 datetime.now().isoformat(timespec="seconds")),
            )
        db.commit()
        flash("Reservation updated.", "success")
    if request.form.get("reference") == "true":
        return redirect(url_for("reference_workspace", role="reception", page=request.form.get("return_page", "dashboard")))
    return redirect(url_for("reservations", role=role))


@app.post("/rooms/<room_number>/status")
def update_room(room_number):
    status = request.form["status"]
    if status in {"available", "booked", "occupied", "cleaning", "unavailable"}:
        if SUPABASE_ENABLED:
            get_request_supabase().table("rooms").update({
                "status": status, "updated_at": datetime.now().isoformat()
            }).eq("hotel_id", current_hotel_id()).eq("number", room_number).execute()
        else:
            db = get_db()
            db.execute(
                "UPDATE rooms SET status = ? WHERE hotel_id = ? AND number = ?",
                (status, current_hotel_id(), room_number),
            )
            db.commit()
        flash(f"Room {room_number} marked {status}.", "success")
    if request.form.get("reference") == "true":
        return redirect(url_for("reference_workspace", role="reception", page="roomstatus"))
    return redirect(url_for("dashboard", role=request.form.get("role", "reception")))


@app.post("/rooms/<room_number>/manage")
def manage_room(room_number):
    action = request.form.get("action")
    try:
        if action == "edit":
            update_reference_room(room_number, request.form)
            flash(f"Room {room_number} details updated.", "success")
        elif action == "remove":
            removed = remove_reference_room(room_number)
            if removed:
                flash(f"Room {room_number} removed.", "success")
            else:
                flash(
                    f"Room {room_number} has booking or payment history, so it was marked unavailable instead of deleted.",
                    "error",
                )
        else:
            raise ValueError("Choose a valid room action.")
    except (KeyError, ValueError) as error:
        flash(str(error) or "Check the room details and try again.", "error")
    return redirect(url_for("reference_workspace", role="manager", page="rooms"))


with app.app_context():
    init_db()


if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_DEBUG", "false").lower() == "true", port=int(os.getenv("PORT", "5000")), host="0.0.0.0")
