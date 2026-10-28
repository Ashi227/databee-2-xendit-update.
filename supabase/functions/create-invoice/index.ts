import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isValidAddress(address: Record<string, unknown>) {
  const required = [
    "full_name",
    "street",
    "barangay",
    "city",
    "province",
  ];
  if (
    required.some((key) => {
      const value = address[key];
      return typeof value !== "string" ||
        ["", "test", "placeholder", "n/a", "na", "none", "-"].includes(
          value.trim().toLowerCase(),
        );
    })
  ) {
    return false;
  }
  const phone = typeof address.phone === "string" ? address.phone : "";
  const postalCode = typeof address.postal_code === "string"
    ? address.postal_code.trim()
    : "";
  return phone.replace(/\D/g, "").length >= 7 &&
    /^\d{4,6}$/.test(postalCode);
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond(405, { error: "Method not allowed." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return respond(401, { error: "Sign in before starting checkout." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey =
    Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const xenditSecretKey = Deno.env.get("XENDIT_SECRET_KEY");
  if (!supabaseUrl || !publishableKey || !serviceRoleKey || !xenditSecretKey) {
    console.error("One or more required checkout secrets are not configured.");
    return respond(500, { error: "Checkout is not configured on the server." });
  }

  try {
    const token = authorization.slice("Bearer ".length);
    const authClient = createClient(supabaseUrl, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userResult, error: authError } =
      await authClient.auth.getUser(token);
    if (authError || !userResult.user) {
      return respond(401, { error: "Your session is invalid. Sign in again." });
    }

    const body = await request.json();
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return respond(400, { error: "Invalid checkout request." });
    }
    const isCartCheckout = typeof body.checkout_key === "string";
    const checkoutKey = isCartCheckout ? body.checkout_key.trim() : null;
    if (
      isCartCheckout &&
      (!/^[A-Za-z0-9._:-]{1,128}$/.test(checkoutKey ?? "") ||
        !body.delivery_address ||
        typeof body.delivery_address !== "object" ||
        Array.isArray(body.delivery_address) ||
        !isValidAddress(body.delivery_address))
    ) {
      return respond(400, {
        error: "A valid checkout key and delivery address are required.",
      });
    }

    const items = body.items;
    if (!Array.isArray(items) || items.length === 0 || items.length > 100) {
      return respond(400, { error: "Your cart is empty or invalid." });
    }
    const itemMap = new Map<string, number>();
    for (const item of items) {
      if (
        item === null ||
        typeof item !== "object" ||
        typeof item.product_id !== "string" ||
        item.product_id.trim() === "" ||
        !Number.isSafeInteger(item.quantity) ||
        item.quantity < 1
      ) {
        return respond(400, {
          error: "A valid product and quantity are required.",
        });
      }
      if (itemMap.has(item.product_id)) {
        return respond(400, {
          error: "Duplicate products are not allowed in checkout.",
        });
      }
      itemMap.set(item.product_id.trim(), item.quantity);
    }
    const validatedItems = [...itemMap].map(([product_id, quantity]) => ({
      product_id,
      quantity,
    }));

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (isCartCheckout) {
      const { data: existingOrder, error: existingOrderError } =
        await adminClient
          .from("orders")
          .select("external_id, invoice_url")
          .eq("user_id", userResult.user.id)
          .eq("checkout_key", checkoutKey)
          .maybeSingle();
      if (existingOrderError) throw existingOrderError;
      if (existingOrder?.invoice_url && existingOrder.external_id) {
        return respond(200, {
          invoice_url: existingOrder.invoice_url,
          external_id: existingOrder.external_id,
        });
      }
    }

    const productIds = [...itemMap.keys()];
    const { data: products, error: productsError } = await adminClient
      .from("products")
      .select("id, name, price, stock, image_url, is_active")
      .in("id", productIds);
    if (productsError) {
      console.error("Could not load checkout products:", productsError.message);
      return respond(500, { error: "Could not verify product availability." });
    }
    const productsById = new Map(
      (products ?? []).map((product) => [product.id, product]),
    );
    if (productsById.size !== itemMap.size) {
      return respond(404, { error: "A product is no longer available." });
    }

    let subtotal = 0;
    let totalQuantity = 0;
    const invoiceLines: string[] = [];
    for (const [productId, quantity] of itemMap) {
      const product = productsById.get(productId);
      if (!product || !product.is_active) {
        return respond(404, { error: "A product is no longer available." });
      }
      if (quantity > product.stock) {
        return respond(409, {
          error: `${product.name} does not have enough stock.`,
        });
      }
      const price = Number(product.price);
      if (!Number.isFinite(price) || price <= 0) {
        return respond(400, { error: `${product.name} has an invalid price.` });
      }
      subtotal += price * quantity;
      totalQuantity += quantity;
      invoiceLines.push(`${product.name} × ${quantity}`);
    }
    subtotal = Math.round(subtotal * 100) / 100;
    const deliveryFee = isCartCheckout ? 150 : 0;
    const amount = Math.round((subtotal + deliveryFee) * 100) / 100;
    if (!Number.isFinite(amount) || amount <= 0) {
      return respond(400, { error: "The checkout has an invalid total." });
    }

    const externalId = `databee-${crypto.randomUUID()}`;
    const idempotencyKey = isCartCheckout
      ? `${userResult.user.id}:${checkoutKey}`
      : externalId;
    const xenditResponse = await fetch("https://api.xendit.co/v2/invoices", {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${xenditSecretKey}:`)}`,
        "Content-Type": "application/json",
        "Idempotency-key": idempotencyKey,
      },
      body: JSON.stringify({
        external_id: externalId,
        amount,
        currency: "PHP",
        payer_email: userResult.user.email,
        description: invoiceLines.join(", ").slice(0, 250),
        invoice_duration: 86400,
      }),
    });
    const invoice = await xenditResponse.json();
    if (!xenditResponse.ok) {
      console.error("Xendit invoice request failed:", invoice);
      return respond(502, {
        error: "Xendit could not create the invoice. Check server credentials.",
      });
    }
    if (
      typeof invoice.invoice_url !== "string" ||
      typeof invoice.external_id !== "string"
    ) {
      console.error("Xendit response omitted invoice details:", invoice);
      return respond(502, { error: "Xendit returned an invalid invoice." });
    }

    if (isCartCheckout) {
      const { data: savedOrder, error: saveOrderError } = await adminClient.rpc(
        "create_xendit_order",
        {
          p_user_id: userResult.user.id,
          p_items: validatedItems,
          p_delivery_address: body.delivery_address,
          p_checkout_key: checkoutKey,
          p_external_id: invoice.external_id,
          p_invoice_url: invoice.invoice_url,
          p_expected_amount: amount,
        },
      );
      if (saveOrderError) {
        const { data: retriedOrder, error: retryLookupError } = await adminClient
          .from("orders")
          .select("external_id, invoice_url")
          .eq("user_id", userResult.user.id)
          .eq("checkout_key", checkoutKey)
          .maybeSingle();
        if (retryLookupError) throw retryLookupError;
        if (!retriedOrder?.invoice_url || !retriedOrder.external_id) {
          console.error("Could not save Xendit cart order:", saveOrderError);
          return respond(409, {
            error:
              "The invoice exists, but the order could not be saved. Contact the store before paying.",
          });
        }
        return respond(200, {
          invoice_url: retriedOrder.invoice_url,
          external_id: retriedOrder.external_id,
        });
      }
      return respond(200, {
        invoice_url: savedOrder.invoice_url,
        external_id: savedOrder.external_id,
      });
    }

    const firstProduct = productsById.get([...itemMap.keys()][0]);
    const { error: orderError } = await adminClient.from("orders").insert({
      user_id: userResult.user.id,
      product_id: firstProduct.id,
      product_name: firstProduct.name,
      amount,
      subtotal,
      delivery_fee: 0,
      quantity: totalQuantity,
      status: "PENDING",
      payment_status: "PENDING",
      payment_method: "XENDIT",
      delivery_status: "PENDING_CONFIRMATION",
      external_id: invoice.external_id,
      invoice_url: invoice.invoice_url,
    });
    if (orderError) {
      console.error("Could not save Xendit order:", orderError.message);
      return respond(500, {
        error: "The invoice was created, but the order could not be saved.",
      });
    }

    return respond(200, {
      invoice_url: invoice.invoice_url,
      external_id: invoice.external_id,
    });
  } catch (error) {
    console.error("Unexpected create-invoice error:", error);
    return respond(500, { error: "Could not start checkout." });
  }
});
