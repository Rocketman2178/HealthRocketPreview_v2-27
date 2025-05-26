import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import Stripe from "https://esm.sh/stripe@14.14.0";
// INITIALIZE STRIPE
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
});
// DEFINE CORS HEADERS
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
// SERVE CREATE SUBSCRIPTION API
serve(async (req) => {
  // HANDLE CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // CREATE SUPABASE CLIENT
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // GET AUTHORIZATION HEADER
    const authHeader = req.headers.get("Authorization")?.split(" ")[1];
    // CHECK AUTH HEADER EXISTS
    if (!authHeader) {
      throw new Error("Authorization header is required");
    }

    // GET AUTHENTICATED USER
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(authHeader);
    // CHECK IF THERE IS AN ERROR WHILE FETCHING AUTHENTICATED USER
    if (userError) {
      throw new Error("Authentication failed");
    }
    // CHECK IF THE USER EXISTS
    if (!user) {
      throw new Error("User not found");
    }

    // GET BODY PARAMS
    const { priceId, trialDays, promoCode } = await req.json();
    if (!priceId) throw new Error("Price ID is required");

    // GET USER PROFILE
    const { data: userData, error: profileError } = await supabase
      .from("users")
      .select("email, name")
      .eq("id", user.id)
      .single();

    // CHECK IF THE USER PROFILE EXISTS
    if (profileError || !userData) {
      throw new Error("User profile not found");
    }
    // CHECK IF THE USER HAS EMAIL ADDRESS
    if (!userData.email) {
      throw new Error("User email is required");
    }

    // CHECK IF USER HAS ALREADY SUBSCRIPTION
    const { data: customers } = await supabase
      .from("subscriptions")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .maybeSingle();
    let customerId = customers?.stripe_customer_id;

    // CHECK IF USER CUSTOMER ID EXISTS
    if (!customerId) {
      // IF THERE IS NO CUSTOMER ID FOR SUBSCRIPTION CREATE NEW CUSTOMER
      const customer = await stripe.customers.create({
        email: userData.email,
        name: userData.name || undefined,
        metadata: {
          supabaseUUID: user.id,
        },
      });

      customerId = customer.id;
    }

    //CREATE STRIPE CHECKOUT SESSION
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      payment_method_collection: "if_required",
      ...(promoCode && { allow_promotion_codes: true }),
      mode: "subscription",
      ...(trialDays > 0 && {
        subscription_data: { trial_period_days: trialDays },
      }),
      success_url: `${req.headers.get(
        "origin"
      )}/subscription/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${req.headers.get("origin")}`,
      metadata: {
        userId: user.id,
      },
    });
    return new Response(
      JSON.stringify({ sessionId: session.id, sessionUrl: session.url }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
