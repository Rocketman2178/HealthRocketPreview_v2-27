import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Get the email from the request
    const { email } = await req.json();
    if (!email) {
      throw new Error("Email is required");
    }

    console.log(`Attempting to delete user with email: ${email}`);

    // First, get the user ID from the auth.users table
    const { data: userData, error: userError } = await supabase.auth.admin.listUsers();
    
    if (userError) {
      throw new Error(`Error fetching users: ${userError.message}`);
    }

    // Find the user with the matching email
    const user = userData.users.find(u => u.email === email);
    
    if (!user) {
      throw new Error(`User with email ${email} not found in auth.users`);
    }

    console.log(`Found user with ID: ${user.id}`);

    // Delete from public.users table first (this should cascade to related tables)
    const { error: deletePublicError } = await supabase
      .from('users')
      .delete()
      .eq('id', user.id);

    if (deletePublicError) {
      console.error(`Error deleting from public.users: ${deletePublicError.message}`);
      // Continue anyway, as we still want to try deleting from auth
    } else {
      console.log(`Deleted user from public.users table`);
    }

    // Delete from auth.users table
    const { error: deleteAuthError } = await supabase.auth.admin.deleteUser(
      user.id
    );

    if (deleteAuthError) {
      throw new Error(`Error deleting from auth.users: ${deleteAuthError.message}`);
    }

    console.log(`Successfully deleted user from auth.users table`);

    return new Response(
      JSON.stringify({
        success: true,
        message: `User with email ${email} has been deleted from both tables`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error deleting user:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }
});