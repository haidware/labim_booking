from datetime import date, datetime, timedelta
from functools import lru_cache
import os
from pathlib import Path
import sqlite3

from dotenv import load_dotenv
from flask import Flask, flash, g, redirect, render_template, request, session, url_for
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
            status TEXT NOT NULL DEFAULT 'booked',
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
        """
    )
    reservation_columns = {column[1] for column in db.execute("PRAGMA table_info(reservations)")}
    if "amount_paid" not in reservation_columns:
        db.execute("ALTER TABLE reservations ADD COLUMN amount_paid INTEGER NOT NULL DEFAULT 0")
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
        return [
            {
                "number": row["number"],
                "type": row["name"],
                "rate": row["rate"],
                "status": row["status"].capitalize(),
                "guest": guest_by_room.get(row["number"], ""),
            }
            for row in rows
        ]
    guest_by_room = {}
    booking_guests = get_db().execute(
        "SELECT room_number, guest_name FROM reservations WHERE status IN ('booked', 'checked_in') ORDER BY created_at"
    ).fetchall()
    guest_by_room.update({row["room_number"]: row["guest_name"] for row in booking_guests})
    rows = get_db().execute("SELECT number, name, rate, status FROM rooms ORDER BY number").fetchall()
    return [
        {
            "number": row["number"],
            "type": row["name"],
            "rate": row["rate"],
            "status": row["status"].capitalize(),
            "guest": guest_by_room.get(row["number"], ""),
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
    reservations = []
    for row in rows:
        reservation = dict(row)
        reservation["amount_paid"] = reservation["amount"] if reservation["payment_status"] == "paid" else 0
        reservations.append(reservation)
    return reservations


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


def reference_bookings(reservations):
    return [
        (
            row["room_number"],
            row["guest_name"],
            row["status"].replace("_", " ").capitalize(),
            row["amount"],
            row.get("amount_paid", 0),
            row["amount"] - row.get("amount_paid", 0),
            row["payment_method"],
        )
        for row in reservations
    ]


def reference_finance(reservations, payments):
    active = [row for row in reservations if row["status"] != "checked_out"]
    total = sum(row["amount"] for row in active)
    paid = sum(row.get("amount_paid", 0) for row in active)
    return {
        "booking_value": total,
        "collected": paid,
        "outstanding": total - paid,
        "stay_records": len(reservations),
    }


def reference_calendar(rooms, reservations):
    start = date.today()
    days = [start + timedelta(days=offset) for offset in range(7)]
    rows = []
    for room in rooms:
        cells = []
        for current_day in days:
            booking = next((
                reservation for reservation in reservations
                if reservation["room_number"] == room["number"]
                and reservation["status"] != "checked_out"
                and reservation["check_in"] <= current_day.isoformat() < reservation["check_out"]
            ), None)
            cells.append({
                "status": "occupied" if booking and booking["status"] == "checked_in" else "booked" if booking else "",
                "guest": booking["guest_name"] if booking else "",
            })
        rows.append({"room": room["number"], "cells": cells})
    return [f"{day.strftime('%b')} {day.day}" for day in days], rows


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
        existing = client.table("rooms").select("number").eq("number", number).maybe_single().execute().data
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


def dashboard_stats():
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        rooms = client.table("rooms").select("*").order("number").execute().data
        reservations = client.table("reservations").select(
            "amount_paid, payment_status, status, check_in, check_out"
        ).execute().data
        today = date.today().isoformat()
        reservation_count = sum(row["status"] != "checked_out" for row in reservations)
        revenue = sum(row["amount_paid"] for row in reservations)
        pending = sum(row["payment_status"] == "pending" for row in reservations)
        occupied = sum(room["status"] == "occupied" for room in rooms)
        occupancy = round(occupied * 100 / len(rooms)) if rooms else 0
        check_ins = sum(row["status"] == "booked" and row["check_in"] == today for row in reservations)
        check_outs = sum(row["status"] == "checked_in" and row["check_out"] == today for row in reservations)
        return rooms, {
            "reservations": reservation_count,
            "revenue": revenue,
            "pending": pending,
            "occupancy": occupancy,
            "check_ins": check_ins,
            "check_outs": check_outs,
        }
    db = get_db()
    rooms = db.execute("SELECT * FROM rooms ORDER BY number").fetchall()
    reservation_count = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status != 'checked_out'"
    ).fetchone()[0]
    revenue = db.execute(
        "SELECT COALESCE(SUM(amount_paid), 0) FROM reservations"
    ).fetchone()[0]
    pending = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE payment_status = 'pending'"
    ).fetchone()[0]
    occupied = sum(room["status"] == "occupied" for room in rooms)
    occupancy = round(occupied * 100 / len(rooms)) if rooms else 0
    today = date.today().isoformat()
    check_ins = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status = 'booked' AND check_in = ?", (today,)
    ).fetchone()[0]
    check_outs = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status = 'checked_in' AND check_out = ?", (today,)
    ).fetchone()[0]
    return rooms, {
        "reservations": reservation_count,
        "revenue": revenue,
        "pending": pending,
        "occupancy": occupancy,
        "check_ins": check_ins,
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
    elif endpoint in {"update_room"}:
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
                profile = client.table("profiles").select("username, role").eq("id", user.id).maybe_single().execute().data
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
        room = client.table("rooms").select("rate, status").eq("number", room_number).maybe_single().execute().data
        if not room or room["status"] != "available":
            raise ValueError("That room is no longer available.")
        amount = int(form.get("total_amount") or nights * room["rate"])
        amount_paid = int(form.get("amount_paid") or 0)
        if amount < 0 or amount_paid < 0 or amount_paid > amount:
            raise ValueError("Check the booking amount and amount paid.")
        payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
        result = client.table("reservations").insert({
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
            "status": "booked",
            "created_by": session.get("supabase_user_id"),
        }).select("*").single().execute().data
        client.table("rooms").update({"status": "booked"}).eq("number", room_number).execute()
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
    room = db.execute("SELECT rate, status FROM rooms WHERE number = ?", (room_number,)).fetchone()
    if not room or room["status"] != "available":
        raise ValueError("That room is no longer available.")
    amount = int(form.get("total_amount") or nights * room["rate"])
    amount_paid = int(form.get("amount_paid") or 0)
    if amount < 0 or amount_paid < 0 or amount_paid > amount:
        raise ValueError("Check the booking amount and amount paid.")
    payment_status = "paid" if amount_paid == amount else "partial" if amount_paid else "pending"
    cursor = db.execute(
        """INSERT INTO reservations
        (guest_name, email, phone, room_number, check_in, check_out, amount, amount_paid,
         payment_method, payment_status, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'booked', ?)""",
        (guest_name, form.get("email", "").strip(), phone, room_number, check_in.isoformat(),
         check_out.isoformat(), amount, amount_paid, payment_method, payment_status,
         datetime.now().isoformat(timespec="seconds")),
    )
    db.execute("UPDATE rooms SET status = 'booked' WHERE number = ?", (room_number,))
    if amount_paid:
        db.execute(
            "INSERT INTO payments (reservation_id, room_number, amount, balance, method, received_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (cursor.lastrowid, room_number, amount_paid, amount - amount_paid, payment_method,
             session.get("username", "Reception"), datetime.now().isoformat(timespec="seconds")),
        )
    db.commit()
    return {"id": cursor.lastrowid}


@app.route("/workspace/<role>/<page>", methods=["GET", "POST"])
def reference_workspace(role, page):
    pages = {
        "director": {"dashboard", "rooms", "finance"},
        "manager": {"dashboard", "rooms", "bookings", "finance"},
        "reception": {"dashboard", "calendar", "new", "checkin", "checkout", "roomstatus", "payments"},
    }
    if role not in pages or page not in pages[role]:
        return redirect(url_for("home"))
    if request.method == "POST":
        if role == "manager" and page == "rooms":
            try:
                create_reference_room(request.form)
                flash(f"Room {request.form['number'].strip()} registered.", "success")
                return redirect(url_for("reference_workspace", role=role, page=page))
            except (KeyError, ValueError) as error:
                flash(str(error) or "Complete all room details.", "error")
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
    available_rooms = [room for room in rooms if room["status"].lower() == "available"]
    calendar_days, calendar_rows = reference_calendar(rooms, reservations)
    return render_template(
        "reference_workspace.html",
        role=role,
        page=page,
        rooms=rooms,
        room_metrics=reference_room_metrics(),
        payment_records=payments,
        bookings=reference_bookings(reservations),
        reservations=reservations,
        available_rooms=available_rooms,
        finance=reference_finance(reservations, payments),
        calendar_days=calendar_days,
        calendar_rows=calendar_rows,
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
    rooms = db.execute("SELECT * FROM rooms WHERE status != 'cleaning' ORDER BY number").fetchall()
    if request.method == "POST":
        form = request.form
        try:
            check_in = datetime.strptime(form["check_in"], "%Y-%m-%d")
            check_out = datetime.strptime(form["check_out"], "%Y-%m-%d")
            nights = (check_out - check_in).days
            if nights < 1:
                raise ValueError("Check-out must be after check-in.")
            room = db.execute("SELECT rate FROM rooms WHERE number = ?", (form["room_number"],)).fetchone()
            if room is None:
                raise ValueError("Choose a valid room.")
            amount = nights * room["rate"]
            db.execute(
                """INSERT INTO reservations
                (guest_name, email, phone, room_number, check_in, check_out, amount,
                 payment_method, payment_status, status, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'booked', ?)""",
                (form["guest_name"], form["email"], form["phone"], form["room_number"],
                 form["check_in"], form["check_out"], amount, form["payment_method"],
                 datetime.now().isoformat(timespec="seconds")),
            )
            db.execute("UPDATE rooms SET status = 'booked' WHERE number = ?", (form["room_number"],))
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
    if SUPABASE_ENABLED:
        client = get_request_supabase()
        reservation = client.table("reservations").select("*").eq("id", reservation_id).maybe_single().execute().data
        if reservation:
            if action == "check_in":
                client.table("reservations").update({"status": "checked_in"}).eq("id", reservation_id).execute()
                client.table("rooms").update({"status": "occupied"}).eq("number", reservation["room_number"]).execute()
            elif action == "check_out":
                client.table("reservations").update({"status": "checked_out"}).eq("id", reservation_id).execute()
                client.table("rooms").update({"status": "cleaning"}).eq("number", reservation["room_number"]).execute()
            elif action == "mark_paid":
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
        if action == "check_in":
            db.execute("UPDATE reservations SET status = 'checked_in' WHERE id = ?", (reservation_id,))
            db.execute("UPDATE rooms SET status = 'occupied' WHERE number = ?", (reservation["room_number"],))
        elif action == "check_out":
            db.execute("UPDATE reservations SET status = 'checked_out' WHERE id = ?", (reservation_id,))
            db.execute("UPDATE rooms SET status = 'cleaning' WHERE number = ?", (reservation["room_number"],))
        elif action == "mark_paid":
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


with app.app_context():
    init_db()


if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_DEBUG", "false").lower() == "true", port=int(os.getenv("PORT", "5000")), host="0.0.0.0")
