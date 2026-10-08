begin;

create table if not exists public.hotel_subscriptions (
  hotel_id uuid primary key references public.hotels(id) on delete cascade,
  plan text not null check (plan in ('legacy', 'trial', 'monthly', 'annual')),
  status text not null check (status in ('legacy', 'trial', 'pending', 'active')),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  paid_until timestamptz,
  billing_email text not null default '',
  pending_reference text,
  pending_plan text check (pending_plan is null or pending_plan in ('monthly', 'annual')),
  updated_at timestamptz not null default now()
);

create table if not exists public.hotel_subscription_payments (
  reference text primary key,
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  plan text not null check (plan in ('monthly', 'annual')),
  amount bigint not null check (amount > 0),
  status text not null check (status in ('pending', 'failed', 'paid')),
  paystack_transaction_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

alter table public.hotel_subscriptions enable row level security;
alter table public.hotel_subscription_payments enable row level security;

insert into public.hotel_subscriptions (hotel_id, plan, status, updated_at)
select id, 'legacy', 'legacy', now()
from public.hotels
on conflict (hotel_id) do nothing;

create or replace function public.activate_hotel_subscription_payment(
  p_reference text,
  p_transaction_id text,
  p_amount bigint,
  p_currency text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  payment_row public.hotel_subscription_payments%rowtype;
  subscription_row public.hotel_subscriptions%rowtype;
  activation_start timestamptz;
  activation_expiry timestamptz;
  expected_amount bigint;
  activation_days integer;
begin
  if coalesce(p_reference, '') = '' or coalesce(p_transaction_id, '') = '' then
    raise exception 'Payment reference and transaction id are required';
  end if;

  select * into payment_row
  from public.hotel_subscription_payments
  where reference = p_reference
  for update;

  if not found then
    raise exception 'No subscription payment exists for this reference';
  end if;

  if payment_row.status = 'paid' then
    if payment_row.paystack_transaction_id = p_transaction_id then
      return jsonb_build_object('ok', true, 'already_paid', true);
    end if;
    raise exception 'Subscription reference was paid by a different transaction';
  end if;

  expected_amount := case payment_row.plan
    when 'monthly' then 8000000
    when 'annual' then 80000000
    else null
  end;
  if payment_row.status <> 'pending'
    or p_currency <> 'NGN'
    or p_amount <> payment_row.amount
    or p_amount <> expected_amount then
    raise exception 'Paystack payment does not match the pending subscription';
  end if;

  select * into subscription_row
  from public.hotel_subscriptions
  where hotel_id = payment_row.hotel_id
  for update;

  if not found then
    raise exception 'Hotel subscription record could not be found';
  end if;

  activation_start := greatest(now(), coalesce(subscription_row.paid_until, now()));
  activation_days := case payment_row.plan when 'monthly' then 30 else 365 end;
  activation_expiry := activation_start + make_interval(days => activation_days);

  update public.hotel_subscription_payments
  set status = 'paid',
      paystack_transaction_id = p_transaction_id,
      paid_at = now()
  where reference = p_reference;

  update public.hotel_subscriptions
  set plan = payment_row.plan,
      status = 'active',
      paid_until = activation_expiry,
  pending_reference = case
    when pending_reference = p_reference then null else pending_reference end,
  pending_plan = case
    when pending_reference = p_reference then null else pending_plan end,
  updated_at = now()
  where hotel_id = payment_row.hotel_id;

  return jsonb_build_object('ok', true, 'paid_until', activation_expiry);
end;
$$;

revoke all on function public.activate_hotel_subscription_payment(text, text, bigint, text)
  from public, anon, authenticated;
grant execute on function public.activate_hotel_subscription_payment(text, text, bigint, text)
  to service_role;

commit;
