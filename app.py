from datetime import date, datetime
from functools import lru_cache
import os
from pathlib import Path
import sqlite3

from dotenv import load_dotenv
from flask import Flask, flash, g, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

try:
    from supabase import create_client
except ImportError:
    create_client = None

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

app = Flask(__name__)
app.config["SECRET_KEY"] = FLASK_SECRET_KEY or "local-development-key-change-before-deploy"
app.config["DATABASE"] = DATABASE


@lru_cache(maxsize=1)
def get_supabase_admin():
    if not SUPABASE_ENABLED:
        return None
    return create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)


def get_supabase_auth():
    if not SUPABASE_ENABLED:
        return None
    return create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

ROOMS = [
    ("101", "Standard", 1, 45000, "available"),
    ("102", "Standard", 1, 45000, "occupied"),
    ("103", "Deluxe", 2, 60000, "booked"),
    ("104", "Deluxe", 2, 60000, "cleaning"),
    ("105", "Suite", 3, 85000, "available"),
    ("106", "Standard", 1, 45000, "unavailable"),
    ("201", "Standard", 1, 45000, "occupied"),
    ("202", "Deluxe", 2, 60000, "available"),
    ("203", "Suite", 3, 85000, "booked"),
    ("204", "Standard", 1, 45000, "cleaning"),
    ("205", "Standard", 1, 45000, "available"),
    ("206", "Deluxe", 2, 60000, "occupied"),
]

REFERENCE_ROOMS = [
    {"number": "101", "type": "Standard", "rate": 45000, "status": "Available", "guest": ""},
    {"number": "102", "type": "Standard", "rate": 45000, "status": "Occupied", "guest": "Mr Ade"},
    {"number": "103", "type": "Deluxe", "rate": 60000, "status": "Booked", "guest": "Mrs Bello"},
    {"number": "104", "type": "Deluxe", "rate": 60000, "status": "Cleaning", "guest": ""},
    {"number": "105", "type": "Suite", "rate": 85000, "status": "Available", "guest": ""},
    {"number": "106", "type": "Standard", "rate": 45000, "status": "Unavailable", "guest": ""},
    {"number": "201", "type": "Standard", "rate": 45000, "status": "Occupied", "guest": "Mr James"},
    {"number": "202", "type": "Deluxe", "rate": 60000, "status": "Available", "guest": ""},
    {"number": "203", "type": "Suite", "rate": 85000, "status": "Booked", "guest": "Ms Grace"},
    {"number": "204", "type": "Standard", "rate": 45000, "status": "Cleaning", "guest": ""},
    {"number": "205", "type": "Standard", "rate": 45000, "status": "Available", "guest": ""},
    {"number": "206", "type": "Deluxe", "rate": 60000, "status": "Occupied", "guest": "Mr Tunde"},
]

PAYMENT_RECORDS = [
    ("102", "Transfer", 90000, 0, "Mary", "2026-09-02"),
    ("103", "POS", 120000, 18000, "James", "2026-09-03"),
    ("201", "Cash", 45000, 0, "Mary", "2026-09-05"),
    ("204", "Transfer", 170000, 0, "Mary", "2026-09-10"),
    ("206", "POS", 120000, 20000, "James", "2026-09-12"),
    ("302", "Transfer", 180000, 0, "Mary", "2026-09-18"),
    ("305", "Transfer", 120000, 18500, "James", "2026-09-21"),
]

REFERENCE_BOOKINGS = [
    ("102", "Mr Ade", "Occupied", 90000, 90000, 0, "Transfer"),
    ("103", "Mrs Bello", "Booked", 120000, 50000, 70000, "POS"),
    ("203", "Ms Grace", "Booked", 170000, 170000, 0, "Transfer"),
    ("206", "Mr Tunde", "Occupied", 60000, 30000, 30000, "POS"),
]


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
        """
    )
    if db.execute("SELECT COUNT(*) FROM rooms").fetchone()[0] == 0:
        db.executemany("INSERT INTO rooms VALUES (?, ?, ?, ?, ?)", ROOMS)
    if db.execute("SELECT COUNT(*) FROM reservations").fetchone()[0] == 0:
        db.execute(
            """INSERT INTO reservations
            (guest_name, email, phone, room_number, check_in, check_out, amount,
             payment_method, payment_status, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            ("Amara Okafor", "amara@example.com", "+234 803 555 0121", "301",
             "2026-10-02", "2026-10-05", 555, "Card", "paid", "booked",
             datetime.now().isoformat(timespec="seconds")),
        )
    for number, name, beds, rate, status in ROOMS:
        db.execute(
            "INSERT OR IGNORE INTO rooms (number, name, beds, rate, status) VALUES (?, ?, ?, ?, ?)",
            (number, name, beds, rate, status),
        )
        db.execute("UPDATE rooms SET name = ?, beds = ?, rate = ? WHERE number = ?", (name, beds, rate, number))
    db.commit()


def reference_rooms():
    guest_by_room = {room["number"]: room["guest"] for room in REFERENCE_ROOMS}
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


def dashboard_stats():
    db = get_db()
    rooms = db.execute("SELECT * FROM rooms ORDER BY number").fetchall()
    reservation_count = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE status != 'checked_out'"
    ).fetchone()[0]
    revenue = db.execute(
        "SELECT COALESCE(SUM(amount), 0) FROM reservations WHERE payment_status = 'paid'"
    ).fetchone()[0]
    pending = db.execute(
        "SELECT COUNT(*) FROM reservations WHERE payment_status = 'pending'"
    ).fetchone()[0]
    return rooms, {"reservations": reservation_count, "revenue": revenue, "pending": pending}


@app.context_processor
def inject_globals():
    return {"today": date.today().isoformat(), "active_role": request.args.get("role", "reception")}


@app.route("/")
def home():
    return render_template("landing.html")


@app.get("/health")
def health():
    return {"status": "ok"}, 200


@app.route("/login/<role>", methods=["GET", "POST"])
def login(role):
    if role not in {"director", "manager", "reception"}:
        return redirect(url_for("home"))
    if request.method == "POST":
        user = get_db().execute(
            "SELECT * FROM users WHERE role = ? AND username = ?",
            (role, request.form.get("username", "").strip()),
        ).fetchone()
        submitted_password = request.form.get("password", "")
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
    account_exists = get_db().execute("SELECT 1 FROM users WHERE role = ?", (role,)).fetchone() is not None
    return render_template("login.html", role=role, account_exists=account_exists)


@app.route("/signup/manager", methods=["GET", "POST"])
def manager_signup():
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
    accounts = get_db().execute("SELECT role, username FROM users ORDER BY role").fetchall()
    account_map = {account["role"]: account["username"] for account in accounts}
    return render_template("manager_signup.html", account_map=account_map, editing=bool(account_map))


@app.route("/workspace/<role>/<page>")
def reference_workspace(role, page):
    pages = {
        "director": {"dashboard", "rooms", "finance"},
        "manager": {"dashboard", "rooms", "bookings", "finance"},
        "reception": {"dashboard", "calendar", "new", "checkin", "checkout", "roomstatus", "payments"},
    }
    if role not in pages or page not in pages[role]:
        return redirect(url_for("home"))
    return render_template(
        "reference_workspace.html",
        role=role,
        page=page,
        rooms=reference_rooms(),
        room_metrics=reference_room_metrics(),
        payment_records=PAYMENT_RECORDS,
        bookings=REFERENCE_BOOKINGS,
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


@app.post("/reservations/<int:reservation_id>/status")
def update_reservation(reservation_id):
    action = request.form["action"]
    role = request.form.get("role", "reception")
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
            db.execute("UPDATE reservations SET payment_status = 'paid' WHERE id = ?", (reservation_id,))
        db.commit()
        flash("Reservation updated.", "success")
    return redirect(url_for("reservations", role=role))


@app.post("/rooms/<room_number>/status")
def update_room(room_number):
    status = request.form["status"]
    if status in {"available", "booked", "occupied", "cleaning", "unavailable"}:
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
