import { useState } from "react";
import { supabase } from "../lib/supabase";

export interface StripeCheckoutResult {
  sessionId: string;
  sessionUrl: string;
}

export interface StripeError {
  error: string;
}

export type StripeResult = StripeCheckoutResult | StripeError |null;

export function useStripe() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const createSubscription = async (
    productId:string, 
    priceId: string,
    trialDays: number = 0,
    promoCode: boolean = false
  ): Promise<StripeResult> => {
    try {
      setLoading(true);
      setError(null);
      // Get the Supabase session for authentication
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (!session) {
        throw new Error("User not authenticated");
      }

      const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-subscription`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${session.access_token}`,
            apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
          },
          body: JSON.stringify({productId, priceId, trialDays, promoCode }),
        }
      );

      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(data.error || "Failed to create Stripe session");
      }

      return {
        sessionUrl: data.sessionUrl || data.session_url,
        sessionId: data.sessionId || data.session_id,
      };
    } catch (_) {
      return null;
    } finally {
      setLoading(false);
    }
  };

  const cancelSubscription = async (): Promise<{
    success: boolean;
    error?: string;
  }> => {
    try {
      setLoading(true);
      setError(null);

      // Call the Supabase RPC function to cancel subscription
      const { data, error } = await supabase.rpc("cancel_subscription");

      if (error) throw error;

      return { success: data?.success || false, error: data?.error };
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to cancel subscription"
      );
      return {
        success: false,
        error:
          err instanceof Error ? err.message : "Failed to cancel subscription",
      };
    } finally {
      setLoading(false);
    }
  };

  const updatePaymentMethod = async (): Promise<StripeResult> => {
    try {
      setLoading(true);
      setError(null);
      // Get the Supabase session for authentication
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (!session) {
        throw new Error("User not authenticated");
      }

      const response = await fetch(
        `${
          import.meta.env.VITE_SUPABASE_URL
        }/functions/v1/update-payment-method`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${session.access_token}`,
            apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
          },
        }
      );

      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(data.error || "Failed to create Stripe session");
      }

      return {
        sessionUrl: data.sessionUrl || data.session_url,
        sessionId: data.sessionId || data.session_id,
      };
    } catch (_) {
      return null;
    } finally {
      setLoading(false);
    }
  };

  return {
    loading,
    error,
    createSubscription,
    cancelSubscription,
    updatePaymentMethod,
  };
}
