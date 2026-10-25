import importlib.util
from email.message import Message
from io import BytesIO
import json
import sqlite3
import shutil
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from datetime import date, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlparse


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
        self, client, name, username_suffix, address, city, state, plan="trial"
    ):
        response = client.post("/signup/manager", data={
            "hotel_name": name,
            "hotel_address": address,
            "hotel_city": city,
            "hotel_state": state,
            "billing_email": f"billing-{username_suffix}@example.com",
            "plan": plan,
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

    def test_category_preview_routes_serve_flutter_app(self):
        with tempfile.TemporaryDirectory() as build_directory:
            build_path = Path(build_directory)
            (build_path / "index.html").write_text(
                "<!doctype html><title>Rooms</title>",
                encoding="utf-8",
            )
            with patch.object(
                self.app_module, "FLUTTER_WEB_BUILD_DIRECTORY", build_path
            ):
                client = self.app_module.app.test_client()
                for path in ("/rental", "/apartment", "/land-properties"):
                    with self.subTest(path=path):
                        response = client.get(path)
                        self.assertEqual(response.status_code, 200)
                        self.assertIn(b"<title>Rooms</title>", response.data)
                        response.close()

                        trailing_slash = client.get(f"{path}/")
                        self.assertEqual(trailing_slash.status_code, 308)
                        self.assertEqual(
                            trailing_slash.headers["Location"],
                            path,
                        )

    def test_rental_proxy_keeps_marketplace_routes_on_rooms_origin(self):
        response_from_rental = Mock()
        response_from_rental.status = 200
        response_from_rental.headers = Message()
        response_from_rental.headers["Content-Type"] = "text/html; charset=utf-8"
        response_from_rental.read.return_value = (
            b'<base href="/"><script src="/flutter_bootstrap.js"></script>'
        )
        response_from_rental.__enter__ = Mock(return_value=response_from_rental)
        response_from_rental.__exit__ = Mock(return_value=False)

        with patch.object(
            self.app_module, "urlopen", return_value=response_from_rental
        ) as open_upstream:
            response = self.app_module.app.test_client().get(
                "/rentals/land?transaction_type=sale"
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn(b'<base href="/rentals/">', response.data)
        self.assertIn(b'src="/rentals/flutter_bootstrap.js"', response.data)
        upstream_request = open_upstream.call_args.args[0]
        self.assertEqual(
            upstream_request.full_url,
            "https://labim-house-rental.onrender.com/land?transaction_type=sale",
        )

    def test_rental_home_route_proxies_to_rental_homepage(self):
        upstream_response = Mock()
        upstream_response.status = 200
        upstream_response.headers = Message()
        upstream_response.headers["Content-Type"] = "text/html; charset=utf-8"
        upstream_response.read.return_value = b"<html><head></head></html>"
        upstream_response.__enter__ = Mock(return_value=upstream_response)
        upstream_response.__exit__ = Mock(return_value=False)

        with patch.object(
            self.app_module, "urlopen", return_value=upstream_response
        ) as open_upstream:
            response = self.app_module.app.test_client().get("/rentals")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b'<base href="/rentals/">', response.data)
        self.assertEqual(
            open_upstream.call_args.args[0].full_url,
            "https://labim-house-rental.onrender.com/",
        )

    def test_rental_home_route_retries_transient_gateway_errors(self):
        gateway_errors = [
            self.app_module.HTTPError(
                "https://labim-house-rental.onrender.com/",
                502,
                "Bad Gateway",
                Message(),
                BytesIO(b"temporary gateway error"),
            )
            for _ in range(5)
        ]
        upstream_response = Mock()
        upstream_response.status = 200
        upstream_response.headers = Message()
        upstream_response.headers["Content-Type"] = "text/html; charset=utf-8"
        upstream_response.read.return_value = b"<html><head></head></html>"
        upstream_response.__enter__ = Mock(return_value=upstream_response)
        upstream_response.__exit__ = Mock(return_value=False)

        with patch.object(
            self.app_module,
            "urlopen",
            side_effect=[*gateway_errors, upstream_response],
        ) as open_upstream, patch.object(self.app_module.time, "sleep") as sleep:
            response = self.app_module.app.test_client().get("/rentals")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(open_upstream.call_count, 6)
        self.assertEqual(
            [call.args[0] for call in sleep.call_args_list],
            [1, 2, 4, 8, 15],
        )

    def test_rental_proxy_does_not_retry_state_changing_requests(self):
        gateway_error = self.app_module.HTTPError(
            "https://labim-house-rental.onrender.com/api/public/property-requests/",
            502,
            "Bad Gateway",
            Message(),
            BytesIO(b"temporary gateway error"),
        )

        with patch.object(
            self.app_module,
            "urlopen",
            side_effect=gateway_error,
        ) as open_upstream, patch.object(self.app_module.time, "sleep") as sleep:
            response = self.app_module.app.test_client().post(
                "/rentals/api/public/property-requests/",
                data=b'{"name":"Guest"}',
                content_type="application/json",
            )

        self.assertEqual(response.status_code, 502)
        open_upstream.assert_called_once()
        sleep.assert_not_called()

    def test_rental_proxy_mounts_admin_pages_and_static_paths(self):
        upstream_response = Mock()
        upstream_response.status = 200
        upstream_response.headers = Message()
        upstream_response.headers["Content-Type"] = "text/html; charset=utf-8"
        upstream_response.read.return_value = (
            b'<html><head><link href="/static/admin.css"></head>'
            b'<body><form action="/accounts/login/"></form></body></html>'
        )
        upstream_response.__enter__ = Mock(return_value=upstream_response)
        upstream_response.__exit__ = Mock(return_value=False)

        with patch.object(self.app_module, "urlopen", return_value=upstream_response):
            response = self.app_module.app.test_client().get(
                "/rentals/accounts/login/"
            )

        self.assertIn(b'<base href="/rentals/">', response.data)
        self.assertIn(b'href="/rentals/static/admin.css"', response.data)
        self.assertIn(b'action="/rentals/accounts/login/"', response.data)

    def test_rental_proxy_forwards_only_rental_cookies_and_rewrites_csrf_origin(self):
        response_from_rental = Mock()
        response_from_rental.status = 201
        response_from_rental.headers = Message()
        response_from_rental.headers["Content-Type"] = "application/json"
        response_from_rental.headers.add_header(
            "Set-Cookie",
            "csrftoken=new-token; Path=/; SameSite=Lax",
        )
        response_from_rental.read.return_value = b'{"saved":true}'
        response_from_rental.__enter__ = Mock(return_value=response_from_rental)
        response_from_rental.__exit__ = Mock(return_value=False)

        client = self.app_module.app.test_client()
        client.set_cookie(
            "session",
            "hotel-session",
            domain="rooms-uamy.onrender.com",
        )
        client.set_cookie(
            "csrftoken",
            "rental-token",
            domain="rooms-uamy.onrender.com",
        )
        client.set_cookie(
            "sessionid",
            "rental-session",
            domain="rooms-uamy.onrender.com",
        )
        with patch.object(
            self.app_module, "urlopen", return_value=response_from_rental
        ) as open_upstream:
            response = client.post(
                "/rentals/api/public/property-requests/",
                json={"name": "Guest"},
                base_url="https://rooms-uamy.onrender.com",
                headers={
                    "Origin": "https://rooms-uamy.onrender.com",
                    "Referer": "https://rooms-uamy.onrender.com/rentals/",
                    "X-CSRFToken": "rental-token",
                },
            )

        self.assertEqual(response.status_code, 201)
        self.assertIn("Path=/rentals;", response.headers["Set-Cookie"])
        upstream_request = open_upstream.call_args.args[0]
        self.assertEqual(
            upstream_request.get_header("Origin"),
            "https://labim-house-rental.onrender.com",
        )
        self.assertEqual(
            upstream_request.get_header("Cookie"),
            "csrftoken=rental-token; sessionid=rental-session",
        )
        self.assertEqual(
            upstream_request.get_header("Referer"),
            "https://labim-house-rental.onrender.com/",
        )

    def test_rental_proxy_does_not_trust_an_unrelated_origin(self):
        upstream_response = Mock()
        upstream_response.status = 200
        upstream_response.headers = Message()
        upstream_response.read.return_value = b"{}"
        upstream_response.__enter__ = Mock(return_value=upstream_response)
        upstream_response.__exit__ = Mock(return_value=False)

        with patch.object(
            self.app_module, "urlopen", return_value=upstream_response
        ) as open_upstream:
            self.app_module.app.test_client().post(
                "/rentals/api/public/property-requests/",
                data="{}",
                base_url="https://rooms-uamy.onrender.com",
                headers={"Origin": "https://attacker.example"},
            )

        upstream_request = open_upstream.call_args.args[0]
        self.assertEqual(
            upstream_request.get_header("Origin"),
            "https://attacker.example",
        )

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

    def test_online_room_price_ranges_are_non_overlapping(self):
        rooms = [{"rate": rate} for rate in (
            9_999, 10_000, 50_000, 50_001, 100_000,
            100_001, 200_000, 200_001,
        )]
        expected_rates = {
            "10000-50000": [10_000, 50_000],
            "50000-100000": [50_001, 100_000],
            "100000-200000": [100_001, 200_000],
            "200000-plus": [200_001],
        }
        for price_range, expected in expected_rates.items():
            with self.subTest(price_range=price_range):
                self.assertEqual(
                    [
                        room["rate"] for room
                        in self.app_module.filter_rooms_by_price_range(
                            rooms, price_range
                        )
                    ],
                    expected,
                )

    def test_expired_trial_blocks_manager_director_and_reception(self):
        client = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            client, "Trial Expiry Hotel", "trial-expiry",
            "8 Market Road", "Lagos", "Lagos",
        )
        with self.app_module.app.app_context():
            expired_at = (
                self.app_module.datetime.now(
                    self.app_module.timezone.utc
                ) - timedelta(seconds=1)
            ).isoformat()
            self.app_module.get_db().execute(
                "UPDATE hotel_subscriptions SET trial_ends_at = ? WHERE hotel_id = ?",
                (expired_at, hotel_id),
            )
            self.app_module.get_db().commit()
            self.assertFalse(
                self.app_module.subscription_access(hotel_id)["allowed"]
            )

        for role in ("manager", "director", "reception"):
            with self.subTest(role=role):
                with client.session_transaction() as current_session:
                    current_session["user_role"] = role
                    current_session["hotel_id"] = hotel_id
                response = client.get(f"/workspace/{role}/dashboard")
                self.assertEqual(
                    response.status_code, 302,
                    f"{role}: expected billing redirect, got {response.status_code} "
                    f"at {response.request.path} -> {response.headers.get('Location')}",
                )
                self.assertEqual(response.headers["Location"], "/billing")

        response = client.get("/billing")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Subscription required", response.data)
        with client.session_transaction() as current_session:
            current_session["user_role"] = "manager"
        response = client.get("/signup/manager")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response.headers["Location"], "/billing")

    def test_existing_hotel_manager_can_opt_in_from_plan_and_billing(self):
        client = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            client, "Existing Account Hotel", "existing-account",
            "12 Market Road", "Lagos", "Lagos",
        )
        with self.app_module.app.app_context():
            self.app_module.get_db().execute(
                "DELETE FROM hotel_subscriptions WHERE hotel_id = ?",
                (hotel_id,),
            )
            self.app_module.get_db().commit()

        response = client.get("/billing")
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"grandfathered", response.data)
        self.assertIn(b"Pay monthly with Paystack", response.data)
        self.assertIn(b"Pay annually with Paystack", response.data)
        with self.app_module.app.app_context():
            subscription = self.app_module.subscription_record(hotel_id)
        self.assertEqual(subscription["status"], "legacy")
        self.assertEqual(subscription["billing_email"], "")

    def test_expired_hotel_is_hidden_and_public_booking_is_rejected(self):
        manager = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            manager, "Expired Online Hotel", "expired-online",
            "13 Market Road", "Lagos", "Lagos",
        )
        self.configure_online_booking(
            manager, hotel_id, "Expired Listing", 50000
        )
        with self.app_module.app.app_context():
            hotel = self.app_module.hotel_details(hotel_id)
            expired_at = (
                self.app_module.datetime.now(
                    self.app_module.timezone.utc
                ) - timedelta(seconds=1)
            ).isoformat()
            self.app_module.get_db().execute(
                """UPDATE hotel_subscriptions SET trial_ends_at = ?
                WHERE hotel_id = ?""",
                (expired_at, hotel_id),
            )
            self.app_module.get_db().commit()

        guest = self.app_module.app.test_client()
        directory = guest.get("/book-legacy")
        self.assertEqual(directory.status_code, 200)
        self.assertNotIn(b"Expired Online Hotel", directory.data)
        direct_hotel_page = guest.get(
            "/book-legacy", query_string={"hotel": hotel["slug"]}
        )
        self.assertEqual(direct_hotel_page.status_code, 200)
        self.assertNotIn(b"Expired Listing", direct_hotel_page.data)

        api_rooms = guest.get(
            f"/api/public/hotels/{hotel['slug']}/rooms",
            query_string={
                "check_in": (date.today() + timedelta(days=3)).isoformat(),
                "check_out": (date.today() + timedelta(days=4)).isoformat(),
            },
        )
        self.assertEqual(api_rooms.status_code, 404)

        with guest.session_transaction() as guest_session:
            csrf_token = guest_session["public_booking_csrf"]
        check_in = (date.today() + timedelta(days=3)).isoformat()
        check_out = (date.today() + timedelta(days=4)).isoformat()
        response = guest.post("/book-legacy", data={
            "csrf_token": csrf_token,
            "hotel_id": hotel_id,
            "hotel_slug": hotel["slug"],
            "room_number": "101",
            "check_in": check_in,
            "check_out": check_out,
            "guest_name": "Blocked Guest",
            "email": "blocked@example.com",
            "phone": "08000000000",
        })
        self.assertEqual(response.status_code, 200)
        self.assertIn(
            b"online booking is temporarily unavailable",
            response.data,
        )
        api_booking = guest.post(
            "/api/public/bookings",
            json={
                "hotel_id": hotel_id,
                "hotel_slug": hotel["slug"],
                "room_number": "101",
                "check_in": check_in,
                "check_out": check_out,
                "guest_name": "Blocked API Guest",
                "email": "blocked-api@example.com",
                "phone": "08000000000",
            },
        )
        self.assertEqual(api_booking.status_code, 400)
        self.assertIn(
            "subscription is inactive",
            api_booking.get_json()["error"],
        )
        with self.app_module.app.app_context():
            reservation_count = self.app_module.get_db().execute(
                "SELECT COUNT(*) FROM reservations WHERE hotel_id = ?",
                (hotel_id,),
            ).fetchone()[0]
        self.assertEqual(reservation_count, 0)

    def test_flutter_public_api_search_room_and_booking_flow(self):
        manager = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            manager, "Flutter API Hotel", "flutter-api",
            "15 Market Road", "Flutter City", "Lagos",
        )
        self.configure_online_booking(
            manager, hotel_id, "API Suite", 75000
        )
        with self.app_module.app.app_context():
            self.app_module.get_db().execute(
                """UPDATE rooms SET status = 'available'
                WHERE hotel_id = ? AND number = '101'""",
                (hotel_id,),
            )
            self.app_module.get_db().commit()
        guest = self.app_module.app.test_client()
        config_response = guest.get("/api/public/config")
        self.assertEqual(config_response.status_code, 200)
        self.assertIn(
            "Lagos",
            config_response.get_json()["states"],
        )
        self.assertIn(
            "10000-50000",
            {
                price_range["key"]
                for price_range in config_response.get_json()["price_ranges"]
            },
        )

        check_in = (date.today() + timedelta(days=4)).isoformat()
        check_out = (date.today() + timedelta(days=5)).isoformat()
        hotels_response = guest.get("/api/public/hotels", query_string={
            "check_in": check_in,
            "check_out": check_out,
            "city": "flutter",
        })
        self.assertEqual(hotels_response.status_code, 200)
        self.assertEqual(
            hotels_response.headers["Access-Control-Allow-Origin"], "*"
        )
        hotel_result = hotels_response.get_json()["hotels"][0]
        self.assertTrue(hotel_result["slug"].startswith("flutter-api-hotel"))
        self.assertEqual(hotel_result["available_room_count"], 1)
        self.assertIn(hotel_id, hotel_result["cover_photo_url"])

        rooms_response = guest.get(
            f"/api/public/hotels/{hotel_result['slug']}/rooms",
            query_string={
                "check_in": check_in,
                "check_out": check_out,
            },
        )
        self.assertEqual(rooms_response.status_code, 200)
        room_result = rooms_response.get_json()["rooms"][0]
        self.assertEqual(room_result["type"], "API Suite")
        self.assertEqual(room_result["rate"], 75000)

        with patch.object(
            self.app_module, "send_reception_booking_email"
        ) as send_reception_email:
            response = guest.post(
                "/api/public/bookings",
                json={
                    "hotel_id": hotel_id,
                    "hotel_slug": hotel_result["slug"],
                    "room_number": room_result["number"],
                    "check_in": check_in,
                    "check_out": check_out,
                    "guest_name": "Flutter Guest",
                    "email": "flutter-guest@example.com",
                    "phone": "08000000000",
                },
            )
        self.assertEqual(response.status_code, 201)
        booking_result = response.get_json()["booking"]
        self.assertEqual(booking_result["hotel_name"], "Flutter API Hotel")
        self.assertEqual(booking_result["amount"], 75000)
        self.assertEqual(booking_result["bank_name"], "API Suite Bank")
        self.assertTrue(booking_result["whatsapp_url"].startswith("https://wa.me/"))
        whatsapp_message = parse_qs(
            urlparse(booking_result["whatsapp_url"]).query
        )["text"][0]
        self.assertIn("Booking reference:", whatsapp_message)
        self.assertIn("Flutter API Hotel", whatsapp_message)
        self.assertIn("Flutter Guest", whatsapp_message)
        self.assertIn("API Suite (", whatsapp_message)
        self.assertIn("Amount transferred: NGN 75,000", whatsapp_message)
        self.assertIn("verify the payment and confirm my booking", whatsapp_message)
        self.assertIn("attach receipt", whatsapp_message)
        send_reception_email.assert_called_once()

    def test_reference_booking_flow_is_at_book_and_flutter_pwa_at_book_app(self):
        with tempfile.TemporaryDirectory() as build_directory:
            build_path = Path(build_directory)
            (build_path / "index.html").write_text(
                '<base href="/"><link rel="manifest" href="manifest.json">',
                encoding="utf-8",
            )
            (build_path / "manifest.json").write_text(
                '{"start_url":"/","scope":"/"}',
                encoding="utf-8",
            )
            (build_path / "flutter_bootstrap.js").write_text(
                "window.flutterBootstrapLoaded = true;",
                encoding="utf-8",
            )
            client = self.app_module.app.test_client()
            with patch.object(
                self.app_module,
                "FLUTTER_WEB_BUILD_DIRECTORY",
                build_path,
            ):
                landing = client.get("/")
                self.assertEqual(landing.status_code, 200)
                self.assertIn(b'<base href="/">', landing.data)
                landing.close()

                admin_landing = client.get("/book.admin")
                self.assertEqual(admin_landing.status_code, 200)
                self.assertIn(b"HAIDWARE HOTEL BOOKING PLATFORM", admin_landing.data)
                self.assertIn(b"Hotel Manager? Register your hotel", admin_landing.data)
                admin_landing.close()

                trailing_slash = client.get(
                    "/book/?hotel=test-hotel",
                    follow_redirects=False,
                )
                self.assertEqual(trailing_slash.status_code, 308)
                self.assertEqual(
                    trailing_slash.headers["Location"],
                    "/?hotel=test-hotel",
                )

                hotel_home_redirect = client.get(
                    "/book?hotel=test-hotel",
                    follow_redirects=False,
                )
                self.assertEqual(hotel_home_redirect.status_code, 308)
                self.assertEqual(
                    hotel_home_redirect.headers["Location"],
                    "/?hotel=test-hotel",
                )

                app_slash = client.get(
                    "/book-app/?hotel=test-hotel",
                    follow_redirects=False,
                )
                self.assertEqual(app_slash.status_code, 308)
                self.assertEqual(
                    app_slash.headers["Location"],
                    "/book-app?hotel=test-hotel",
                )

                app_page = client.get("/book-app?hotel=test-hotel")
                self.assertEqual(app_page.status_code, 200)
                self.assertIn(b'<base href="/">', app_page.data)
                self.assertIn(b"hotel=test-hotel", app_page.request.query_string)
                app_page.close()

                manifest = client.get("/manifest.json")
                self.assertEqual(manifest.status_code, 200)
                self.assertIn(b'"start_url":"/"', manifest.data)
                manifest.close()

                bootstrap = client.get("/flutter_bootstrap.js")
                self.assertEqual(bootstrap.status_code, 200)
                self.assertIn(b"flutterBootstrapLoaded", bootstrap.data)
                bootstrap.close()

        legacy_page = client.get("/book-legacy")
        self.assertEqual(legacy_page.status_code, 200)

    def test_monthly_subscription_activates_only_after_paystack_verification(self):
        client = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            client, "Paid Plan Hotel", "paid-plan",
            "9 Market Road", "Lagos", "Lagos",
        )
        with self.app_module.app.app_context():
            self.app_module.get_db().execute(
                """UPDATE hotel_subscriptions SET plan = 'monthly',
                status = 'pending', pending_plan = 'monthly' WHERE hotel_id = ?""",
                (hotel_id,),
            )
            self.app_module.get_db().commit()
        self.assertEqual(client.get("/billing").status_code, 200)
        with client.session_transaction() as current_session:
            csrf_token = current_session["billing_csrf_token"]
        verification_amount = {"value": None}

        def paystack_mock(path, method="GET", payload=None):
            if path == "/transaction/initialize":
                self.assertEqual(payload["amount"], 8_000_000)
                self.assertEqual(payload["currency"], "NGN")
                return {"authorization_url": "https://checkout.paystack.com/example"}
            reference = path.rsplit("/", 1)[-1]
            with self.app_module.app.app_context():
                payment = self.app_module.get_db().execute(
                    "SELECT * FROM hotel_subscription_payments WHERE reference = ?",
                    (reference,),
                ).fetchone()
            return {
                "status": "success",
                "reference": reference,
                "amount": verification_amount["value"] or payment["amount"],
                "currency": "NGN",
                "id": 987654,
            }

        with patch.object(self.app_module, "paystack_request", side_effect=paystack_mock):
            response = client.post("/billing/subscribe", data={
                "csrf_token": csrf_token,
                "plan": "monthly",
            })
            self.assertEqual(response.status_code, 303)
            self.assertEqual(
                response.headers["Location"],
                "https://checkout.paystack.com/example",
            )
            with self.app_module.app.app_context():
                payment = self.app_module.get_db().execute(
                    """SELECT * FROM hotel_subscription_payments
                    WHERE hotel_id = ?""",
                    (hotel_id,),
                ).fetchone()
            self.assertEqual(payment["status"], "pending")
            reference = payment["reference"]
            verification_amount["value"] = payment["amount"] - 1
            rejected_callback = client.get(
                "/billing/paystack/callback?reference=" + reference
            )
            self.assertEqual(rejected_callback.status_code, 302)
            with self.app_module.app.app_context():
                payment = self.app_module.get_db().execute(
                    "SELECT status FROM hotel_subscription_payments WHERE reference = ?",
                    (reference,),
                ).fetchone()
            self.assertEqual(payment["status"], "pending")
            verification_amount["value"] = None
            callback = client.get(
                "/billing/paystack/callback?reference=" + reference
            )

        self.assertEqual(callback.status_code, 302)
        with self.app_module.app.app_context():
            payment = self.app_module.get_db().execute(
                "SELECT status FROM hotel_subscription_payments WHERE reference = ?",
                (reference,),
            ).fetchone()
            subscription = self.app_module.subscription_record(hotel_id)
            self.assertTrue(
                self.app_module.subscription_access(hotel_id)["allowed"]
            )
        self.assertEqual(payment["status"], "paid")
        self.assertEqual(subscription["status"], "active")

    def test_annual_subscription_uses_annual_price_and_term(self):
        client = self.app_module.app.test_client()
        hotel_id = self.register_hotel(
            client, "Annual Plan Hotel", "annual-plan",
            "10 Market Road", "Lagos", "Lagos",
        )
        with self.app_module.app.app_context():
            self.app_module.get_db().execute(
                """UPDATE hotel_subscriptions SET plan = 'annual',
                status = 'pending', pending_plan = 'annual' WHERE hotel_id = ?""",
                (hotel_id,),
            )
            self.app_module.get_db().commit()
        self.assertEqual(client.get("/billing").status_code, 200)
        with client.session_transaction() as current_session:
            csrf_token = current_session["billing_csrf_token"]

        def paystack_mock(path, method="GET", payload=None):
            if path == "/transaction/initialize":
                self.assertEqual(payload["amount"], 80_000_000)
                return {"authorization_url": "https://checkout.paystack.com/annual"}
            reference = path.rsplit("/", 1)[-1]
            with self.app_module.app.app_context():
                payment = self.app_module.get_db().execute(
                    "SELECT amount FROM hotel_subscription_payments WHERE reference = ?",
                    (reference,),
                ).fetchone()
            return {
                "status": "success",
                "reference": reference,
                "amount": payment["amount"],
                "currency": "NGN",
                "id": 987655,
            }

        with patch.object(self.app_module, "paystack_request", side_effect=paystack_mock):
            response = client.post("/billing/subscribe", data={
                "csrf_token": csrf_token,
                "plan": "annual",
            })
            self.assertEqual(response.status_code, 303)
            with self.app_module.app.app_context():
                reference = self.app_module.get_db().execute(
                    """SELECT reference FROM hotel_subscription_payments
                    WHERE hotel_id = ?""",
                    (hotel_id,),
                ).fetchone()["reference"]
            response = client.get(
                "/billing/paystack/callback?reference=" + reference
            )
        self.assertEqual(response.status_code, 302)
        with self.app_module.app.app_context():
            subscription = self.app_module.subscription_record(hotel_id)
            paid_until = self.app_module.datetime.fromisoformat(
                subscription["paid_until"]
            )
            now = self.app_module.datetime.now(self.app_module.timezone.utc)
            self.assertGreaterEqual((paid_until - now).days, 364)
            self.assertLessEqual((paid_until - now).days, 365)

    def test_paystack_webhook_requires_valid_signature(self):
        client = self.app_module.app.test_client()
        payload = b'{"event":"verification.ping","data":{}}'
        with patch.dict(
            self.app_module.os.environ,
            {"PAYSTACK_SECRET_KEY": "webhook-test-secret"},
        ):
            response = client.post(
                "/billing/paystack/webhook",
                data=payload,
                headers={"x-paystack-signature": "invalid"},
            )
            self.assertEqual(response.status_code, 401)
            signature = self.app_module.hmac.new(
                b"webhook-test-secret",
                payload,
                self.app_module.hashlib.sha512,
            ).hexdigest()
            response = client.post(
                "/billing/paystack/webhook",
                data=payload,
                headers={"x-paystack-signature": signature},
            )
        self.assertEqual(response.status_code, 200)

    def test_paystack_http_errors_include_provider_message(self):
        error = self.app_module.HTTPError(
            "https://api.paystack.co/transaction/initialize",
            403,
            "Forbidden",
            {},
            BytesIO(json.dumps({
                "status": False,
                "message": "Payment initialization is not permitted.",
                "code": "forbidden",
            }).encode("utf-8")),
        )
        with patch.dict(
            self.app_module.os.environ,
            {"PAYSTACK_SECRET_KEY": "sk_live_diagnostic"},
        ), patch.object(
            self.app_module, "urlopen", side_effect=error
        ) as mocked_urlopen:
            with self.assertRaisesRegex(
                ValueError,
                "Payment initialization is not permitted",
            ):
                self.app_module.paystack_request(
                    "/transaction/initialize",
                    "POST",
                    {"email": "manager@example.com"},
                )
        request_headers = {
            name.lower(): value
            for name, value in mocked_urlopen.call_args.args[0].header_items()
        }
        self.assertEqual(
            request_headers["user-agent"],
            "HAIDWARE-LabimBookingOS/1.0 "
            "(Paystack API client; Labim Booking OS)",
        )

    def test_paystack_cloudflare_block_error_is_reported(self):
        cloudflare_error = self.app_module.HTTPError(
            "https://api.paystack.co/transaction/initialize",
            403,
            "Forbidden",
            {},
            BytesIO(json.dumps({
                "type": "https://developers.cloudflare.com/support/",
                "title": "Error 1010: Access denied",
                "status": 403,
                "detail": "The site owner has blocked access based on your browser's signature.",
                "error_code": 1010,
                "error_name": "browser_signature_banned",
            }).encode("utf-8")),
        )
        with patch.dict(
            self.app_module.os.environ,
            {"PAYSTACK_SECRET_KEY": "sk_live_diagnostic"},
        ), patch.object(
            self.app_module, "urlopen", side_effect=cloudflare_error
        ):
            with self.assertRaisesRegex(
                ValueError,
                "1010.*browser_signature_banned",
            ):
                self.app_module.paystack_request(
                    "/transaction/initialize",
                    "POST",
                    {"email": "manager@example.com"},
                )

    def test_paid_signup_redirects_to_matching_paystack_checkout(self):
        for plan, amount in (("monthly", 8_000_000), ("annual", 80_000_000)):
            with self.subTest(plan=plan):
                client = self.app_module.app.test_client()
                suffix = f"signup-{plan}"

                def paystack_mock(path, method="GET", payload=None):
                    self.assertEqual(path, "/transaction/initialize")
                    self.assertEqual(payload["amount"], amount)
                    self.assertEqual(payload["email"], f"billing-{suffix}@example.com")
                    return {
                        "authorization_url":
                            f"https://checkout.paystack.com/{plan}"
                    }

                form_data = {
                    "hotel_name": f"Signup {plan.title()} Hotel",
                    "hotel_address": "11 Market Road",
                    "hotel_city": "Lagos",
                    "hotel_state": "Lagos",
                    "billing_email": f"billing-{suffix}@example.com",
                    "plan": plan,
                    "manager_username": f"manager-{suffix}",
                    "manager_password": "ManagerPass123!",
                    "director_username": f"director-{suffix}",
                    "director_password": "DirectorPass123!",
                    "reception_username": f"reception-{suffix}",
                    "reception_password": "ReceptionPass123!",
                }
                with patch.object(
                    self.app_module, "paystack_request",
                    side_effect=paystack_mock,
                ):
                    response = client.post("/signup/manager", data=form_data)
                self.assertEqual(response.status_code, 303)
                self.assertEqual(
                    response.headers["Location"],
                    f"https://checkout.paystack.com/{plan}",
                )
                with self.app_module.app.app_context():
                    subscription = self.app_module.get_db().execute(
                        """SELECT status, pending_plan, pending_reference
                        FROM hotel_subscriptions
                        WHERE billing_email = ?""",
                        (form_data["billing_email"],),
                    ).fetchone()
                    payment = self.app_module.get_db().execute(
                        """SELECT plan, amount, status
                        FROM hotel_subscription_payments WHERE reference = ?""",
                        (subscription["pending_reference"],),
                    ).fetchone()
                self.assertEqual(subscription["status"], "pending")
                self.assertEqual(subscription["pending_plan"], plan)
                self.assertEqual(payment["plan"], plan)
                self.assertEqual(payment["amount"], amount)
                self.assertEqual(payment["status"], "pending")

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
        hotel_directory = guest.get("/book-legacy")
        self.assertEqual(hotel_directory.status_code, 200)
        self.assertIn(b"Labim Test Hotel", hotel_directory.data)
        self.assertIn(b"Other Test Hotel", hotel_directory.data)
        self.assertIn(b"14 Independence Avenue", hotel_directory.data)
        self.assertIn(
            f"/book-legacy?hotel={hotel_two['slug']}".encode(),
            hotel_directory.data,
        )
        self.assertNotIn(b'<select name="hotel"', hotel_directory.data)
        filtered_directory = guest.get("/book-legacy", query_string={
            "state": "Enugu",
            "city": "enu",
        })
        self.assertEqual(filtered_directory.status_code, 200)
        self.assertIn(b"Other Test Hotel", filtered_directory.data)
        self.assertNotIn(b"Labim Test Hotel", filtered_directory.data)
        search = guest.get("/book-legacy", query_string={
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
        search = guest.get("/book-legacy", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertEqual(search.status_code, 200)
        self.assertIn(b"Other Test Hotel", search.data)
        self.assertIn(b"Suite", search.data)
        self.assertIn(b"Photo 1 of Room 101", search.data)
        self.assertIn(b"Photo 2 of Room 101", search.data)

        price_filtered_directory = guest.get("/book-legacy", query_string={
            "check_in": stay_start,
            "check_out": stay_end,
            "price_range": "50000-100000",
        })
        self.assertEqual(price_filtered_directory.status_code, 200)
        self.assertIn(b"Other Test Hotel", price_filtered_directory.data)
        self.assertIn(b"1 available room from", price_filtered_directory.data)
        self.assertNotIn(b"Labim Test Hotel", price_filtered_directory.data)

        price_filtered_search = guest.get("/book-legacy", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
            "price_range": "100000-200000",
        })
        self.assertEqual(price_filtered_search.status_code, 200)
        self.assertIn(b"No listed rooms available", price_filtered_search.data)

        with guest.session_transaction() as guest_session:
            csrf_token = guest_session["public_booking_csrf"]

        with patch.object(
            self.app_module,
            "send_reception_booking_email",
        ) as send_reception_email:
            send_reception_email.return_value = None
            response = guest.post("/book-legacy", data={
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
            room_after_confirmation = self.app_module.get_db().execute(
                "SELECT status FROM rooms WHERE hotel_id = ? AND number = '101'",
                (hotel_two_id,),
            ).fetchone()
            payment = self.app_module.get_db().execute(
                "SELECT hotel_id, amount FROM payments WHERE reservation_id = ?",
                (booking["id"],),
            ).fetchone()
            self.assertEqual(confirmed["status"], "booked")
            self.assertEqual(confirmed["amount_paid"], 90000)
            self.assertEqual(room_after_confirmation["status"], "available")
            self.assertEqual(payment["hotel_id"], hotel_two_id)
            self.assertEqual(payment["amount"], 90000)

        with self.app_module.app.app_context():
            future_room = self.app_module.reference_rooms(
                hotel_id=hotel_two_id,
                as_of_date=date.fromisoformat(stay_start),
            )[0]
        self.assertEqual(future_room["status"], "Booked")
        self.assertEqual(future_room["guest"], "Guest Two")

        manager_dashboard = hotel_two_manager.get("/workspace/manager/dashboard")
        self.assertEqual(manager_dashboard.status_code, 200)
        self.assertIn(b"Available", manager_dashboard.data)

        response = reception.post("/rooms/101/status", data={
            "status": "cleaning",
            "reference": "true",
        })
        self.assertEqual(response.status_code, 302)
        manager_dashboard = hotel_two_manager.get("/workspace/manager/dashboard")
        self.assertIn(b"Cleaning", manager_dashboard.data)
        with self.app_module.app.app_context():
            future_room = self.app_module.reference_rooms(
                hotel_id=hotel_two_id,
                as_of_date=date.fromisoformat(stay_start),
            )[0]
        self.assertEqual(future_room["status"], "Cleaning")
        with self.app_module.app.app_context():
            self.assertEqual(
                self.app_module.get_db().execute(
                    "SELECT status FROM rooms WHERE hotel_id = ? AND number = '101'",
                    (hotel_two_id,),
                ).fetchone()["status"],
                "cleaning",
            )

        hotel_two_availability = guest.get("/book-legacy", query_string={
            "hotel": hotel_two["slug"],
            "check_in": stay_start,
            "check_out": stay_end,
        })
        self.assertIn(b"No listed rooms available", hotel_two_availability.data)
        with self.app_module.app.app_context():
            hotel_one = self.app_module.hotel_details(hotel_one_id)
        hotel_one_availability = guest.get("/book-legacy", query_string={
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
        hotel_one_availability = guest.get("/book-legacy", query_string={
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
