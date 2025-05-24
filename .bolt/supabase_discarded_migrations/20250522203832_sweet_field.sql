/*
  # Fix health assessment null constraint and add health goals support

  1. Changes
    - Ensures previous_healthspan column exists with a NOT NULL constraint and default value
    - Updates the update_health_assessment function to properly handle the previous healthspan value
    - Adds support for health_goals in the function parameters
    - Sets a default value for the previous healthspan when none exists
    
  2. Security
    - Maintains existing RLS policies
*/

-- Add previous_healthspan column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'health_assessments' 
    AND column_name = 'previous_healthspan'
  ) THEN
    ALTER TABLE health_assessments 
    ADD COLUMN previous_healthspan integer NOT NULL DEFAULT 0;
  END IF;
END $$;

-- Add health_goals column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'health_assessments' 
    AND column_name = 'health_goals'
  ) THEN
    ALTER TABLE health_assessments 
    ADD COLUMN health_goals text;
  END IF;
END $$;

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS update_health_assessment(
  p_user_id uuid,
  p_expected_lifespan integer,
  p_expected_healthspan integer,
  p_gender text,
  p_health_score numeric,
  p_mindset_score numeric,
  p_sleep_score numeric,
  p_exercise_score numeric,
  p_nutrition_score numeric,
  p_biohacking_score numeric,
  p_created_at timestamptz,
  p_health_goals text
);

-- Create updated function with previous_healthspan handling and health_goals support
CREATE OR REPLACE FUNCTION update_health_assessment(
  p_user_id uuid,
  p_expected_lifespan integer,
  p_expected_healthspan integer,
  p_gender text,
  p_health_score numeric,
  p_mindset_score numeric,
  p_sleep_score numeric,
  p_exercise_score numeric,
  p_nutrition_score numeric,
  p_biohacking_score numeric,
  p_created_at timestamptz,
  p_health_goals text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_assessment_id uuid;
  v_previous_healthspan integer;
  v_healthspan_years numeric(4,2);
BEGIN
  -- Get previous healthspan if exists
  SELECT expected_healthspan INTO v_previous_healthspan
  FROM health_assessments
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- If no previous assessment, use current expected_healthspan as previous
  IF v_previous_healthspan IS NULL THEN
    v_previous_healthspan := p_expected_healthspan;
  END IF;

  -- Calculate healthspan years gained
  v_healthspan_years := p_expected_healthspan - v_previous_healthspan;

  -- Insert new health assessment
  INSERT INTO health_assessments (
    user_id,
    expected_lifespan,
    expected_healthspan,
    gender,
    health_score,
    healthspan_years,
    previous_healthspan,
    mindset_score,
    sleep_score,
    exercise_score,
    nutrition_score,
    biohacking_score,
    created_at,
    health_goals
  ) VALUES (
    p_user_id,
    p_expected_lifespan,
    p_expected_healthspan,
    p_gender,
    p_health_score,
    v_healthspan_years,
    v_previous_healthspan,
    p_mindset_score,
    p_sleep_score,
    p_exercise_score,
    p_nutrition_score,
    p_biohacking_score,
    p_created_at,
    p_health_goals
  )
  RETURNING id INTO v_assessment_id;

  -- Update user's health metrics
  UPDATE users
  SET 
    health_score = p_health_score,
    healthspan_years = v_healthspan_years,
    lifespan = p_expected_lifespan,
    healthspan = p_expected_healthspan
  WHERE id = p_user_id;

  -- Build result object
  v_result := jsonb_build_object(
    'success', true,
    'assessment_id', v_assessment_id,
    'healthspan_years', v_healthspan_years
  );

  RETURN v_result;
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.update_health_assessment(uuid, integer, integer, text, numeric, numeric, numeric, numeric, numeric, numeric, timestamp with time zone, text) TO public;