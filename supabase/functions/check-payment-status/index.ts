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
// SERVE THE CHECK PAYMENT STATUS API
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // CREATE SUPABASE CLIENT
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    // GET SESSION ID
    const { sessionId } = await req.json();
    if (!sessionId) throw new Error("Session ID is required");
    // GET STRIPE SESSION
    const session = await stripe.checkout.sessions.retrieve(sessionId);
    // CHECK IF THERE IS SESSION
    if (!session || !session.metadata?.userId) {
      throw new Error("Invalid session or missing user metadata");
    }

    const userId = session.metadata.userId;
    const customerId = session.customer as string;
    const subscriptionId = session.subscription as string;

    if (session.payment_status !== "paid") {
      throw new Error("Payment not completed");
    }

    const subscription = await stripe.subscriptions.retrieve(subscriptionId);

    const newSubscriptionRecord = {
      user_id: userId,
      stripe_customer_id: customerId,
      stripe_subscription_id: subscription.id,
      plan_id: subscription.items.data[0].price.id,
      status: subscription.status,
      current_period_start: new Date(
        subscription.current_period_start * 1000
      ).toISOString(),
      current_period_end: new Date(
        subscription.current_period_end * 1000
      ).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
    };
    // IF THE USER HAS ALREADY SUBSCRIPTION
    const { data: user_subsctription, error: user_subscription_error } =
      await supabase
        .from("subscriptions")
        .select("*")
        .eq("user_id", userId)
        .eq("stripe_customer_id", customerId);
    if (!user_subsctription || user_subscription_error || user_subsctription.length === 0) {
      // Insert subscription data
      const { error: insertError } = await supabase
        .from("subscriptions")
        .insert(newSubscriptionRecord);
      if (insertError) throw insertError;
    } else {
      // UPDATE EXISTING SUBSCRIPTION
      const { user_id, stripe_customer_id, ...updateFields } =
        newSubscriptionRecord;
      const { error: updatetError } = await supabase
        .from("subscriptions")
        .update(updateFields)
        .eq("user_id", userId)
        .eq("stripe_customer_id", customerId);
      if (updatetError) throw updatetError;
    }

    // Update user's plan
    const { error: userUpdateError } = await supabase
      .from("users")
      .update({
        plan: "Pro Plan",
        plan_status: "Active",
        subscription_start_date: newSubscriptionRecord.current_period_start,
        subscription_end_date: newSubscriptionRecord.current_period_end,
      })
      .eq("id", userId);

    if (userUpdateError) throw userUpdateError;

    return new Response(
      JSON.stringify({
        success: true,
        paymentStatus: session.payment_status,
        userId,
        customerId,
        subscriptionId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message ?? "Unknown error" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }
});
