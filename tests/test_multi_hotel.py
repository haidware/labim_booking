import importlib.util
from io import BytesIO
import sqlite3
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from datetime import date, timedelta
from pathlib import Path


class MultiHotelFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp_directory = tempfile.TemporaryDirectory()
        cls.app_directory = Path(cls.temp_directory.name)
        source_directory = Path(__file__).resolve().parents[1]
        shutil.copy2(source_directory / "app.py", cls.app_directory / "app.py")
        shutil.copytree(source_directory / "templates", cls.app_directory / "templates")
        shutil.copytree(source_directory / "static", cls.app_directory / "static")
        sys.path.insert(0, str(cls.app_directory))
        spec = importlib.util.spec_from_file_location(
            "multi_hotel_test_app", cls.app_directory / "app.py"
        )
        cls.app_module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.app_module
        spec.loader.exec_module(cls.app_module)
        cls.app_module.SUPABASE_ENABLED = False
        cls.app_module.app.config.update(TESTING=True)

    @classmethod
    def tearDownClass(cls):
        sys.modules.pop("multi_hotel_test_app", None)
        sys.path.remove(str(cls.app_directory))
        cls.temp_directory.cleanup()

    def register_hotel(
        self, client, name, username_suffix, address, city, state
    ):
        response = client.post("/signup/manager", data={
            "hotel_name": name,
            "hotel_address": address,
            "hotel_city": city,
            "hotel_state": state,
            "manager_username": f"manager-{username_suffix}",
            "manager_password": "ManagerPass123!",
            "director_username": f"director-{username_suffix}",
            "director_password": "DirectorPass123!",
            "reception_username": f"reception-{username_suffix}",
            "reception_password": "ReceptionPass123!",
        })
        self.assertEqual(response.status_code, 302)
        response = client.post("/login/manager", data={
            "username": f"manager-{username_suffix}",
            "password": "ManagerPass123!",
        })
        self.assertEqual(response.status_code, 302)
        with client.session_transaction() as current_session:
            return current_session["hotel_id"]

    def configure_online_booking(self, client, hotel_id, room_name, rate):
        response = client.post("/workspace/manager/rooms", data={
            "number": "101",
            "name": room_name,
            "beds": "1",
            "rate": str(rate),
        })
        self.assertEqual(response.status_code, 302)
        response = client.post("/workspace/manager/online-settings", data={
            "action": "settings",
            "bank_name": f"{room_name} Bank",
            "account_name": f"{room_name} Hotel",
            "account_number": "12345678",
            "reception_whatsapp": "+2348012345678",
            "reception_email": f"reception-{hotel_id[:8]}@example.com",
        })
        self.assertEqual(response.status_code, 302)
        with self.app_module.app.app_context():
            self.app_module.get_db().execute(
                """INSERT INTO online_room_listings
                (hotel_id, room_number, description, photo_path, enabled, updated_at)
                VALUES (?, '101', ?, ?, 1, ?)""",
                (
                    hotel_id, f"{room_name} guest room",
                    f"{hotel_id}/{'a' * 32}.jpg", self.app_module.now_iso(),
                ),
            )
            self.app_module.get_db().commit()

    def test_calendar_shows_booked_and_approved_online_stays(self):
        week_start = date.today() - timedelta(days=date.today().weekday())
        calendar_days, calendar_rows = self.app_module.reference_calendar(
            [{"number": "101"}],
            [
                {
                    "id": "manual-booking",
                    "room_number": 101,
                    "guest_name": "Manual Guest",
                    "status": "BOOKED",
                    "check_in": week_start,
                    "check_out": week_start + timedelta(days=2),
                    "booking_source": "reception",
                },
                {
                    "id": "approved-online-booking",
                    "room_number": "101",
                    "guest_name": "Online Guest",
                    "status": "booked",
                    "check_in": week_start + timedelta(days=2),
                    "check_out": week_start + timedelta(days=4),
                    "booking_source": "online",
                },
                {
                    "id": "cancelled-booking",
                    "room_number": "101",
                    "guest_name": "Cancelled Guest",
                    "status": "cancelled",
                    "check_in": week_start,
                    "check_out": week_start + timedelta(days=4),
                    "booking_source": "reception",
                },
            ],
            week_start,
        )

        self.assertEqual(len(calendar_days), 7)
        cells = calendar_rows[0]["cells"]
        self.assertEqual(cells[0]["guest"], "Manual Guest")
        self.assertEqual(cells[0]["status"], "booked")
        self.assertEqual(cells[1]["guest"], "Manual Guest")
        self.assertEqual(cells[2]["guest"], "Online Guest")
        self.assertEqual(cells[2]["source"], "Online")
        self.assertEqual(cells[3]["guest"], "Online Guest")
        self.assertEqual(cells[4]["status"], "")

    def test_future_reception_stays_show_in_calendar_without_date_clashes(self):
        manager = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            manager, "Calendar Test Hotel", "calendar",
            "1 Main Road", "Lagos", "Lagos",
        )
        response = manager.post("/workspace/manager/rooms", data={
            "number": "101", "name": "Standard", "beds": "1", "rate": "50000",
        })
        self.assertEqual(response.status_code, 302)

        reception = self.app_module.app.test_client()
        response = reception.post("/login/reception", data={
            "username": "reception-calendar",
            "password": "ReceptionPass123!",
        })
        self.assertEqual(response.status_code, 302)
        response = reception.post("/rooms/101/status", data={
            "status": "available", "reference": "true",
        })
        self.assertEqual(response.status_code, 302)

        arrival = date.today() + timedelta(days=3)
        departure = date.today() + timedelta(days=6)
        response = reception.post("/workspace/reception/new", data={
            "room_number": "101",
            "guest_name": "Tobi",
            "phone": "08000000000",
            "email": "tobi@example.com",
            "check_in": arrival.isoformat(),
            "check_out": departure.isoformat(),
            "total_amount": "150000",
            "amount_paid": "150000",
            "payment_method": "Transfer",
        })
        self.assertEqual(response.status_code, 302)

        calendar = reception.get("/workspace/reception/calendar", query_string={
            "reference_date": arrival.isoformat(),
        })
        self.assertEqual(calendar.status_code, 200)
        self.assertIn(b"Tobi", calendar.data)
        self.assertIn(b"Booked", calendar.data)
        checkout = reception.get("/workspace/reception/checkout")
        self.assertEqual(checkout.status_code, 200)
        self.assertNotIn(b"Tobi", checkout.data)

        response = reception.post("/workspace/reception/new", data={
            "room_number": "101",
            "guest_name": "Clashing Guest",
            "phone": "08000000001",
            "email": "clash@example.com",
            "check_in": (arrival + timedelta(days=2)).isoformat(),
            "check_out": (departure + timedelta(days=1)).isoformat(),
            "total_amount": "100000",
            "amount_paid": "0",
            "payment_method": "Cash",
        })
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"already has a booking", response.data)

        response = reception.post(
            "/reservations/new?role=reception",
            data={
                "room_number": "101",
                "guest_name": "Legacy Clashing Guest",
                "phone": "08000000003",
                "email": "legacy-clash@example.com",
                "check_in": (arrival + timedelta(days=1)).isoformat(),
                "check_out": (departure + timedelta(days=1)).isoformat(),
                "payment_method": "Cash",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"already has a booking", response.data)

        response = reception.post("/workspace/reception/new", data={
            "room_number": "101",
            "guest_name": "Next Guest",
            "phone": "08000000002",
            "email": "next@example.com",
            "check_in": departure.isoformat(),
            "check_out": (departure + timedelta(days=2)).isoformat(),
            "total_amount": "100000",
            "amount_paid": "0",
            "payment_method": "Cash",
        })
        self.assertEqual(response.status_code, 302)
        with self.app_module.app.app_context():
            bookings = self.app_module.get_db().execute(
                """SELECT guest_name, status FROM reservations
                WHERE hotel_id = ? AND room_number = '101'
                ORDER BY check_in""",
                (hotel_id,),
            ).fetchall()
            self.assertEqual(
                [(row["guest_name"], row["status"]) for row in bookings],
                [("Tobi", "booked"), ("Next Guest", "booked")],
            )
            tobi = self.app_module.get_db().execute(
                "SELECT id FROM reservations WHERE guest_name = 'Tobi'"
            ).fetchone()

        response = reception.post(
            f"/reservations/{tobi['id']}/status",
            data={
                "role": "reception",
                "action": "extend",
                "check_out": (departure + timedelta(days=1)).isoformat(),
            },
        )
        self.assertEqual(response.status_code, 302)
        checkout = reception.get("/workspace/reception/checkout")
        self.assertIn(
            b"another stay scheduled before that departure date",
            checkout.data,
        )
        with self.app_module.app.app_context():
            tobi_checkout = self.app_module.get_db().execute(
                "SELECT check_out FROM reservations WHERE id = ?",
                (tobi["id"],),
            ).fetchone()["check_out"]
            self.assertEqual(tobi_checkout, departure.isoformat())

    def test_manager_and_director_use_one_top_navigation_across_pages(self):
        manager = self.app_module.app.test_client()
        self.register_hotel(
            manager, "Navigation Test Hotel", "navigation",
            "1 Main Road", "Lagos", "Lagos",
        )

        for page, expected_link in (
            ("dashboard", b"Operational Overview"),
            ("rooms", b">Rooms</a>"),
            ("bookings", b">Bookings</a>"),
            ("calendar", b"Booking Calendar"),
            ("finance", b">Finance</a>"),
            ("online-settings", b"Online Booking Setup"),
        ):
            response = manager.get(f"/workspace/manager/{page}")
            self.assertEqual(response.status_code, 200)
            self.assertIn(expected_link, response.data)
            self.assertEqual(response.data.count(b'class="header-nav"'), 1)
            self.assertNotIn(b'class="reference-sidebar"', response.data)

        team_page = manager.get("/signup/manager")
        self.assertEqual(team_page.status_code, 200)
        self.assertEqual(team_page.data.count(b'class="header-nav"'), 1)
        self.assertNotIn(b'class="reference-sidebar"', team_page.data)

        director = self.app_module.app.test_client()
        response = director.post("/login/director", data={
            "username": "director-navigation",
            "password": "DirectorPass123!",
        })
        self.assertEqual(response.status_code, 302)
        for page, expected_link in (
            ("dashboard", b">Dashboard</a>"),
            ("rooms", b">Rooms</a>"),
            ("finance", b">Finance</a>"),
        ):
            response = director.get(f"/workspace/director/{page}")
            self.assertEqual(response.status_code, 200)
            self.assertIn(expected_link, response.data)
            self.assertEqual(response.data.count(b'class="header-nav"'), 1)
            self.assertNotIn(b'class="reference-sidebar"', response.data)

    def test_signup_guest_selection_booking_and_staff_isolation(self):
        hotel_one_manager = self.app_module.app.test_client()
        hotel_one_id = self.register_hotel(
            hotel_one_manager, "Labim Test Hotel", "one",
            "1 Beach Road", "Lagos", "Lagos",
        )
        self.configure_online_booking(
            hotel_one_manager, hotel_one_id, "Standard", 50000
        )

        hotel_two_manager = self.app_module.app.test_client()
        hotel_two_id = self.register_hotel(
            hotel_two_manager, "Other Test Hotel", "two",
            "14 Independence Avenue", "Enugu", "Enugu",
        )
        self.configure_online_booking(
            hotel_two_manager, hotel_two_id, "Suite", 90000
        )
        self.assertNotEqual(hotel_one_id, hotel_two_id)
        with self.app_module.app.app_context():
            hotel_two_location = self.app_module.hotel_details(hotel_two_id)
            self.assertEqual(
                (hotel_two_location["address"], hotel_two_location["city"],
                 hotel_two_location["state"]),
                ("14 Independence Avenue", "Enugu", "Enugu"),
            )
        photo_upload = hotel_two_manager.post(
            "/rooms/101/online",
            data={
                "photos": [
                    (BytesIO(b"\x89PNG\r\n\x1a\nimage one"), "room-one.png", "image/png"),
                    (BytesIO(b"\x89PNG\r\n\x1a\nimage two"), "room-two.png", "image/png"),
                ]
            },
            content_type="multipart/form-data",
        )
        self.assertEqual(photo_upload.status_code, 302)
        with self.app_module.app.app_context():
            listing = self.app_module.get_db().execute(
                """SELECT photo_path, photo_paths, enabled FROM online_room_listings
                WHERE hotel_id = ? AND room_number = '101'""",
                (hotel_two_id,),
            ).fetchone()
            self.assertEqual(len(self.app_module.room_photo_paths(dict(listing))), 2)
            self.assertTrue(listing["enabled"])

        one_workspace = hotel_one_manager.get("/workspace/manager/rooms")
        two_workspace = hotel_two_manager.get("/workspace/manager/rooms")
        self.assertIn("Standard • ₦50,000".encode(), one_workspace.data)
        self.assertNotIn("Suite • ₦90,000".encode(), one_workspace.data)
        self.assertIn("Suite • ₦90,000".encode(), two_workspace.data)
        self.assertNotIn("Standard • ₦50,000".encode(), two_workspace.data)

        stay_start = (date.today() + timedelta(days=3)).isoformat()
        stay_end = (date.today() + timedelta(days=4)).isoformat()
        with self.app_module.app.app_context():
            hotel_two = self.app_module.hotel_details(hotel_two_id)

        reception = self.app_module.app.test_client()
        response = reception.post("/login/reception", data={
            "username": "reception-two",
            "password": "ReceptionPass123!",
        })
        self.assertEqual(response.status_code, 302)
        response = reception.post("/rooms/101/status", data={
            "status": "cleaning",
            "reference": "true",
        })
        self.assertEqual(response.status_code, 302)
        guest = self.app_module.app.test_client()
        hotel_directory = guest.get("/book")
        self.assertEqual(hotel_directory.status_code, 200)
        self.assertIn(b"Labim Test Hotel", hotel_directory.data)
        self.assertIn(b"Other Test Hotel", hotel_directory.data)
        self.assertIn(b"14 Independence Avenue", hotel_directory.data)
        self.assertIn(
            f"/book?hotel={hotel_two['slug']}".encode(),
            hotel_directory.data,
        )
        self.assertNotIn(b'<select name="hotel"', hotel_directory.data)
        filtered_directory = guest.get("/book", query_string={
            "state": "Enugu",
            "city": "enu",
        })
        self.assertEqual(filtered_directory.status_code, 200)
        self.assertIn(b"Other Test Hotel", filtered_directory.data)
        self.assertNotIn(b"Labim Test Hotel", filtered_directory.data)
        search = guest.get("/book", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertEqual(search.status_code, 200)
        self.assertIn(b"No listed rooms available", search.data)
        self.assertNotIn(b"Photo 1 of Room 101", search.data)

        response = reception.post("/rooms/101/status", data={
            "status": "available",
            "reference": "true",
        })
        self.assertEqual(response.status_code, 302)
        search = guest.get("/book", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertEqual(search.status_code, 200)
        self.assertIn(b"Other Test Hotel", search.data)
        self.assertIn(b"Suite", search.data)
        self.assertIn(b"Photo 1 of Room 101", search.data)
        self.assertIn(b"Photo 2 of Room 101", search.data)
        with guest.session_transaction() as guest_session:
            csrf_token = guest_session["public_booking_csrf"]

        with patch.object(
            self.app_module,
            "send_reception_booking_email",
        ) as send_reception_email:
            send_reception_email.return_value = None
            response = guest.post("/book", data={
                "csrf_token": csrf_token,
                "hotel_id": hotel_two_id,
                "hotel_slug": hotel_two["slug"],
                "room_number": "101",
                "check_in": stay_start,
                "check_out": stay_end,
                "guest_name": "Guest Two",
                "email": "guest@example.com",
                "phone": "08000000000",
            })
        self.assertEqual(response.status_code, 302)
        send_reception_email.assert_called_once()
        email_args = send_reception_email.call_args.args
        self.assertEqual(
            (email_args[0], email_args[1], *email_args[3:]),
            (f"reception-{hotel_two_id[:8]}@example.com", "Other Test Hotel",
             "Guest Two", "guest@example.com", "08000000000", "101",
             stay_start, stay_end, 90000),
        )
        confirmation = guest.get("/booking/confirmation")
        self.assertEqual(confirmation.status_code, 200)
        self.assertIn(b"Other Test Hotel", confirmation.data)
        self.assertIn(b"Suite Bank", confirmation.data)
        self.assertIn(b"notification has been emailed", confirmation.data)

        with self.app_module.app.app_context():
            booking = self.app_module.get_db().execute(
                "SELECT * FROM reservations WHERE guest_name = 'Guest Two'"
            ).fetchone()
            self.assertEqual(booking["hotel_id"], hotel_two_id)
            self.assertEqual(booking["room_number"], "101")
            self.assertEqual(
                self.app_module.get_db().execute(
                    "SELECT hotel_id FROM online_booking_settings WHERE hotel_id = ?",
                    (hotel_two_id,),
                ).fetchone()["hotel_id"],
                hotel_two_id,
            )

        response = reception.post(
            f"/online-bookings/{booking['id']}/confirm"
        )
        self.assertEqual(response.status_code, 302)
        self.assertIn(
            f"/workspace/reception/calendar?reference_date={stay_start}",
            response.headers["Location"],
        )
        approved_calendar = reception.get(response.headers["Location"])
        self.assertEqual(approved_calendar.status_code, 200)
        self.assertIn(b"Booked", approved_calendar.data)
        self.assertIn(b"Guest Two \xc2\xb7 Online", approved_calendar.data)
        checkout_page = reception.get("/workspace/reception/checkout")
        self.assertEqual(checkout_page.status_code, 200)
        self.assertNotIn(b"Guest Two", checkout_page.data)
        with self.app_module.app.app_context():
            confirmed = self.app_module.get_db().execute(
                "SELECT status, amount_paid FROM reservations WHERE id = ?",
                (booking["id"],),
            ).fetchone()
            payment = self.app_module.get_db().execute(
                "SELECT hotel_id, amount FROM payments WHERE reservation_id = ?",
                (booking["id"],),
            ).fetchone()
            self.assertEqual(confirmed["status"], "booked")
            self.assertEqual(confirmed["amount_paid"], 90000)
            self.assertEqual(payment["hotel_id"], hotel_two_id)
            self.assertEqual(payment["amount"], 90000)

        hotel_two_availability = guest.get("/book", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertIn(b"No listed rooms available", hotel_two_availability.data)
        with self.app_module.app.app_context():
            hotel_one = self.app_module.hotel_details(hotel_one_id)
        hotel_one_availability = guest.get("/book", query_string={
            "hotel": hotel_one["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertIn(b"No listed rooms available", hotel_one_availability.data)
        reception_one = self.app_module.app.test_client()
        response = reception_one.post("/login/reception", data={
            "username": "reception-one",
            "password": "ReceptionPass123!",
        })
        self.assertEqual(response.status_code, 302)
        response = reception_one.post("/rooms/101/status", data={
            "status": "available",
            "reference": "true",
        })
        self.assertEqual(response.status_code, 302)
        hotel_one_availability = guest.get("/book", query_string={
            "hotel": hotel_one["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertIn("Standard · Room 101".encode(), hotel_one_availability.data)
        self.assertNotIn("Suite · Room 101".encode(), hotel_one_availability.data)

    def test_legacy_sqlite_records_are_assigned_to_labim(self):
        legacy_directory = Path(tempfile.mkdtemp())
        try:
            shutil.copy2(
                Path(__file__).resolve().parents[1] / "app.py",
                legacy_directory / "app.py",
            )
            shutil.copytree(
                Path(__file__).resolve().parents[1] / "templates",
                legacy_directory / "templates",
            )
            shutil.copytree(
                Path(__file__).resolve().parents[1] / "static",
                legacy_directory / "static",
            )
            (legacy_directory / "instance").mkdir()
            connection = sqlite3.connect(
                legacy_directory / "instance" / "booking_os.sqlite3"
            )
            connection.executescript(
                """
                CREATE TABLE rooms (
                    number TEXT PRIMARY KEY, name TEXT NOT NULL,
                    beds INTEGER NOT NULL, rate INTEGER NOT NULL, status TEXT NOT NULL
                );
                INSERT INTO rooms VALUES ('101', 'Standard', 1, 50000, 'available');
                CREATE TABLE reservations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, guest_name TEXT NOT NULL,
                    email TEXT NOT NULL, phone TEXT NOT NULL, room_number TEXT NOT NULL,
                    check_in TEXT NOT NULL, check_out TEXT NOT NULL, amount INTEGER NOT NULL,
                    payment_method TEXT NOT NULL, payment_status TEXT NOT NULL DEFAULT 'pending',
                    status TEXT NOT NULL DEFAULT 'checked_in', created_at TEXT NOT NULL
                );
                INSERT INTO reservations VALUES
                    (1, 'Legacy Guest', '', '0800000000', '101', '2030-01-01',
                     '2030-01-02', 50000, 'Transfer', 'paid', 'booked', 'now');
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL UNIQUE,
                    username TEXT NOT NULL UNIQUE, password TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                INSERT INTO users VALUES (1, 'manager', 'legacy-manager', 'hash', 'now');
                CREATE TABLE payments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, reservation_id INTEGER NOT NULL,
                    room_number TEXT NOT NULL, amount INTEGER NOT NULL, balance INTEGER NOT NULL,
                    method TEXT NOT NULL, received_by TEXT NOT NULL, created_at TEXT NOT NULL
                );
                INSERT INTO payments VALUES
                    (1, 1, '101', 50000, 0, 'Transfer', 'Reception', 'now');
                CREATE TABLE app_migrations (name TEXT PRIMARY KEY);
                CREATE TABLE online_room_listings (
                    room_number TEXT PRIMARY KEY, description TEXT NOT NULL DEFAULT '',
                    photo_path TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL
                );
                INSERT INTO online_room_listings VALUES ('101', 'Legacy room', '', 0, 'now');
                CREATE TABLE online_booking_settings (
                    id INTEGER PRIMARY KEY CHECK (id = 1), bank_name TEXT NOT NULL DEFAULT '',
                    account_name TEXT NOT NULL DEFAULT '', account_number TEXT NOT NULL DEFAULT '',
                    reception_whatsapp TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL
                );
                INSERT INTO online_booking_settings
                    VALUES (1, 'Legacy Bank', 'Labim Hotel', '12345678', '+2348012345678', 'now');
                """
            )
            connection.commit()
            connection.close()

            spec = importlib.util.spec_from_file_location(
                "legacy_sqlite_test_app", legacy_directory / "app.py"
            )
            legacy_app = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = legacy_app
            spec.loader.exec_module(legacy_app)
            legacy_app.SUPABASE_ENABLED = False
            with legacy_app.app.app_context():
                db = legacy_app.get_db()
                hotel_id = legacy_app.DEFAULT_HOTEL_ID
                self.assertEqual(
                    db.execute("SELECT hotel_id FROM rooms WHERE number = '101'").fetchone()[0],
                    hotel_id,
                )
                self.assertEqual(
                    db.execute("SELECT hotel_id FROM reservations WHERE id = 1").fetchone()[0],
                    hotel_id,
                )
                self.assertEqual(
                    db.execute("SELECT hotel_id FROM users WHERE username = 'legacy-manager'").fetchone()[0],
                    hotel_id,
                )
                self.assertEqual(
                    db.execute("SELECT bank_name FROM online_booking_settings WHERE hotel_id = ?", (hotel_id,)).fetchone()[0],
                    "Legacy Bank",
                )
                self.assertEqual(
                    db.execute(
                        "SELECT reception_email FROM online_booking_settings WHERE hotel_id = ?",
                        (hotel_id,),
                    ).fetchone()[0],
                    "",
                )
                db.execute(
                    "INSERT INTO hotels (id, name, slug, created_at) VALUES ('tenant-two', 'Second Hotel', 'second-hotel', 'now')"
                )
                db.execute(
                    "INSERT INTO rooms (number, hotel_id, name, beds, rate, status) VALUES ('101', 'tenant-two', 'Suite', 2, 90000, 'available')"
                )
                self.assertEqual(
                    db.execute("SELECT COUNT(*) FROM rooms WHERE number = '101'").fetchone()[0],
                    2,
                )
            sys.modules.pop(spec.name, None)
        finally:
            shutil.rmtree(legacy_directory)

    def test_reception_booking_email_uses_tls_and_includes_review_link(self):
        with self.app_module.app.test_request_context():
            with (
                patch.dict("os.environ", {
                    "SMTP_HOST": "smtp.example.com",
                    "SMTP_PORT": "587",
                    "SMTP_FROM_EMAIL": "bookings@example.com",
                    "SMTP_USERNAME": "smtp-user",
                    "SMTP_PASSWORD": "smtp-password",
                }),
                patch.object(self.app_module.smtplib, "SMTP") as smtp_factory,
            ):
                smtp = smtp_factory.return_value.__enter__.return_value
                self.app_module.send_reception_booking_email(
                    "reception@example.com",
                    "Test Hotel",
                    "booking-123",
                    "Guest Name",
                    "guest@example.com",
                    "+2348000000000",
                    "101",
                    "2030-01-01",
                    "2030-01-02",
                    50000,
                )

        smtp.starttls.assert_called_once()
        smtp.login.assert_called_once_with("smtp-user", "smtp-password")
        sent_message = smtp.send_message.call_args.args[0]
        self.assertEqual(sent_message["To"], "reception@example.com")
        self.assertIn("booking-123", sent_message.get_content())
        self.assertIn("Guest Name", sent_message.get_content())
        self.assertIn("/workspace/reception/online", sent_message.get_content())


if __name__ == "__main__":
    unittest.main()
