/*
  # Fix HealthSpan Calculation Logic

  1. Changes
    - Updates the update_health_assessment_v3 function to properly calculate healthspan years
    - Ensures initial_healthspan is properly stored and used for all calculations
    - Adds a function to update existing users with correct initial_healthspan values
    
  2. Security
    - Maintains existing RLS policies
    - Function remains security definer with proper permissions
*/

-- First, ensure the initial_healthspan column exists
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

-- Create a function to fix initial_healthspan for existing users
CREATE OR REPLACE FUNCTION fix_initial_healthspan()
RETURNS JSONB AS $$
DECLARE
  v_user RECORD;
  v_first_assessment RECORD;
  v_updated_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
BEGIN
  -- Loop through all users
  FOR v_user IN SELECT id FROM users WHERE initial_healthspan IS NULL
  LOOP
    -- Get the first health assessment for this user
    SELECT expected_healthspan INTO v_first_assessment
    FROM health_assessments
    WHERE user_id = v_user.id
    ORDER BY created_at ASC
    LIMIT 1;
    
    -- If user has an assessment, update their initial_healthspan
    IF v_first_assessment IS NOT NULL THEN
      UPDATE users
      SET initial_healthspan = v_first_assessment.expected_healthspan
      WHERE id = v_user.id;
      
      v_updated_count := v_updated_count + 1;
    ELSE
      v_skipped_count := v_skipped_count + 1;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'updated_count', v_updated_count,
    'skipped_count', v_skipped_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop the existing function to replace it
DROP FUNCTION IF EXISTS update_health_assessment_v3(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
);

-- Create updated function with proper healthspan calculation
CREATE OR REPLACE FUNCTION update_health_assessment_v3(
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
  v_assessment_count INTEGER;
BEGIN
  -- Check if this is the first assessment
  SELECT COUNT(*) INTO v_assessment_count
  FROM health_assessments
  WHERE user_id = p_user_id;
  
  v_is_first_assessment := (v_assessment_count = 0);
  
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

-- Run the fix function to update existing users
SELECT fix_initial_healthspan();

-- Grant execute permission to the fix function
GRANT EXECUTE ON FUNCTION fix_initial_healthspan() TO postgres;