import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import Stripe from "https://esm.sh/stripe@14.14.0";
// INITIALIZE STRIPE
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2023-10-16',
});
// DEFINE CORS HEADERS 
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
// SERVE STRIPE EDGE FUNCTION
serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // CREATE SUPABASE CLIENT 
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // GET AUTHERIZATION HEADER FROM THE REQUEST
    const authHeader = req.headers.get('Authorization')?.split(' ')[1];
    if (!authHeader) {
      throw new Error('Authorization header is required');
    }

    //GET USER FROM SUPABASE AUTH
    const { data: { user }, error: userError } = await supabase.auth.getUser(authHeader);
    if (userError || !user) throw new Error('Invalid user');

    //GET CURRENT SUBSCRIPTION OF THE USER 
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .select('stripe_subscription_id')
      .eq('user_id', user.id)
      .maybeSingle();

    if (subError) throw subError;
    // CHECK IF THE USER HAS SUBSCRIPTION 
    if (!subscription?.stripe_subscription_id) {
      throw new Error('No active subscription found');
    }

    //CANCEL IMMEDIATELY
   await stripe.subscriptions.cancel(subscription.stripe_subscription_id);
    // UPDATE SUBSCRIPTIONS IN THE DATABASE 
    const { error: updateError } = await supabase
      .from('subscriptions')
      .delete()
      .eq('user_id', user.id);
      // CHECK IF THERE IS ERROR WHILE UPDATING SUBSCRIPTIONS IN THE DATABASE 
    if (updateError) throw updateError;
    
    // UPDATE USER TABLE
    const { error: userUpdateError } = await supabase
      .from('users')
      .update({ 
        plan: 'Free Plan'
      })
      .eq('id', user.id);
      
    if (userUpdateError) throw userUpdateError;

    return new Response(
      JSON.stringify({ success: true }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});