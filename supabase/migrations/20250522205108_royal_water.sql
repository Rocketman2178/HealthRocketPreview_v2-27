/*
  # Fix health assessment schema and update function

  1. Changes
    - Makes previous_healthspan column nullable
    - Creates a more specific version of the update_health_assessment function
    - Ensures proper parameter handling for gender and health_goals
    
  2. Security
    - Maintains existing RLS policies
*/

-- Make previous_healthspan nullable
ALTER TABLE health_assessments 
ALTER COLUMN previous_healthspan DROP NOT NULL;

-- Drop existing function with specific signatures to avoid ambiguity
DROP FUNCTION IF EXISTS update_health_assessment(uuid, integer, integer, numeric, numeric, numeric, numeric, numeric, numeric, timestamp with time zone);
DROP FUNCTION IF EXISTS update_health_assessment(uuid, integer, integer, text, numeric, numeric, numeric, numeric, numeric, numeric, timestamp with time zone);
DROP FUNCTION IF EXISTS update_health_assessment(uuid, integer, integer, text, numeric, numeric, numeric, numeric, numeric, numeric, timestamp with time zone, text);

-- Create updated function with a unique signature
CREATE OR REPLACE FUNCTION update_health_assessment_v2(
  p_user_id UUID,
  p_expected_lifespan INTEGER,
  p_expected_healthspan INTEGER,
  p_health_score NUMERIC(4,2),
  p_mindset_score NUMERIC(4,2),
  p_sleep_score NUMERIC(4,2),
  p_exercise_score NUMERIC(4,2),
  p_nutrition_score NUMERIC(4,2),
  p_biohacking_score NUMERIC(4,2),
  p_created_at TIMESTAMPTZ,
  p_gender TEXT DEFAULT NULL,
  p_health_goals TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_previous_healthspan INTEGER;
  v_result JSONB;
  v_assessment_id UUID;
  v_healthspan_years NUMERIC(4,2);
BEGIN
  -- Get previous healthspan from most recent assessment
  SELECT expected_healthspan INTO v_previous_healthspan
  FROM health_assessments
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Calculate healthspan years gained
  v_healthspan_years := p_expected_healthspan - COALESCE(v_previous_healthspan, p_expected_healthspan);

  -- Insert new assessment
  INSERT INTO health_assessments (
    user_id,
    expected_lifespan,
    expected_healthspan,
    health_score,
    healthspan_years,
    previous_healthspan,
    mindset_score,
    sleep_score,
    exercise_score,
    nutrition_score,
    biohacking_score,
    created_at,
    gender,
    health_goals
  ) VALUES (
    p_user_id,
    p_expected_lifespan,
    p_expected_healthspan,
    p_health_score,
    v_healthspan_years,
    v_previous_healthspan,
    p_mindset_score,
    p_sleep_score,
    p_exercise_score,
    p_nutrition_score,
    p_biohacking_score,
    p_created_at,
    p_gender,
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

  -- Return success
  v_result := jsonb_build_object(
    'success', true,
    'assessment_id', v_assessment_id,
    'healthspan_years', v_healthspan_years
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
) TO public;