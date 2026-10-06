from datetime import date, datetime, timedelta
from functools import lru_cache
import hmac
import os
from pathlib import Path
import re
import secrets
import sqlite3
from urllib.parse import urlencode
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
MAX_ROOM_PHOTO_BYTES = 5 * 1024 * 1024
ALLOWED_ROOM_PHOTO_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
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
app.config["MAX_CONTENT_LENGTH"] = MAX_ROOM_PHOTO_BYTES + 1024 * 1024


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
        CREATE TABLE IF NOT EXISTS rooms (
            number TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            beds INTEGER NOT NULL,
            rate INTEGER NOT NULL,
            status TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reservations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            role TEXT NOT NULL UNIQUE,
            username TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            room_number TEXT PRIMARY KEY,
            description TEXT NOT NULL DEFAULT '',
            photo_path TEXT NOT NULL DEFAULT '',
            enabled INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS online_booking_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            bank_name TEXT NOT NULL DEFAULT '',
            account_name TEXT NOT NULL DEFAULT '',
            account_number TEXT NOT NULL DEFAULT '',
            reception_whatsapp TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL
        );
        INSERT OR IGNORE INTO online_booking_settings (id, updated_at)
        VALUES (1, CURRENT_TIMESTAMP);
        """
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
            WHERE guest_name = 'Amara Okafor' AND email = 'amara@example.com'
              AND phone = '+234 803 555 0121' AND room_number = '301'
              AND check_in = '2026-10-02' AND check_out = '2026-10-05'
              AND amount = 555 AND payment_method = 'Card'"""
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
                AND NOT EXISTS (SELECT 1 FROM reservations WHERE room_number = ?)
                AND NOT EXISTS (SELECT 1 FROM payments WHERE room_number = ?)""",
                (number, name, beds, rate, number, number),
            )
        db.execute("INSERT INTO app_migrations (name) VALUES ('remove_seeded_demo_data')")
    db.commit()


def reference_rooms():
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rows = client.table("rooms").select("*").order("number").execute().data
        bookings = client.table("reservations").select("room_number, guest_name, status").in_("status", ["booked", "checked_in"]).execute().data
        guest_by_room = {booking["room_number"]: booking["guest_name"] for booking in bookings}
        active_room_numbers = {booking["room_number"] for booking in bookings}
        return [
            {
                "number": row["number"],
                "type": row["name"],
                "beds": row["beds"],
                "rate": row["rate"],
                "status": row["status"].capitalize(),
                "guest": guest_by_room.get(row["number"], ""),
                "active_booking": row["number"] in active_room_numbers,
            }
            for row in rows
        ]
    guest_by_room = {}
    booking_guests = get_db().execute(
        "SELECT room_number, guest_name FROM reservations WHERE status IN ('booked', 'checked_in') ORDER BY created_at"
    ).fetchall()
    guest_by_room.update({row["room_number"]: row["guest_name"] for row in booking_guests})
    active_room_numbers = {row["room_number"] for row in booking_guests}
    rows = get_db().execute(
        "SELECT number, name, beds, rate, status FROM rooms ORDER BY number"
    ).fetchall()
    return [
        {
            "number": row["number"],
            "type": row["name"],
            "beds": row["beds"],
            "rate": row["rate"],
            "status": row["status"].capitalize(),
            "guest": guest_by_room.get(row["number"], ""),
            "active_booking": row["number"] in active_room_numbers,
        }
        for row in rows
    ]


def reference_room_metrics():
    if SUPABASE_ENABLED:
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
    counts = get_db().execute(
        "SELECT status, COUNT(*) AS total FROM rooms GROUP BY status"
    ).fetchall()
    values = {row["status"]: row["total"] for row in counts}
    return [
        ("Total Rooms", sum(values.values())),
        ("Available", values.get("available", 0)),
        ("Booked", values.get("booked", 0)),
        ("Occupied", values.get("occupied", 0)),
        ("Cleaning", values.get("cleaning", 0)),
    ]


def reference_reservations():
    if SUPABASE_ENABLED:
        return get_request_supabase().table("reservations").select("*").order("check_in").execute().data
    rows = get_db().execute("SELECT * FROM reservations ORDER BY check_in, id DESC").fetchall()
    return [dict(row) for row in rows]


def reference_payments():
    if SUPABASE_ENABLED:
        rows = get_request_supabase().table("payments").select("*").order("created_at", desc=True).execute().data
        return [
            (row["room_number"], row["method"], row["amount"], row["balance"], row["received_by"], row["created_at"][:10])
            for row in rows
        ]
    rows = get_db().execute(
        "SELECT room_number, method, amount, balance, received_by, created_at FROM payments ORDER BY id DESC"
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


def online_booking_settings(public=False):
    if SUPABASE_ENABLED:
        client = get_supabase_admin() if public else get_request_supabase()
        rows = client.table("online_booking_settings").select("*").eq(
            "id", True
        ).limit(1).execute().data
        return rows[0] if rows else {}
    row = get_db().execute(
        "SELECT * FROM online_booking_settings WHERE id = 1"
    ).fetchone()
    return dict(row) if row else {}


def online_room_listings(manager=False):
    if SUPABASE_ENABLED:
        client = get_request_supabase() if manager else get_supabase_admin()
        room_rows = client.table("rooms").select("*").order("number").execute().data
        query = client.table("online_room_listings").select("*")
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
        rooms = reference_rooms()
        query = "SELECT * FROM online_room_listings"
        if not manager:
            query += " WHERE enabled = 1"
        listings = [
            dict(row) for row in get_db().execute(query).fetchall()
        ]
    listing_by_room = {item["room_number"]: item for item in listings}
    result = []
    for room in rooms:
        listing = listing_by_room.get(room["number"])
        if manager:
            result.append({
                **room,
                "description": listing["description"] if listing else "",
                "photo_path": listing["photo_path"] if listing else "",
                "enabled": bool(listing and listing["enabled"]),
                "photo_url": online_photo_url(
                    listing["photo_path"] if listing else ""
                ),
            })
        elif listing:
            result.append({**room, **listing})
    return result


def online_photo_url(photo_path):
    if not photo_path:
        return ""
    if SUPABASE_ENABLED:
        return get_supabase_admin().storage.from_(ROOM_PHOTO_BUCKET).get_public_url(
            photo_path
        )
    return url_for("online_room_photo", photo_path=photo_path)


def available_online_rooms(check_in, check_out):
    expire_online_booking_holds()
    listings = online_room_listings()
    available = []
    for room in listings:
        if room["status"].lower() in {"unavailable", "cleaning"}:
            continue
        if SUPABASE_ENABLED:
            stays = get_supabase_admin().table("reservations").select(
                "id, check_in, check_out, status, hold_expires_at"
            ).eq("room_number", room["number"]).in_(
                "status", ["booked", "checked_in", "pending_payment"]
            ).execute().data
        else:
            stays = [
                dict(row) for row in get_db().execute(
                    """SELECT id, check_in, check_out, status, hold_expires_at
                    FROM reservations WHERE room_number = ?
                    AND status IN ('booked', 'checked_in', 'pending_payment')""",
                    (room["number"],),
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
            room["photo_url"] = online_photo_url(room.get("photo_path", ""))
            available.append(room)
    return available


def save_online_booking_settings(form):
    bank_name = form.get("bank_name", "").strip()
    account_name = form.get("account_name", "").strip()
    account_number = re.sub(r"\s", "", form.get("account_number", ""))
    whatsapp = form.get("reception_whatsapp", "").strip()
    whatsapp_digits = re.sub(r"\D", "", whatsapp)
    if not bank_name or not account_name:
        raise ValueError("Enter the bank and account holder name.")
    if not re.fullmatch(r"\d{6,20}", account_number):
        raise ValueError("Enter a valid bank account number.")
    if not 8 <= len(whatsapp_digits) <= 15 or whatsapp_digits.startswith("0"):
        raise ValueError("Enter the Reception WhatsApp number with its country code.")
    settings = {
        "bank_name": bank_name[:100],
        "account_name": account_name[:120],
        "account_number": account_number,
        "reception_whatsapp": "+" + whatsapp_digits,
        "updated_at": now_iso(),
    }
    if SUPABASE_ENABLED:
        get_request_supabase().table("online_booking_settings").upsert({
            "id": True,
            **settings,
        }).execute()
    else:
        get_db().execute(
            """UPDATE online_booking_settings SET bank_name = ?, account_name = ?,
            account_number = ?, reception_whatsapp = ?, updated_at = ? WHERE id = 1""",
            (
                settings["bank_name"], settings["account_name"],
                settings["account_number"], settings["reception_whatsapp"],
                settings["updated_at"],
            ),
        )
        get_db().commit()


def save_online_room_listing(room_number, form):
    if SUPABASE_ENABLED:
        room = get_request_supabase().table("rooms").select("number").eq(
            "number", room_number
        ).limit(1).execute().data
    else:
        room = get_db().execute(
            "SELECT number FROM rooms WHERE number = ?", (room_number,)
        ).fetchone()
    if not room:
        raise ValueError("Room not found.")
    description = form.get("description", "").strip()
    if len(description) > 1200:
        raise ValueError("Room description must be 1,200 characters or fewer.")
    enabled = form.get("enabled") == "on"
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        old = client.table("online_room_listings").select("photo_path").eq(
            "room_number", room_number
        ).limit(1).execute().data
        if enabled and (not old or not old[0].get("photo_path")):
            raise ValueError("Upload a room photo before publishing this room.")
        client.table("online_room_listings").upsert({
            "room_number": room_number,
            "description": description,
            "enabled": enabled,
            "updated_at": now_iso(),
        }).execute()
    else:
        db = get_db()
        old = db.execute(
            "SELECT photo_path FROM online_room_listings WHERE room_number = ?",
            (room_number,),
        ).fetchone()
        if enabled and (not old or not old["photo_path"]):
            raise ValueError("Upload a room photo before publishing this room.")
        db.execute(
            """INSERT INTO online_room_listings
            (room_number, description, enabled, updated_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(room_number) DO UPDATE SET description = excluded.description,
            enabled = excluded.enabled, updated_at = excluded.updated_at""",
            (room_number, description, int(enabled), now_iso()),
        )
        db.commit()


def save_room_photo(room_number, uploaded_file):
    if not uploaded_file or not uploaded_file.filename:
        raise ValueError("Choose a room photo to upload.")
    safe_name = secure_filename(uploaded_file.filename)
    extension = Path(safe_name).suffix.lower()
    if extension not in ALLOWED_ROOM_PHOTO_EXTENSIONS:
        raise ValueError("Use a JPG, PNG, or WebP room photo.")
    content = uploaded_file.stream.read(MAX_ROOM_PHOTO_BYTES + 1)
    if not content or len(content) > MAX_ROOM_PHOTO_BYTES:
        raise ValueError("Room photos must be between 1 byte and 5 MB.")
    expected_types = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }
    if uploaded_file.mimetype != expected_types[extension]:
        raise ValueError("The selected photo's file type does not match its extension.")
    valid_signature = (
        extension in {".jpg", ".jpeg"} and content.startswith(b"\xff\xd8\xff")
        or extension == ".png" and content.startswith(b"\x89PNG\r\n\x1a\n")
        or extension == ".webp" and content.startswith(b"RIFF")
        and content[8:12] == b"WEBP"
    )
    if not valid_signature:
        raise ValueError("The selected file is not a valid JPG, PNG, or WebP image.")
    if SUPABASE_ENABLED:
        admin = get_supabase_admin()
        room = admin.table("rooms").select("number").eq(
            "number", room_number
        ).limit(1).execute().data
        if not room:
            raise ValueError("Room not found.")
        existing = admin.table("online_room_listings").select(
            "photo_path, description, enabled"
        ).eq(
            "room_number", room_number
        ).limit(1).execute().data
        photo_path = f"{uuid4().hex}{extension}"
        admin.storage.from_(ROOM_PHOTO_BUCKET).upload(
            photo_path,
            content,
            {"content-type": expected_types[extension], "upsert": "true"},
        )
        admin.table("online_room_listings").upsert({
            "room_number": room_number,
            "photo_path": photo_path,
            "description": existing[0]["description"] if existing else "",
            "enabled": existing[0]["enabled"] if existing else False,
            "updated_at": now_iso(),
        }).execute()
        if existing and existing[0].get("photo_path"):
            admin.storage.from_(ROOM_PHOTO_BUCKET).remove(
                [existing[0]["photo_path"]]
            )
        return

    db = get_db()
    room = db.execute(
        "SELECT number FROM rooms WHERE number = ?", (room_number,)
    ).fetchone()
    if not room:
        raise ValueError("Room not found.")
    ROOM_PHOTO_DIRECTORY.mkdir(parents=True, exist_ok=True)
    photo_path = f"{uuid4().hex}{extension}"
    destination = ROOM_PHOTO_DIRECTORY / photo_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(content)
    existing = db.execute(
        "SELECT description, enabled, photo_path FROM online_room_listings WHERE room_number = ?",
        (room_number,),
    ).fetchone()
    db.execute(
        """INSERT INTO online_room_listings
        (room_number, description, photo_path, enabled, updated_at)
        VALUES (?, ?, ?, ?, ?) ON CONFLICT(room_number) DO UPDATE SET
        photo_path = excluded.photo_path, updated_at = excluded.updated_at""",
        (
            room_number,
            existing["description"] if existing else "",
            photo_path,
            existing["enabled"] if existing else 0,
            now_iso(),
        ),
    )
    db.commit()
    if existing and existing["photo_path"]:
        previous = ROOM_PHOTO_DIRECTORY / existing["photo_path"]
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
    if not guest_name or len(guest_name) > 160 or not phone or len(phone) > 40:
        raise ValueError("Enter a guest name and valid phone number.")
    if len(email) > 254 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise ValueError("Enter a valid email address.")
    if form.get("website", "").strip():
        raise ValueError("Booking could not be submitted.")

    settings = online_booking_settings(public=True)
    if not all(settings.get(key) for key in (
        "bank_name", "account_name", "account_number", "reception_whatsapp"
    )):
        raise ValueError("Online booking is not available yet. Please contact the hotel.")
    available = available_online_rooms(check_in, check_out)
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
                "p_guest_name": guest_name,
                "p_email": email,
                "p_phone": phone,
                "p_room_number": room_number,
                "p_check_in": check_in.isoformat(),
                "p_check_out": check_out.isoformat(),
            }).execute().data
        except APIError as error:
            if error.code == "P0001" and (
                error.message
                and "already has a booking" in error.message
            ):
                raise ValueError(
                    "That room was just booked for the selected dates."
                ) from error
            raise
        reservation_id = result[0] if isinstance(result, list) else result
    else:
        db = get_db()
        db.execute("BEGIN IMMEDIATE")
        overlap = db.execute(
            """SELECT 1 FROM reservations WHERE room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')
            AND check_in < ? AND check_out > ?
            AND (status != 'pending_payment' OR hold_expires_at > ?)
            LIMIT 1""",
            (room_number, check_out.isoformat(), check_in.isoformat(), now_iso()),
        ).fetchone()
        if overlap:
            db.rollback()
            raise ValueError("That room was just booked for the selected dates.")
        cursor = db.execute(
            """INSERT INTO reservations
            (guest_name, email, phone, room_number, check_in, check_out, amount,
             amount_paid, payment_method, payment_status, status, created_at,
             booking_source, hold_expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, 'Transfer', 'pending',
                    'pending_payment', ?, 'online', ?)""",
            (
                guest_name, email, phone, room_number, check_in.isoformat(),
                check_out.isoformat(), (check_out - check_in).days * room["rate"],
                now_iso(), hold_expires_at,
            ),
        )
        reservation_id = cursor.lastrowid
        db.commit()
    message = (
        f"Hello, I submitted online booking request {reservation_id} for "
        f"{guest_name}, room {room_number}, {check_in.isoformat()} to "
        f"{check_out.isoformat()}. I am sending the bank transfer for "
        f"NGN {(check_out - check_in).days * room['rate']:,.0f}. "
        "Please confirm once received."
    )
    wa_number = re.sub(r"\D", "", settings["reception_whatsapp"])
    session["online_booking_confirmation"] = {
        "reference": str(reservation_id),
        "room_number": room_number,
        "room_type": room["type"],
        "check_in": check_in.isoformat(),
        "check_out": check_out.isoformat(),
        "amount": (check_out - check_in).days * room["rate"],
        "bank_name": settings["bank_name"],
        "account_name": settings["account_name"],
        "account_number": settings["account_number"],
        "hold_expires_at": hold_expires_at,
        "whatsapp_url": f"https://wa.me/{wa_number}?{urlencode({'text': message})}",
    }
    return reservation_id


def confirm_online_booking(reservation_id, received_by):
    if SUPABASE_ENABLED:
        confirmed = get_request_supabase().rpc("confirm_online_booking", {
            "p_reservation_id": reservation_id,
            "p_received_by": received_by[:120],
        }).execute().data
        if not confirmed:
            raise ValueError("This online request expired or is no longer awaiting confirmation.")
        return
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    reservation = db.execute(
        "SELECT * FROM reservations WHERE id = ? AND status = 'pending_payment'",
        (reservation_id,),
    ).fetchone()
    if not reservation:
        db.rollback()
        raise ValueError("This online request is no longer awaiting confirmation.")
    if not reservation["hold_expires_at"] or reservation["hold_expires_at"] <= now_iso():
        db.execute(
            "UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL WHERE id = ?",
            (reservation_id,),
        )
        db.commit()
        raise ValueError("The 30-minute room hold expired. Ask the guest to submit a new request.")
    db.execute(
        """UPDATE reservations SET status = 'booked', amount_paid = amount,
        payment_status = 'paid', hold_expires_at = NULL WHERE id = ?""",
        (reservation_id,),
    )
    if reservation["amount"] > 0:
        db.execute(
            """INSERT INTO payments
            (reservation_id, room_number, amount, balance, method, received_by, created_at)
            VALUES (?, ?, ?, 0, 'Transfer', ?, ?)""",
            (
                reservation_id, reservation["room_number"], reservation["amount"],
                received_by[:120], now_iso(),
            ),
        )
    db.commit()


def pending_online_bookings():
    now = now_iso()
    if SUPABASE_ENABLED:
        return get_request_supabase().table("reservations").select("*").eq(
            "booking_source", "online"
        ).eq("status", "pending_payment").gt(
            "hold_expires_at", now
        ).order("created_at").execute().data
    return [
        dict(row) for row in get_db().execute(
            """SELECT * FROM reservations WHERE booking_source = 'online'
            AND status = 'pending_payment' AND hold_expires_at > ?
            ORDER BY created_at""",
            (now,),
        ).fetchall()
    ]


def reference_calendar(rooms, reservations, reference_date=None):
    reference_date = reference_date or date.today()
    start = reference_date - timedelta(days=reference_date.weekday())
    days = [start + timedelta(days=offset) for offset in range(7)]
    rows = []
    for room in rooms:
        cells = []
        for current_day in days:
            booking = next((
                reservation for reservation in reservations
                if reservation["room_number"] == room["number"]
                and reservation["status"] in {"booked", "checked_in", "pending_payment"}
                and (
                    reservation["status"] != "pending_payment"
                    or reservation.get("hold_expires_at")
                    and reservation["hold_expires_at"] > now_iso()
                )
                and reservation["check_in"] <= current_day.isoformat() < reservation["check_out"]
            ), None)
            cells.append({
                "status": (
                    "pending-payment" if booking and booking["status"] == "pending_payment"
                    else "occupied" if booking and booking["status"] == "checked_in"
                    else "booked" if booking else ""
                ),
                "guest": booking["guest_name"] if booking else "",
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
        existing = client.table("rooms").select("number").eq("number", number).limit(1).execute().data
        if existing:
            raise ValueError("A room with that number is already registered.")
        client.table("rooms").insert({
            "number": number,
            "name": name,
            "beds": beds,
            "rate": rate,
            "status": "available",
        }).execute()
        return

    db = get_db()
    existing = db.execute("SELECT 1 FROM rooms WHERE number = ?", (number,)).fetchone()
    if existing:
        raise ValueError("A room with that number is already registered.")
    db.execute(
        "INSERT INTO rooms (number, name, beds, rate, status) VALUES (?, ?, ?, ?, 'available')",
        (number, name, beds, rate),
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
            "number", room_number
        ).limit(1).execute().data
        if not existing:
            raise ValueError("Room not found.")
        client.table("rooms").update({
            "name": name,
            "beds": beds,
            "rate": rate,
            "updated_at": datetime.now().isoformat(),
        }).eq("number", room_number).execute()
        return

    db = get_db()
    existing = db.execute("SELECT 1 FROM rooms WHERE number = ?", (room_number,)).fetchone()
    if not existing:
        raise ValueError("Room not found.")
    db.execute(
        "UPDATE rooms SET name = ?, beds = ?, rate = ? WHERE number = ?",
        (name, beds, rate, room_number),
    )
    db.commit()


def room_has_history(room_number):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        reservations = client.table("reservations").select("id").eq(
            "room_number", room_number
        ).limit(1).execute().data
        payments = client.table("payments").select("id").eq(
            "room_number", room_number
        ).limit(1).execute().data
        return bool(reservations or payments)
    db = get_db()
    reservation = db.execute(
        "SELECT 1 FROM reservations WHERE room_number = ? LIMIT 1", (room_number,)
    ).fetchone()
    payment = db.execute(
        "SELECT 1 FROM payments WHERE room_number = ? LIMIT 1", (room_number,)
    ).fetchone()
    return bool(reservation or payment)


def room_has_active_booking(room_number):
    if SUPABASE_ENABLED:
        bookings = get_request_supabase().table("reservations").select(
            "status, hold_expires_at"
        ).eq(
            "room_number", room_number
        ).in_("status", ["booked", "checked_in", "pending_payment"]).execute().data
    else:
        bookings = [
            dict(row) for row in get_db().execute(
                "SELECT status, hold_expires_at FROM reservations WHERE room_number = ? "
                "AND status IN ('booked', 'checked_in', 'pending_payment')",
                (room_number,),
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
            "number", room_number
        ).limit(1).execute().data
        if not existing:
            raise ValueError("Room not found.")
    else:
        db = get_db()
        existing = db.execute(
            "SELECT 1 FROM rooms WHERE number = ?", (room_number,)
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
            }).eq("number", room_number).execute()
        else:
            db.execute(
                "UPDATE rooms SET status = 'unavailable' WHERE number = ?",
                (room_number,),
            )
            db.commit()
        return False

    if SUPABASE_ENABLED:
        listings = get_request_supabase().table("online_room_listings").select(
            "photo_path"
        ).eq("room_number", room_number).limit(1).execute().data
        if listings:
            photo_path = listings[0].get("photo_path")
            if photo_path:
                get_supabase_admin().storage.from_(ROOM_PHOTO_BUCKET).remove(
                    [photo_path]
                )
            get_request_supabase().table("online_room_listings").delete().eq(
                "room_number", room_number
            ).execute()
        get_request_supabase().table("rooms").delete().eq(
            "number", room_number
        ).execute()
    else:
        listing = db.execute(
            "SELECT photo_path FROM online_room_listings WHERE room_number = ?",
            (room_number,),
        ).fetchone()
        if listing:
            photo_path = listing["photo_path"]
            if photo_path and re.fullmatch(
                r"[a-f0-9]{32}\.(?:jpg|jpeg|png|webp)", photo_path
            ):
                photo = ROOM_PHOTO_DIRECTORY / photo_path
                if photo.is_file():
                    photo.unlink()
            db.execute(
                "DELETE FROM online_room_listings WHERE room_number = ?",
                (room_number,),
            )
        db.execute("DELETE FROM rooms WHERE number = ?", (room_number,))
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
        rooms = client.table("rooms").select("*").order("number").execute().data
        reservations = client.table("reservations").select(
            "amount_paid, payment_status, status, check_in, check_out"
        ).execute().data
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
    rooms = db.execute("SELECT * FROM rooms ORDER BY number").fetchall()
    reservation_count = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status NOT IN ('checked_out', 'cancelled')"
    ).fetchone()[0]
    revenue = db.execute(
        "SELECT COALESCE(SUM(amount_paid), 0) FROM reservations"
    ).fetchone()[0]
    pending = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE payment_status = 'pending' AND status != 'cancelled'"
    ).fetchone()[0]
    occupied = sum(room["status"] == "occupied" for room in rooms)
    occupancy = round(occupied * 100 / len(rooms)) if rooms else 0
    today = date.today().isoformat()
    arrivals_today = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE check_in = ? AND status != 'cancelled'", (today,)
    ).fetchone()[0]
    check_outs = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status IN ('booked', 'checked_in') AND check_out = ?", (today,)
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
    return {"today": date.today().isoformat(), "active_role": request.args.get("role", "reception")}


@app.errorhandler(SupabaseSessionExpired)
def handle_supabase_session_expired(error):
    flash("Your session has expired. Please sign in again.", "error")
    return redirect(url_for("login", role=error.role))


@app.before_request
def require_workspace_login():
    endpoint = request.endpoint
    if endpoint in {"home", "health", "login", "manager_signup", "logout", "static"}:
        return None
    if endpoint == "reference_workspace":
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
    if required_role and session.get("user_role") != required_role:
        return redirect(url_for("login", role=required_role))
    return None


@app.route("/book", methods=["GET", "POST"])
def public_booking():
    today = date.today()
    default_check_in = today + timedelta(days=1)
    default_check_out = default_check_in + timedelta(days=1)
    try:
        submitted_dates = request.form if request.method == "POST" else request.args
        check_in = date.fromisoformat(submitted_dates.get(
            "check_in", default_check_in.isoformat()
        ))
        check_out = date.fromisoformat(submitted_dates.get(
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
                create_online_booking(request.form)
                return redirect(url_for("online_booking_confirmation"))
            except ValueError as error:
                flash(str(error), "error")
    session.setdefault("public_booking_csrf", secrets.token_urlsafe(32))

    rooms = []
    if check_in >= today and check_out > check_in:
        rooms = available_online_rooms(check_in, check_out)
    return render_template(
        "public_booking.html",
        rooms=rooms,
        check_in=check_in.isoformat(),
        check_out=check_out.isoformat(),
        today=today.isoformat(),
        csrf_token=session["public_booking_csrf"],
    )


@app.get("/booking/confirmation")
def online_booking_confirmation():
    confirmation = session.get("online_booking_confirmation")
    if not confirmation:
        return redirect(url_for("public_booking"))
    return render_template("online_booking_confirmation.html", confirmation=confirmation)


@app.get("/room-photos/<path:photo_path>")
def online_room_photo(photo_path):
    if SUPABASE_ENABLED or not re.fullmatch(r"[a-f0-9]{32}\.(?:jpg|jpeg|png|webp)", photo_path):
        return "", 404
    return send_from_directory(ROOM_PHOTO_DIRECTORY, photo_path)


@app.post("/rooms/<room_number>/online")
def manage_online_room(room_number):
    try:
        save_room_photo(room_number, request.files.get("photo"))
        flash(f"Room photo for {room_number} uploaded.", "success")
    except ValueError as error:
        flash(str(error), "error")
    return redirect(url_for(
        "reference_workspace", role="manager", page="online-settings"
    ))


@app.post("/online-bookings/<reservation_id>/confirm")
def confirm_online_booking_route(reservation_id):
    try:
        confirm_online_booking(reservation_id, session.get("username", "Reception"))
        flash(f"Online booking {reservation_id} confirmed and payment recorded.", "success")
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
            "status", "pending_payment"
        ).select("id").execute().data
        if not result:
            flash("This request has expired or is no longer awaiting payment.", "error")
            return redirect(url_for(
                "reference_workspace", role="reception", page="online"
            ))
    else:
        result = get_db().execute(
            """UPDATE reservations SET status = 'cancelled', hold_expires_at = NULL
            WHERE id = ? AND status = 'pending_payment'""",
            (reservation_id,),
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
                profiles = client.table("profiles").select("username, role").eq("id", user.id).limit(1).execute().data
                profile = profiles[0] if profiles else None
                if not profile or profile["role"] != role:
                    client.auth.sign_out()
                    raise ValueError("Role does not match this login.")
                session.clear()
                session["user_role"] = profile["role"]
                session["username"] = profile["username"]
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
            return redirect(url_for("reference_workspace", role=role, page="dashboard"))
        return render_template("login.html", role=role, account_exists=True, error="Invalid login details.")
    if SUPABASE_ENABLED:
        account_exists = bool(
            get_supabase_admin().table("profiles").select("id").eq("role", role).limit(1).execute().data
        )
    else:
        account_exists = get_db().execute("SELECT 1 FROM users WHERE role = ?", (role,)).fetchone() is not None
    return render_template("login.html", role=role, account_exists=account_exists)


@app.route("/signup/manager", methods=["GET", "POST"])
def manager_signup():
    if SUPABASE_ENABLED:
        supabase_admin = get_supabase_admin()
        existing_profiles = supabase_admin.table("profiles").select("id, role, username").execute().data
        has_accounts = bool(existing_profiles)
    else:
        supabase_admin = None
        existing_profiles = []
        has_accounts = get_db().execute("SELECT 1 FROM users LIMIT 1").fetchone() is not None
    if has_accounts and session.get("user_role") != "manager":
        return redirect(url_for("login", role="manager"))
    if request.method == "POST":
        fields = {
            "director": (request.form.get("director_username", "").strip(), request.form.get("director_password", "")),
            "reception": (request.form.get("reception_username", "").strip(), request.form.get("reception_password", "")),
        }
        if not has_accounts:
            fields["manager"] = (request.form.get("manager_username", "").strip(), request.form.get("manager_password", ""))
        if any(not username or not password for username, password in fields.values()):
            return render_template("manager_signup.html", error="Complete all three role accounts.")
        if SUPABASE_ENABLED:
            try:
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
                                "app_metadata": {"role": account_role},
                                "user_metadata": {"username": username},
                            },
                        )
                        supabase_admin.table("profiles").update({"username": username}).eq("id", user_id).execute()
                    else:
                        created_user = supabase_admin.auth.admin.create_user(
                            {
                                "email": email,
                                "password": password,
                                "email_confirm": True,
                                "app_metadata": {"role": account_role},
                                "user_metadata": {"username": username},
                            }
                        ).user
                        supabase_admin.table("profiles").insert(
                            {
                                "id": created_user.id,
                                "role": account_role,
                                "username": username,
                                "created_by": session.get("supabase_user_id"),
                            }
                        ).execute()
                return redirect(url_for("login", role="manager"))
            except Exception:
                return render_template("manager_signup.html", error="Could not save the workspace accounts. Check usernames and try again.")
        db = get_db()
        try:
            existing = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            if existing:
                db.executemany(
                    "UPDATE users SET username = ?, password = ? WHERE role = ?",
                    [(username, generate_password_hash(password), role) for role, (username, password) in fields.items()],
                )
            else:
                db.executemany(
                    "INSERT INTO users (role, username, password, created_at) VALUES (?, ?, ?, ?)",
                    [(role, username, generate_password_hash(password), datetime.now().isoformat(timespec="seconds")) for role, (username, password) in fields.items()],
                )
            db.commit()
        except sqlite3.IntegrityError:
            db.rollback()
            return render_template("manager_signup.html", error="An account or username already exists.")
        return redirect(url_for("login", role="manager"))
    if SUPABASE_ENABLED:
        account_map = {profile["role"]: profile["username"] for profile in existing_profiles}
    else:
        accounts = get_db().execute("SELECT role, username FROM users ORDER BY role").fetchall()
        account_map = {account["role"]: account["username"] for account in accounts}
    return render_template("manager_signup.html", account_map=account_map, editing=bool(account_map))


def create_reference_booking(form):
    check_in = datetime.strptime(form["check_in"], "%Y-%m-%d").date()
    check_out = datetime.strptime(form["check_out"], "%Y-%m-%d").date()
    nights = (check_out - check_in).days
    if nights < 1:
        raise ValueError("Check-out must be after check-in.")
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
        rooms = client.table("rooms").select("rate, status").eq("number", room_number).limit(1).execute().data
        room = rooms[0] if rooms else None
        if not room or room["status"] != "available":
            raise ValueError("That room is no longer available.")
        occupied_dates = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("room_number", room_number).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
    else:
        db = get_db()
        room = db.execute(
            "SELECT rate, status FROM rooms WHERE number = ?", (room_number,)
        ).fetchone()
        if not room or room["status"] != "available":
            raise ValueError("That room is no longer available.")
        occupied_dates = db.execute(
            """SELECT id, check_in, check_out, status, hold_expires_at
            FROM reservations WHERE room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')""",
            (room_number,),
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
        raise ValueError("That room already has a booking during the selected dates.")

    if SUPABASE_ENABLED:
        amount = int(form.get("total_amount") or nights * room["rate"])
        amount_paid = int(form.get("amount_paid") or 0)
        if amount < 0 or amount_paid < 0 or amount_paid > amount:
            raise ValueError("Check the booking amount and amount paid.")
        payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
        results = client.table("reservations").insert({
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
            "status": "checked_in",
            "created_by": session.get("supabase_user_id"),
        }).select("*").execute().data
        if not results:
            raise RuntimeError("Supabase did not return the created booking.")
        result = results[0]
        client.table("rooms").update({"status": "occupied"}).eq("number", room_number).execute()
        if amount_paid:
            client.table("payments").insert({
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
        raise ValueError("Check the booking amount and amount paid.")
    payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
    cursor = db.execute(
        """INSERT INTO reservations
        (guest_name, email, phone, room_number, check_in, check_out, amount, amount_paid,
         payment_method, payment_status, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'checked_in', ?)""",
        (guest_name, form.get("email", "").strip(), phone, room_number, check_in.isoformat(),
         check_out.isoformat(), amount, amount_paid, payment_method, payment_status,
         datetime.now().isoformat(timespec="seconds")),
    )
    db.execute("UPDATE rooms SET status = 'occupied' WHERE number = ?", (room_number,))
    if amount_paid:
        db.execute(
            "INSERT INTO payments (reservation_id, room_number, amount, balance, method, received_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (cursor.lastrowid, room_number, amount_paid, amount - amount_paid, payment_method,
             session.get("username", "Reception"), datetime.now().isoformat(timespec="seconds")),
        )
    db.commit()
    return {"id": cursor.lastrowid}


def extend_reference_reservation(reservation_id, form):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        results = client.table("reservations").select("*").eq("id", reservation_id).limit(1).execute().data
        reservation = results[0] if results else None
    else:
        reservation = get_db().execute(
            "SELECT * FROM reservations WHERE id = ?", (reservation_id,)
        ).fetchone()
    if not reservation or reservation["status"] not in {"booked", "checked_in"}:
        raise ValueError("Only a current stay can be extended.")

    try:
        current_departure = date.fromisoformat(reservation["check_out"])
        new_departure = date.fromisoformat(form["check_out"])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("Choose a valid new departure date.") from error
    if new_departure <= current_departure:
        raise ValueError("The new departure date must be after the current departure.")

    if SUPABASE_ENABLED:
        client = get_request_supabase()
        other_stays = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("room_number", reservation["room_number"]).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
        has_conflict = any(
            stay["id"] != reservation_id
            and (
                stay["status"] != "pending_payment"
                or timestamp_is_future(stay["hold_expires_at"])
            )
            and date.fromisoformat(stay["check_in"]) < new_departure
            and date.fromisoformat(stay["check_out"]) > current_departure
            for stay in other_stays
        )
        room_results = client.table("rooms").select("rate").eq(
            "number", reservation["room_number"]
        ).limit(1).execute().data
        room = room_results[0] if room_results else None
    else:
        db = get_db()
        has_conflict = db.execute(
            """SELECT 1 FROM reservations
            WHERE room_number = ? AND id != ?
              AND status IN ('booked', 'checked_in', 'pending_payment')
              AND (status != 'pending_payment' OR hold_expires_at > ?)
              AND check_in < ? AND check_out > ? LIMIT 1""",
            (
                reservation["room_number"],
                reservation_id,
                now_iso(),
                new_departure.isoformat(),
                current_departure.isoformat(),
            ),
        ).fetchone() is not None
        room = db.execute(
            "SELECT rate FROM rooms WHERE number = ?", (reservation["room_number"],)
        ).fetchone()
    if has_conflict:
        raise ValueError("The room has another stay scheduled before that departure date.")
    if not room:
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
        client.table("reservations").update(updates).eq("id", reservation_id).execute()
        client.table("rooms").update({"status": "occupied"}).eq(
            "number", reservation["room_number"]
        ).execute()
    else:
        db.execute(
            """UPDATE reservations SET check_out = ?, amount = ?, payment_status = ?, status = ?
            WHERE id = ?""",
            (
                updates["check_out"], updates["amount"], updates["payment_status"],
                updates["status"], reservation_id,
            ),
        )
        db.execute(
            "UPDATE rooms SET status = 'occupied' WHERE number = ?",
            (reservation["room_number"],),
        )
        db.commit()
    return extra_nights, extension_charge, new_departure


def get_manager_reservation(reservation_id):
    if SUPABASE_ENABLED:
        rows = get_request_supabase().table("reservations").select("*").eq(
            "id", reservation_id
        ).limit(1).execute().data
        return rows[0] if rows else None
    row = get_db().execute(
        "SELECT * FROM reservations WHERE id = ?", (reservation_id,)
    ).fetchone()
    return dict(row) if row else None


def update_room_status_from_reservations(room_number):
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("status").eq(
            "number", room_number
        ).limit(1).execute().data
        room = rooms[0] if rooms else None
        stays = client.table("reservations").select("status").eq(
            "room_number", room_number
        ).in_("status", ["booked", "checked_in"]).execute().data
    else:
        db = get_db()
        room = db.execute(
            "SELECT status FROM rooms WHERE number = ?", (room_number,)
        ).fetchone()
        stays = db.execute(
            "SELECT status FROM reservations WHERE room_number = ? AND status IN ('booked', 'checked_in')",
            (room_number,),
        ).fetchall()
    if not room:
        raise ValueError("The assigned room could not be found.")
    if any(stay["status"] == "checked_in" for stay in stays):
        status = "occupied"
    elif stays:
        status = "booked"
    elif room["status"] in {"booked", "occupied"}:
        status = "available"
    else:
        return
    if SUPABASE_ENABLED:
        get_request_supabase().table("rooms").update({"status": status}).eq(
            "number", room_number
        ).execute()
    else:
        get_db().execute(
            "UPDATE rooms SET status = ? WHERE number = ?", (status, room_number)
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
            "number", room_number
        ).limit(1).execute().data
        other_stays = client.table("reservations").select(
            "id, check_in, check_out, status, hold_expires_at"
        ).eq("room_number", room_number).in_(
            "status", ["booked", "checked_in", "pending_payment"]
        ).execute().data
    else:
        db = get_db()
        rooms = db.execute(
            "SELECT number, status FROM rooms WHERE number = ?", (room_number,)
        ).fetchall()
        other_stays = db.execute(
            """SELECT id, check_in, check_out, status, hold_expires_at
            FROM reservations WHERE room_number = ?
            AND status IN ('booked', 'checked_in', 'pending_payment')""",
            (room_number,),
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
        client.table("reservations").update(updates).eq(
            "id", reservation_id
        ).execute()
    else:
        db.execute(
            """UPDATE reservations SET guest_name = ?, email = ?, phone = ?,
            room_number = ?, check_in = ?, check_out = ?, amount = ?,
            payment_method = ?, payment_status = ? WHERE id = ?""",
            (
                guest_name, email, phone, room_number, check_in.isoformat(),
                check_out.isoformat(), amount, payment_method, payment_status,
                reservation_id,
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
        ).eq("id", reservation_id).execute()
    else:
        get_db().execute(
            "UPDATE reservations SET status = 'cancelled' WHERE id = ?",
            (reservation_id,),
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
                    flash("Online payment and WhatsApp details saved.", "success")
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
        "SELECT * FROM reservations ORDER BY check_in ASC, id DESC"
    ).fetchall()
    return render_template("reservations.html", reservations=rows, role=role)


@app.route("/reservations/new", methods=["GET", "POST"])
def new_reservation():
    role = request.args.get("role", "reception")
    db = get_db()
    rooms = db.execute("SELECT * FROM rooms WHERE status = 'available' ORDER BY number").fetchall()
    if request.method == "POST":
        form = request.form
        try:
            check_in = datetime.strptime(form["check_in"], "%Y-%m-%d")
            check_out = datetime.strptime(form["check_out"], "%Y-%m-%d")
            nights = (check_out - check_in).days
            if nights < 1:
                raise ValueError("Check-out must be after check-in.")
            room = db.execute(
                "SELECT rate FROM rooms WHERE number = ? AND status = 'available'",
                (form["room_number"],),
            ).fetchone()
            if room is None:
                raise ValueError("Choose an available room.")
            amount = nights * room["rate"]
            db.execute(
                """INSERT INTO reservations
                (guest_name, email, phone, room_number, check_in, check_out, amount,
                 payment_method, payment_status, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'checked_in', ?)""",
                (form["guest_name"], form["email"], form["phone"], form["room_number"],
                 form["check_in"], form["check_out"], amount, form["payment_method"],
                 datetime.now().isoformat(timespec="seconds")),
            )
            db.execute("UPDATE rooms SET status = 'occupied' WHERE number = ?", (form["room_number"],))
            db.commit()
            flash(f"Reservation created for {form['guest_name']}.", "success")
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
        reservations = client.table("reservations").select("*").eq("id", reservation_id).limit(1).execute().data
        reservation = reservations[0] if reservations else None
        if reservation:
            if action == "check_out" and reservation["status"] in {"booked", "checked_in"}:
                client.table("reservations").update({"status": "checked_out"}).eq("id", reservation_id).execute()
                client.table("rooms").update({"status": "cleaning"}).eq("number", reservation["room_number"]).execute()
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
                }).eq("id", reservation_id).execute()
                client.table("payments").insert({
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
    reservation = db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,)).fetchone()
    if reservation:
        if action == "check_out" and reservation["status"] in {"booked", "checked_in"}:
            db.execute("UPDATE reservations SET status = 'checked_out' WHERE id = ?", (reservation_id,))
            db.execute("UPDATE rooms SET status = 'cleaning' WHERE number = ?", (reservation["room_number"],))
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
                "UPDATE reservations SET amount_paid = ?, payment_status = ? WHERE id = ?",
                (new_paid, "paid" if new_paid == reservation["amount"] else "partial", reservation_id),
            )
            db.execute(
                "INSERT INTO payments (reservation_id, room_number, amount, balance, method, received_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (reservation_id, reservation["room_number"], amount, reservation["amount"] - new_paid,
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
            get_request_supabase().table("rooms").update({"status": status, "updated_at": datetime.now().isoformat()}).eq("number", room_number).execute()
        else:
            db = get_db()
            db.execute("UPDATE rooms SET status = ? WHERE number = ?", (status, room_number))
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
