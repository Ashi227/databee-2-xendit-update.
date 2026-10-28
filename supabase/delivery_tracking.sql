-- DataBee: delivery tracking for the Orders screen.
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to run more than once. It only ADDS optional columns to public.orders.

alter table public.orders add column if not exists delivery_status text default 'PROCESSING';
alter table public.orders add column if not exists tracking_number text;
alter table public.orders add column if not exists shipped_at timestamptz;
alter table public.orders add column if not exists delivered_at timestamptz;

-- How the app reads these (payment status comes from the existing "status" column):
--   status = PENDING                         -> To pay
--   status = PAID/SETTLED, delivery_status = PROCESSING   -> To ship
--   delivery_status = SHIPPED / OUT_FOR_DELIVERY          -> To receive
--   delivery_status = DELIVERED                           -> Completed
--   status = EXPIRED/FAILED, or delivery_status = CANCELLED -> Cancelled

-- When you hand a parcel to the courier (replace the id):
-- update public.orders
--   set delivery_status = 'SHIPPED', tracking_number = 'JT1234567890', shipped_at = now()
--   where id = 'ORDER-ID-HERE';

-- When it arrives:
-- update public.orders
--   set delivery_status = 'DELIVERED', delivered_at = now()
--   where id = 'ORDER-ID-HERE';

-- If a purchase never shows up in the app, check that the order row exists
-- and that its owner column matches the buyer:
-- select * from public.orders order by created_at desc limit 5;
