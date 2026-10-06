-- Run once on projects that already ran the old sample-room seed script.
-- Rooms with reservation or payment history are deliberately retained.
delete from public.rooms r
where (r.number, r.name, r.beds, r.rate) in (
  ('101', 'Standard', 1, 45000),
  ('102', 'Standard', 1, 45000),
  ('103', 'Deluxe', 2, 60000),
  ('104', 'Deluxe', 2, 60000),
  ('105', 'Suite', 3, 85000),
  ('106', 'Standard', 1, 45000),
  ('201', 'Standard', 1, 45000),
  ('202', 'Deluxe', 2, 60000),
  ('203', 'Suite', 3, 85000),
  ('204', 'Standard', 1, 45000),
  ('205', 'Standard', 1, 45000),
  ('206', 'Deluxe', 2, 60000)
)
and not exists (
  select 1 from public.reservations reservation
  where reservation.room_number = r.number
)
and not exists (
  select 1 from public.payments payment
  where payment.room_number = r.number
);
