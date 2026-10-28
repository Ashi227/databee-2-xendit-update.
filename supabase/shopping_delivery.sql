-- DataBee shopping cart, COD/Xendit orders, and controlled seller/rider workflow.
-- Additive migration: this keeps existing products, addresses, favorites, and orders.
-- Run in Supabase Dashboard > SQL Editor after schema.sql (and delivery_tracking.sql).
-- Assign trusted app_metadata.role values ("admin" or "rider") through an
-- administrator-controlled server process; never grant roles from user_metadata.

alter table public.delivery_addresses
  add column if not exists label text not null default 'Home';

insert into public.delivery_addresses (
  id, user_id, label, recipient_name, phone, street, barangay, city,
  province, postal_code, is_default
)
select
  md5(
    u.id::text || ':' ||
      coalesce(nullif(saved_address ->> 'id', ''), saved_address::text)
  )::uuid,
  u.id,
  coalesce(nullif(saved_address ->> 'label', ''), 'Home'),
  saved_address ->> 'full_name',
  saved_address ->> 'phone',
  saved_address ->> 'street',
  saved_address ->> 'barangay',
  saved_address ->> 'city',
  saved_address ->> 'province',
  saved_address ->> 'postal_code',
  saved_address -> 'is_default' = 'true'::jsonb
from auth.users u
cross join lateral jsonb_array_elements(
  case
    when jsonb_typeof(u.raw_user_meta_data -> 'delivery_addresses') = 'array'
      then u.raw_user_meta_data -> 'delivery_addresses'
    else '[]'::jsonb
  end
) as address_rows(saved_address)
where coalesce(trim(saved_address ->> 'full_name'), '') <> ''
  and coalesce(trim(saved_address ->> 'phone'), '') <> ''
  and coalesce(trim(saved_address ->> 'street'), '') <> ''
  and coalesce(trim(saved_address ->> 'barangay'), '') <> ''
  and coalesce(trim(saved_address ->> 'city'), '') <> ''
  and coalesce(trim(saved_address ->> 'province'), '') <> ''
  and coalesce(trim(saved_address ->> 'postal_code'), '') <> ''
on conflict (id) do nothing;

create table if not exists public.cart_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text references public.products(id) on delete set null,
  product_name text not null,
  image_url text not null default '',
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0)
);

alter table public.orders
  add column if not exists subtotal numeric(12,2) not null default 0,
  add column if not exists delivery_fee numeric(12,2) not null default 0,
  add column if not exists payment_method text,
  add column if not exists payment_status text,
  add column if not exists delivery_address jsonb,
  add column if not exists rider_id uuid references auth.users(id) on delete set null,
  add column if not exists confirmed_at timestamptz,
  add column if not exists ready_for_pickup_at timestamptz,
  add column if not exists out_for_delivery_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists checkout_key text,
  add column if not exists invoice_url text,
  add column if not exists stock_reserved boolean not null default false,
  add column if not exists delivery_status text default 'PENDING_CONFIRMATION',
  add column if not exists tracking_number text,
  add column if not exists shipped_at timestamptz,
  add column if not exists delivered_at timestamptz;

create unique index if not exists orders_user_checkout_key_unique
  on public.orders(user_id, checkout_key)
  where checkout_key is not null;

update public.orders
set payment_status = status
where payment_status is null;

alter table public.orders alter column payment_status set default 'PENDING';
alter table public.orders alter column delivery_status
  set default 'PENDING_CONFIRMATION';

create or replace function public.create_xendit_order(
  p_user_id uuid,
  p_items jsonb,
  p_delivery_address jsonb,
  p_checkout_key text,
  p_external_id text,
  p_invoice_url text,
  p_expected_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_order_id uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_quantity integer;
  v_subtotal numeric(12,2) := 0;
  v_total_quantity integer := 0;
  v_first_product_id text;
  v_first_product_name text;
  v_delivery_fee constant numeric(12,2) := 150;
begin
  if p_user_id is null
     or coalesce(trim(p_checkout_key), '') = ''
     or coalesce(trim(p_external_id), '') = ''
     or coalesce(p_invoice_url, '') not like 'https://%' then
    raise exception 'Invalid Xendit order details.';
  end if;

  select * into v_order
  from public.orders
  where user_id = p_user_id and checkout_key = p_checkout_key
  for update;
  if found then
    if v_order.invoice_url is null then
      raise exception 'An order already exists for this checkout key.';
    end if;
    return jsonb_build_object(
      'invoice_url', v_order.invoice_url,
      'external_id', v_order.external_id
    );
  end if;

  if p_items is null
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 100 then
    raise exception 'Your cart is empty or invalid.';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) as parsed_items(item)
    group by item ->> 'product_id'
    having count(*) > 1
  ) then
    raise exception 'Duplicate products are not allowed in checkout.';
  end if;
  if lower(trim(coalesce(p_delivery_address ->> 'full_name', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'phone'), '') = ''
     or length(regexp_replace(p_delivery_address ->> 'phone', '[^0-9]', '', 'g')) < 7
     or lower(trim(coalesce(p_delivery_address ->> 'street', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'barangay', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'city', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'province', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'postal_code'), '') !~ '^[0-9]{4,6}$' then
    raise exception 'A valid delivery address is required.';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item ->> 'product_id', '') = ''
       or coalesce(v_item ->> 'quantity', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid product or quantity.';
    end if;
    v_quantity := (v_item ->> 'quantity')::integer;
    select * into v_product
    from public.products
    where id = v_item ->> 'product_id' and is_active = true
    for update;
    if not found or v_product.stock < v_quantity then
      raise exception 'A product is unavailable or has insufficient stock.';
    end if;

    update public.products
    set stock = stock - v_quantity
    where id = v_product.id;
    if v_first_product_id is null then
      v_first_product_id := v_product.id;
      v_first_product_name := v_product.name;
    end if;
    v_subtotal := v_subtotal + v_product.price * v_quantity;
    v_total_quantity := v_total_quantity + v_quantity;
  end loop;

  if round(v_subtotal + v_delivery_fee, 2) <> p_expected_amount then
    raise exception 'The invoice amount does not match the current cart total.';
  end if;

  insert into public.orders (
    user_id, product_id, product_name, amount, subtotal, delivery_fee,
    quantity, status, payment_status, payment_method, delivery_status,
    delivery_address, checkout_key, external_id, invoice_url, stock_reserved
  )
  values (
    p_user_id, v_first_product_id, v_first_product_name,
    v_subtotal + v_delivery_fee, v_subtotal, v_delivery_fee,
    v_total_quantity, 'PENDING', 'PENDING', 'XENDIT',
    'PENDING_CONFIRMATION', p_delivery_address, p_checkout_key,
    p_external_id, p_invoice_url, true
  )
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select * into v_product
    from public.products
    where id = v_item ->> 'product_id';
    insert into public.order_items (
      order_id, product_id, product_name, image_url, unit_price, quantity
    )
    values (
      v_order_id, v_product.id, v_product.name, v_product.image_url,
      v_product.price, (v_item ->> 'quantity')::integer
    );
  end loop;

  return jsonb_build_object(
    'invoice_url', p_invoice_url,
    'external_id', p_external_id
  );
end;
$$;

create or replace function public.finalize_xendit_order(
  p_external_id text,
  p_payment_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if p_payment_status is null
     or p_payment_status not in ('PAID', 'SETTLED', 'EXPIRED', 'FAILED') then
    raise exception 'Unsupported Xendit payment status.';
  end if;

  select * into v_order
  from public.orders
  where external_id = p_external_id and payment_method = 'XENDIT'
  for update;
  if not found then
    raise exception 'Xendit order not found.';
  end if;

  if v_order.status in ('CANCELLED', 'EXPIRED', 'FAILED') then
    return;
  end if;
  if v_order.status in ('PAID', 'SETTLED')
     and p_payment_status not in ('PAID', 'SETTLED') then
    return;
  end if;
  if p_payment_status in ('PAID', 'SETTLED') then
    update public.orders
    set status = p_payment_status,
        payment_status = p_payment_status,
        stock_reserved = false
    where id = v_order.id;
  else
    if v_order.stock_reserved then
      update public.products p
      set stock = p.stock + items.quantity
      from public.order_items items
      where items.order_id = v_order.id
        and items.product_id = p.id;
    end if;
    update public.orders
    set status = p_payment_status,
        payment_status = p_payment_status,
        stock_reserved = false
    where id = v_order.id;
  end if;
end;
$$;

revoke all on function public.create_xendit_order(
  uuid, jsonb, jsonb, text, text, text, numeric
) from public, anon, authenticated;
grant execute on function public.create_xendit_order(
  uuid, jsonb, jsonb, text, text, text, numeric
) to service_role;
revoke all on function public.finalize_xendit_order(text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_xendit_order(text, text)
  to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.orders;
  end if;
exception
  when duplicate_object then null;
end;
$$;

alter table public.cart_items enable row level security;
alter table public.order_items enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Users manage their own cart" on public.cart_items;
create policy "Users manage their own cart"
  on public.cart_items for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Owners and staff read order items" on public.order_items;
create policy "Owners and staff read order items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1
      from public.orders o
      where o.id = order_id
        and (
          o.user_id = auth.uid()
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'rider')
        )
    )
  );

drop policy if exists "Staff can read orders" on public.orders;
create policy "Staff can read orders"
  on public.orders for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'rider')
  );

create or replace function public.save_cart_items(p_items jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_product public.products%rowtype;
  v_quantity integer;
begin
  if v_user_id is null then
    raise exception 'Sign in before saving your cart.';
  end if;
  if p_items is null or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Invalid cart data.';
  end if;

  perform 1 from auth.users where id = v_user_id for update;
  delete from public.cart_items where user_id = v_user_id;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item ->> 'product_id', '') = ''
       or coalesce(v_item ->> 'quantity', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid product or cart quantity.';
    end if;
    v_quantity := (v_item ->> 'quantity')::integer;
    select * into v_product
    from public.products
    where id = v_item ->> 'product_id' and is_active = true;
    if not found or v_quantity > v_product.stock then
      raise exception 'A cart item is unavailable or exceeds current stock.';
    end if;

    insert into public.cart_items (user_id, product_id, quantity, updated_at)
    values (v_user_id, v_product.id, v_quantity, now());
  end loop;
end;
$$;

create or replace function public.create_cod_order(
  p_items jsonb,
  p_delivery_address jsonb,
  p_delivery_fee numeric default 150,
  p_checkout_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_order_id uuid;
  v_item jsonb;
  v_product public.products%rowtype;
  v_quantity integer;
  v_subtotal numeric(12,2) := 0;
  v_total_quantity integer := 0;
  v_first_product_id text;
  v_first_product_name text;
begin
  if v_user_id is null then
    raise exception 'Sign in before placing an order.';
  end if;
  if coalesce(trim(p_checkout_key), '') = '' then
    raise exception 'A valid checkout key is required.';
  end if;
  select id into v_order_id
  from public.orders
  where user_id = v_user_id and checkout_key = p_checkout_key;
  if found then
    return v_order_id;
  end if;
  if p_items is null
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty.';
  end if;
  if p_delivery_fee < 0 then
    raise exception 'Delivery fee cannot be negative.';
  end if;
  if lower(trim(coalesce(p_delivery_address ->> 'full_name', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'phone'), '') = ''
     or length(regexp_replace(p_delivery_address ->> 'phone', '[^0-9]', '', 'g')) < 7
     or lower(trim(coalesce(p_delivery_address ->> 'street', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'barangay', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'city', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'province', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'postal_code'), '') !~ '^[0-9]{4,6}$' then
    raise exception 'A valid delivery address is required.';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item ->> 'product_id', '') = ''
       or coalesce(v_item ->> 'quantity', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid product or quantity.';
    end if;
    v_quantity := (v_item ->> 'quantity')::integer;

    select * into v_product
    from public.products
    where id = v_item ->> 'product_id'
      and is_active = true
    for update;
    if not found or v_product.stock < v_quantity then
      raise exception 'A product is unavailable or has insufficient stock.';
    end if;

    update public.products
    set stock = stock - v_quantity
    where id = v_product.id;

    if v_first_product_id is null then
      v_first_product_id := v_product.id;
      v_first_product_name := v_product.name;
    end if;
    v_subtotal := v_subtotal + v_product.price * v_quantity;
    v_total_quantity := v_total_quantity + v_quantity;
  end loop;

  insert into public.orders (
    user_id, product_id, product_name, amount, subtotal, delivery_fee,
    quantity, status, payment_status, payment_method, delivery_status,
    delivery_address, checkout_key
  )
  values (
    v_user_id, v_first_product_id, v_first_product_name,
    v_subtotal + p_delivery_fee, v_subtotal, p_delivery_fee,
    v_total_quantity, 'PENDING', 'DUE_ON_DELIVERY', 'COD',
    'PENDING_CONFIRMATION', p_delivery_address, p_checkout_key
  )
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select * into v_product from public.products
    where id = v_item ->> 'product_id';

    insert into public.order_items (
      order_id, product_id, product_name, image_url, unit_price, quantity
    )
    values (
      v_order_id, v_product.id, v_product.name, v_product.image_url,
      v_product.price, (v_item ->> 'quantity')::integer
    );

    delete from public.cart_items
    where user_id = v_user_id and product_id = v_product.id;
  end loop;

  return v_order_id;
end;
$$;

create or replace function public.attach_invoice_delivery(
  p_external_id text,
  p_product_id text,
  p_quantity integer,
  p_delivery_address jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_order public.orders%rowtype;
  v_product public.products%rowtype;
  v_subtotal numeric(12,2);
begin
  if v_user_id is null then
    raise exception 'Sign in before completing checkout.';
  end if;
  if coalesce(trim(p_external_id), '') = ''
     or p_quantity is null
     or p_quantity < 1 then
    raise exception 'Invalid payment order details.';
  end if;
  if lower(trim(coalesce(p_delivery_address ->> 'full_name', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'phone'), '') = ''
     or length(regexp_replace(p_delivery_address ->> 'phone', '[^0-9]', '', 'g')) < 7
     or lower(trim(coalesce(p_delivery_address ->> 'street', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'barangay', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'city', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or lower(trim(coalesce(p_delivery_address ->> 'province', ''))) in
       ('', 'test', 'placeholder', 'n/a', 'na', 'none', '-')
     or coalesce(trim(p_delivery_address ->> 'postal_code'), '') !~ '^[0-9]{4,6}$' then
    raise exception 'A valid delivery address is required.';
  end if;

  select * into v_order
  from public.orders
  where external_id = p_external_id and user_id = v_user_id
  for update;
  if not found or v_order.product_id is distinct from p_product_id then
    raise exception 'The payment order could not be verified.';
  end if;

  select * into v_product
  from public.products
  where id = p_product_id;
  if not found then
    raise exception 'The ordered product could not be found.';
  end if;

  v_subtotal := v_product.price * p_quantity;
  update public.orders
  set payment_method = 'XENDIT',
      delivery_address = p_delivery_address,
      subtotal = v_subtotal,
      delivery_fee = greatest(amount - v_subtotal, 0),
      quantity = p_quantity
  where id = v_order.id;

  if not exists (
    select 1 from public.order_items where order_id = v_order.id
  ) then
    insert into public.order_items (
      order_id, product_id, product_name, image_url, unit_price, quantity
    )
    values (
      v_order.id, v_product.id, v_product.name, v_product.image_url,
      v_product.price, p_quantity
    );
  end if;
end;
$$;

create or replace function public.transition_order(
  p_order_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if auth.uid() is null then
    raise exception 'Sign in before updating an order.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then
    raise exception 'Order was not found.';
  end if;

  if p_action in ('confirm', 'reject', 'ready_for_pickup') then
    if v_role <> 'admin' then
      raise exception 'Only an authorized seller can perform this action.';
    end if;
    if p_action = 'confirm'
       and v_order.payment_method = 'XENDIT'
       and v_order.payment_status not in ('PAID', 'SETTLED') then
      raise exception 'An Xendit order must be paid before confirmation.';
    end if;
    if p_action = 'confirm' and v_order.delivery_status = 'PENDING_CONFIRMATION' then
      update public.orders
      set delivery_status = 'TO_SHIP', status = 'CONFIRMED', confirmed_at = now()
      where id = p_order_id;
    elsif p_action = 'reject' and v_order.delivery_status = 'PENDING_CONFIRMATION' then
      if v_order.payment_method = 'XENDIT'
         and v_order.payment_status not in ('FAILED', 'EXPIRED') then
        raise exception 'An Xendit order must be refunded or expire before rejection.';
      end if;
      update public.products p
      set stock = p.stock + oi.quantity
      from public.order_items oi
      where oi.order_id = p_order_id
        and oi.product_id = p.id
        and v_order.payment_method <> 'XENDIT';
      update public.orders
      set delivery_status = 'CANCELLED', status = 'CANCELLED', cancelled_at = now()
      where id = p_order_id;
    elsif p_action = 'ready_for_pickup' and v_order.delivery_status = 'TO_SHIP' then
      update public.orders
      set delivery_status = 'READY_FOR_PICKUP', ready_for_pickup_at = now()
      where id = p_order_id;
    else
      raise exception 'Invalid seller order status transition.';
    end if;
  elsif p_action = 'accept_delivery' then
    if v_role <> 'rider' then
      raise exception 'Only an authorized rider can accept a delivery.';
    end if;
    if v_order.delivery_status <> 'READY_FOR_PICKUP' or v_order.rider_id is not null then
      raise exception 'This delivery is not available for assignment.';
    end if;
    update public.orders
    set rider_id = auth.uid(),
        delivery_status = 'OUT_FOR_DELIVERY',
        out_for_delivery_at = now(),
        shipped_at = now()
    where id = p_order_id;
  elsif p_action = 'mark_delivered' then
    if v_role <> 'rider'
       or v_order.rider_id is distinct from auth.uid()
       or v_order.delivery_status <> 'OUT_FOR_DELIVERY' then
      raise exception 'Only the assigned rider can complete an active delivery.';
    end if;
    update public.orders
    set delivery_status = 'DELIVERED', delivered_at = now()
    where id = p_order_id;
  elsif p_action = 'cancel' then
    if v_order.user_id <> auth.uid()
       or v_order.delivery_status <> 'PENDING_CONFIRMATION'
       or (
         v_order.payment_method = 'XENDIT'
         and v_order.payment_status not in ('FAILED', 'EXPIRED')
       ) then
      raise exception 'This order can no longer be cancelled.';
    end if;
    update public.products p
    set stock = p.stock + oi.quantity
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.product_id = p.id
      and v_order.payment_method <> 'XENDIT';
    update public.orders
    set delivery_status = 'CANCELLED', status = 'CANCELLED', cancelled_at = now()
    where id = p_order_id;
  else
    raise exception 'Unsupported order action.';
  end if;
end;
$$;

revoke all on function public.create_cod_order(jsonb, jsonb, numeric, text) from public;
grant execute on function public.create_cod_order(jsonb, jsonb, numeric, text) to authenticated;
revoke all on function public.save_cart_items(jsonb) from public;
grant execute on function public.save_cart_items(jsonb) to authenticated;
revoke all on function public.attach_invoice_delivery(text, text, integer, jsonb) from public;
grant execute on function public.attach_invoice_delivery(text, text, integer, jsonb) to authenticated;
revoke all on function public.transition_order(uuid, text) from public;
grant execute on function public.transition_order(uuid, text) to authenticated;

notify pgrst, 'reload schema';
