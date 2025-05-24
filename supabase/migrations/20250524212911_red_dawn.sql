/*
  # Fix HealthSpan Calculation

  1. Changes
    - Creates a new function to properly calculate healthspan years based on initial assessment
    - Stores the initial healthspan value for reference
    - Calculates the difference between current and initial healthspan for proper tracking
    
  2. Security
    - Maintains existing RLS policies
    - Function remains security definer with proper permissions
*/

-- Add initial_healthspan column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'users' 
    AND column_name = 'initial_healthspan'
  ) THEN
    ALTER TABLE users 
    ADD COLUMN initial_healthspan integer;
  END IF;
END $$;

-- Create a function to properly calculate healthspan years
CREATE OR REPLACE FUNCTION public.update_health_assessment_v3(
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
  v_initial_healthspan INTEGER;
  v_result JSONB;
  v_assessment_id UUID;
  v_healthspan_years NUMERIC(4,2);
  v_is_first_assessment BOOLEAN;
BEGIN
  -- Check if this is the first assessment
  SELECT COUNT(*) = 0 INTO v_is_first_assessment
  FROM health_assessments
  WHERE user_id = p_user_id;
  
  -- Get initial healthspan from user record
  SELECT initial_healthspan INTO v_initial_healthspan
  FROM users
  WHERE id = p_user_id;
  
  -- If this is the first assessment or initial_healthspan is null, set it
  IF v_is_first_assessment OR v_initial_healthspan IS NULL THEN
    -- Store the initial healthspan value
    UPDATE users
    SET initial_healthspan = p_expected_healthspan
    WHERE id = p_user_id;
    
    -- Set initial value for calculation
    v_initial_healthspan := p_expected_healthspan;
    
    -- For first assessment, healthspan_years is 0
    v_healthspan_years := 0;
  ELSE
    -- Calculate healthspan years as the difference between current and initial
    v_healthspan_years := p_expected_healthspan - v_initial_healthspan;
  END IF;

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
    v_initial_healthspan,
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
    healthspan = p_expected_healthspan,
    onboarding_completed = true
  WHERE id = p_user_id;

  -- Return success
  v_result := jsonb_build_object(
    'success', true,
    'assessment_id', v_assessment_id,
    'healthspan_years', v_healthspan_years,
    'initial_healthspan', v_initial_healthspan,
    'is_first_assessment', v_is_first_assessment
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION update_health_assessment_v3(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
) TO public;