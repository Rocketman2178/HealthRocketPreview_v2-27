/*
  # Add Boost Code Redemption System

  1. New Tables
    - `boost_codes` - Stores boost codes that can be redeemed for Fuel Points
    - `boost_code_redemptions` - Tracks which users have redeemed which codes
    
  2. New Functions
    - `redeem_boost_code` - Handles the redemption process and awards FP
    
  3. Security
    - RLS policies to control access to the tables
    - Function is SECURITY DEFINER to ensure proper validation
*/

-- Create boost_codes table
CREATE TABLE IF NOT EXISTS public.boost_codes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    boost_code TEXT UNIQUE NOT NULL,
    fp_amount INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    promotion TEXT,
    is_active BOOLEAN DEFAULT true
);

-- Create boost_code_redemptions table
CREATE TABLE IF NOT EXISTS public.boost_code_redemptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users ON DELETE CASCADE NOT NULL,
    boost_code_id UUID REFERENCES public.boost_codes ON DELETE CASCADE NOT NULL,
    redeemed_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    fp_earned INTEGER NOT NULL,
    CONSTRAINT unique_user_boost_code UNIQUE (user_id, boost_code_id)
);

-- Enable RLS on boost_codes table
ALTER TABLE public.boost_codes ENABLE ROW LEVEL SECURITY;

-- Enable RLS on boost_code_redemptions table
ALTER TABLE public.boost_code_redemptions ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for boost_codes table
CREATE POLICY "Enable read access for all users" ON public.boost_codes 
  FOR SELECT USING (TRUE);

-- Create RLS policy for boost_code_redemptions table
CREATE POLICY "Enable read access for users based on user_id" ON public.boost_code_redemptions 
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Enable insert for authenticated users" ON public.boost_code_redemptions 
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create function to redeem boost code
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
BEGIN
    -- Get current user ID
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'User not authenticated'
        );
    END IF;
    
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
        'Boost Code Redemption',
        'other',
        v_fp_amount
    );
    
    -- Return success
    RETURN jsonb_build_object(
        'success', TRUE,
        'fp_earned', v_fp_amount
    );
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.redeem_boost_code(TEXT) TO public;

-- Insert some sample boost codes for testing
INSERT INTO public.boost_codes (boost_code, fp_amount, promotion)
VALUES 
    ('HR100', 100, 'Welcome Bonus'),
    ('FUEL5', 50, 'Social Media Promotion'),
    ('ROCK2', 25, 'Newsletter Signup');