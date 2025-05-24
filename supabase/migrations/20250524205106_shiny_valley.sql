/*
  # Launch Codes System

  1. New Tables
    - `launch_codes` - Stores launch codes that can be used for account creation
    - `launch_code_usages` - Tracks which users have used which launch codes
    
  2. New Functions
    - `validate_launch_code` - Validates a launch code and checks if it's still available
    - `use_launch_code` - Records usage of a launch code during account creation
    
  3. Security
    - RLS policies to control access to the tables
    - Functions are SECURITY DEFINER to ensure proper validation
*/

-- Create launch_codes table
CREATE TABLE IF NOT EXISTS public.launch_codes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    max_uses INTEGER NOT NULL,
    uses_count INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    promotion TEXT,
    is_active BOOLEAN DEFAULT true
);

-- Create launch_code_usages table
CREATE TABLE IF NOT EXISTS public.launch_code_usages (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users ON DELETE CASCADE NOT NULL,
    launch_code_id UUID REFERENCES public.launch_codes ON DELETE CASCADE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_user_launch_code UNIQUE (user_id, launch_code_id)
);

-- Enable RLS on launch_codes table
ALTER TABLE public.launch_codes ENABLE ROW LEVEL SECURITY;

-- Enable RLS on launch_code_usages table
ALTER TABLE public.launch_code_usages ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for launch_codes table
CREATE POLICY "Enable read access for all users" ON public.launch_codes 
  FOR SELECT USING (TRUE);

-- Create RLS policy for launch_code_usages table
CREATE POLICY "Enable read access for users based on user_id" ON public.launch_code_usages 
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Enable insert for authenticated users" ON public.launch_code_usages 
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create function to validate launch code
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
            'error', 'Invalid launch code'
        );
    END IF;
    
    -- Check if launch code is active
    IF NOT v_is_active THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'error', 'Launch code is no longer active'
        );
    END IF;
    
    -- Check if launch code has available uses
    IF v_uses_count >= v_max_uses THEN
        RETURN jsonb_build_object(
            'valid', FALSE,
            'error', 'Launch code has been fully subscribed'
        );
    END IF;
    
    -- Return success
    RETURN jsonb_build_object(
        'valid', TRUE,
        'launch_code_id', v_launch_code_id
    );
END;
$$;

-- Create function to use a launch code
CREATE OR REPLACE FUNCTION public.use_launch_code(p_user_id UUID, p_code TEXT)
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
BEGIN
    -- Find the launch code
    SELECT id, max_uses, uses_count, is_active 
    INTO v_launch_code_id, v_max_uses, v_uses_count, v_is_active
    FROM launch_codes
    WHERE code = p_code;
    
    -- Check if launch code exists
    IF v_launch_code_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Invalid launch code'
        );
    END IF;
    
    -- Check if launch code is active
    IF NOT v_is_active THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Launch code is no longer active'
        );
    END IF;
    
    -- Check if launch code has available uses
    IF v_uses_count >= v_max_uses THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Launch code has been fully subscribed'
        );
    END IF;
    
    -- Record the usage
    INSERT INTO launch_code_usages (
        user_id,
        launch_code_id
    ) VALUES (
        p_user_id,
        v_launch_code_id
    );
    
    -- Increment the uses count
    UPDATE launch_codes
    SET uses_count = uses_count + 1
    WHERE id = v_launch_code_id;
    
    -- Return success
    RETURN jsonb_build_object(
        'success', TRUE
    );
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.validate_launch_code(TEXT) TO public;
GRANT EXECUTE ON FUNCTION public.use_launch_code(UUID, TEXT) TO public;

-- Insert some sample launch codes for testing
INSERT INTO public.launch_codes (code, max_uses, promotion)
VALUES 
    ('PREVIEW100', 100, 'Preview Access'),
    ('GOBUNDANCE', 50, 'Gobundance Members'),
    ('HEALTHROCKET', 25, 'Early Access');