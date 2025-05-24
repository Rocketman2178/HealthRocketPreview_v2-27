/*
  # Improve Launch Code Error Message

  1. Changes
    - Updates the validate_launch_code function to return more specific error messages
    - Ensures users see "Launch Code is not valid or has been fully subscribed. Please contact support at support@healthrocket.app for more info."
    - Maintains existing functionality while improving user experience
    
  2. Security
    - Function remains security definer with proper permissions
    - No changes to RLS policies
*/

-- Drop the existing function
DROP FUNCTION IF EXISTS public.validate_launch_code(TEXT);

-- Create updated function with improved error messages
CREATE OR REPLACE FUNCTION public.validate_launch_code(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_launch_code_id UUID;
    v_max_uses INTEGER;
    v_uses_count INTEGER;
    v_is_active BOOLEAN;
    v_result JSONB;
    v_standard_error TEXT := 'Launch Code is not valid or has been fully subscribed. Please contact support at support@healthrocket.app for more info.';
BEGIN
    -- Find the launch code
    SELECT id, max_uses, uses_count, is_active 
    INTO v_launch_code_id, v_max_uses, v_uses_count, v_is_active
    FROM launch_codes
    WHERE code = p_code;
    
    -- Check if launch code exists
    IF v_launch_code_id IS NULL THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'error', v_standard_error
        );
    END IF;
    
    -- Check if launch code is active
    IF NOT v_is_active THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'error', v_standard_error
        );
    END IF;
    
    -- Check if launch code has available uses
    IF v_uses_count >= v_max_uses THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'error', v_standard_error
        );
    END IF;
    
    -- Return success
    RETURN jsonb_build_object(
        'valid', TRUE,
        'launch_code_id', v_launch_code_id
    );
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.validate_launch_code(TEXT) TO public;