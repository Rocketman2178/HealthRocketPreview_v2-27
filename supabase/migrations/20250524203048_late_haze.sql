/*
  # Update Boost Code Redemption to Update Daily FP

  1. Changes
    - Modifies the redeem_boost_code function to update the daily_fp table
    - Adds a trigger to sync FP earnings with daily_fp table
    - Ensures consistent FP tracking across all earning methods
    
  2. Security
    - Maintains existing RLS policies
    - Function remains security definer with proper permissions
*/

-- Drop the existing function
DROP FUNCTION IF EXISTS public.redeem_boost_code(TEXT);

-- Create updated function with daily_fp update
CREATE OR REPLACE FUNCTION public.redeem_boost_code(p_boost_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_boost_code_id UUID;
    v_fp_amount INTEGER;
    v_result JSONB;
    v_today DATE := CURRENT_DATE;
    v_user_name TEXT;
BEGIN
    -- Get current user ID
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'User not authenticated'
        );
    END IF;
    
    -- Get user name for records
    SELECT name INTO v_user_name
    FROM users
    WHERE id = v_user_id;
    
    -- Find the boost code
    SELECT id, fp_amount INTO v_boost_code_id, v_fp_amount
    FROM boost_codes
    WHERE boost_code = p_boost_code
    AND is_active = TRUE;
    
    -- Check if boost code exists
    IF v_boost_code_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Invalid boost code'
        );
    END IF;
    
    -- Check if user has already redeemed this code
    IF EXISTS (
        SELECT 1 FROM boost_code_redemptions
        WHERE user_id = v_user_id
        AND boost_code_id = v_boost_code_id
    ) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'You have already redeemed this code'
        );
    END IF;
    
    -- Record the redemption
    INSERT INTO boost_code_redemptions (
        user_id,
        boost_code_id,
        fp_earned
    ) VALUES (
        v_user_id,
        v_boost_code_id,
        v_fp_amount
    );
    
    -- Add FP to user
    UPDATE users
    SET fuel_points = fuel_points + v_fp_amount,
        days_since_fp = 0
    WHERE id = v_user_id;
    
    -- Record FP earning
    INSERT INTO fp_earnings (
        user_id,
        item_id,
        item_name,
        item_type,
        fp_amount
    ) VALUES (
        v_user_id,
        p_boost_code,
        'Boost Code: ' || p_boost_code,
        'other',
        v_fp_amount
    );
    
    -- Update or insert into daily_fp table
    INSERT INTO daily_fp (
        user_id,
        date,
        fp_earned,
        source,
        user_name
    ) VALUES (
        v_user_id,
        v_today,
        v_fp_amount,
        'boost_code',
        v_user_name
    )
    ON CONFLICT (user_id, date) 
    DO UPDATE SET
        fp_earned = daily_fp.fp_earned + v_fp_amount;
    
    -- Return success
    RETURN jsonb_build_object(
        'success', TRUE,
        'fp_earned', v_fp_amount
    );
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.redeem_boost_code(TEXT) TO public;

-- Create a trigger function to sync boost code redemptions with fp_earnings
CREATE OR REPLACE FUNCTION public.sync_boost_code_fp()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert into fp_earnings table
    INSERT INTO fp_earnings (
        user_id,
        item_id,
        item_name,
        item_type,
        fp_amount
    ) VALUES (
        NEW.user_id,
        (SELECT boost_code FROM boost_codes WHERE id = NEW.boost_code_id),
        'Boost Code Redemption',
        'other',
        NEW.fp_earned
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger on boost_code_redemptions table
DROP TRIGGER IF EXISTS record_boost_code_fp_earning ON public.boost_code_redemptions;
CREATE TRIGGER record_boost_code_fp_earning
AFTER INSERT ON public.boost_code_redemptions
FOR EACH ROW
EXECUTE FUNCTION public.sync_boost_code_fp();