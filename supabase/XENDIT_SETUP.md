# Xendit checkout setup

Cart Xendit checkout runs through Supabase Edge Functions. Do not put an
Xendit secret key or Supabase service-role key in the Flutter app.

1. Re-run the updated `shopping_delivery.sql` migration in Supabase SQL Editor.
   It adds the invoice and stock-reservation fields and the server-only order
   functions required for cart checkout.
2. In your Xendit **test** account, copy the development secret key and create a
   callback verification token.
3. Set both values as Supabase Function secrets:

   ```sh
   supabase secrets set --project-ref YOUR_PROJECT_REF XENDIT_SECRET_KEY=xnd_development-YOUR_TEST_KEY XENDIT_CALLBACK_TOKEN=YOUR_CALLBACK_TOKEN
   ```

   The Supabase project URL and server credentials are supplied to deployed
   functions by Supabase. Never add the Xendit key to `--dart-define`.
4. Deploy the invoice and webhook functions from the repository root:

   ```sh
   supabase functions deploy create-invoice --project-ref YOUR_PROJECT_REF
   supabase functions deploy xendit-webhook --project-ref YOUR_PROJECT_REF
   ```

5. In Xendit, set the invoice payment callback URL to
   `https://YOUR_PROJECT_REF.supabase.co/functions/v1/xendit-webhook` and use
   the same callback verification token.
6. Launch the app in Supabase mode (not local demo mode), sign in, and select
   **Xendit** in cart checkout. A development Xendit key creates test invoices;
   payment and callback status updates must be enabled in the Xendit test
   dashboard.

   For a local Flutter run, pass your own public Supabase settings:

   ```sh
   flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
   ```
