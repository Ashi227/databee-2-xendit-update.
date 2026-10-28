import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed.", { status: 405 });
  }

  const callbackToken = Deno.env.get("XENDIT_CALLBACK_TOKEN");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!callbackToken || !supabaseUrl || !serviceRoleKey) {
    console.error("One or more required webhook secrets are not configured.");
    return new Response("Webhook is not configured.", { status: 500 });
  }
  if (request.headers.get("x-callback-token") !== callbackToken) {
    return new Response("Unauthorized.", { status: 401 });
  }

  try {
    const body = await request.json();
    const externalId =
      typeof body.external_id === "string" ? body.external_id : "";
    const xenditStatus =
      typeof body.status === "string" ? body.status.toUpperCase() : "";
    const status = new Map([
      ["PAID", "PAID"],
      ["SETTLED", "SETTLED"],
      ["EXPIRED", "EXPIRED"],
      ["FAILED", "FAILED"],
    ]).get(xenditStatus);
    if (!externalId || !status) {
      return new Response("Unsupported callback payload.", { status: 400 });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: finalizeError } = await adminClient.rpc(
      "finalize_xendit_order",
      {
        p_external_id: externalId,
        p_payment_status: status,
      },
    );
    if (finalizeError) {
      if (finalizeError.message.includes("Xendit order not found")) {
        return new Response("Order not found.", { status: 404 });
      }
      throw finalizeError;
    }

    return new Response("OK", { status: 200 });
  } catch (error) {
    console.error("Xendit webhook processing failed:", error);
    return new Response("Could not process callback.", { status: 500 });
  }
});
