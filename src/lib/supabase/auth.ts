import { supabase } from "./client";
import { AuthError } from "../errors";

export async function resetPassword(email: string) {
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    });

    if (error) throw error;
  } catch (err) {
    console.error("Password reset error:", err);
    throw new AuthError("Failed to send reset email", err);
  }
}

export async function updatePassword(newPassword: string) {
  try {
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
    });

    if (error) throw error;
  } catch (err) {
    console.error("Password update error:", err);
    throw new AuthError("Failed to update password", err);
  }
}

export async function signIn(email: string, password: string) {
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      if (error.message.includes("Invalid login")) {
        throw new AuthError("Invalid email or password");
      }
      throw error;
    }
  } catch (err) {
    console.error("Sign in error:", err);
    throw new AuthError("Failed to sign in", err);
  }
}

export async function signUp(email: string, password: string, name: string, launchCode: string = '') {
  try {
    // Validate launch code first
    if (launchCode.trim()) {
      const { data: validationData, error: validationError } = await supabase.rpc(
        'validate_launch_code',
        { p_code: launchCode }
      );

      if (validationError) {
        console.error('Launch code validation error:', validationError);
        throw new AuthError('Failed to validate launch code. Please try again.');
      }
      
      if (!validationData || !validationData.valid) {
        throw new AuthError(
          validationData?.error || 
          'Launch Code is not valid or has been fully subscribed. Please contact support at support@healthrocket.app for more info.'
        );
      }
    }

    // Create auth user
    const { error: signUpError, data } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { name, launchCode },
      },
    });

    if (signUpError) throw signUpError;
    if (!data.user) throw new Error("No user returned from signup");

    // Use the launch code if provided
    if (launchCode.trim()) {
      const { error: usageError } = await supabase.rpc(
        'use_launch_code',
        { 
          p_user_id: data.user.id,
          p_code: launchCode
        }
      );

      if (usageError) throw usageError;
    }

    // Create user profile
    const { error: profileError } = await supabase.from("users").insert({
      id: data.user.id,
      email,
      name,
      plan: "Pro Plan", // Default to Pro Plan with trial
      subscription_start_date: new Date().toISOString(), // Track when subscription started for trial period
      level: 1,
      fuel_points: 0,
      burn_streak: 0,
      health_score: 7.8,
      healthspan_years: 0,
      onboarding_completed: false,
    });

    if (profileError) throw profileError;
  } catch (err) {
    console.error("Sign up error:", err);
    // Preserve the original error message from AuthError
    if (err instanceof AuthError) {
      throw err;
    } else {
      throw new AuthError("Failed to create account", err);
    }
  }
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
  localStorage.clear();
  sessionStorage.clear();
}
