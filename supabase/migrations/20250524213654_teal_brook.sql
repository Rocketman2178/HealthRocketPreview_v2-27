/*
  # Fix John Lee's HealthSpan Calculation

  1. Changes
    - Fixes the incorrect HealthSpan calculation for user John Lee
    - Updates both the users table and the most recent health assessment
    - Ensures the healthspan_years value is correctly set to 0
    
  2. Security
    - Function is security definer with proper permissions
    - Only affects the specific user with the issue
*/

-- Create a function to fix John Lee's healthspan years
CREATE OR REPLACE FUNCTION fix_john_lee_healthspan()
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_latest_assessment_id UUID;
  v_initial_healthspan INTEGER;
  v_expected_healthspan INTEGER;
  v_result JSONB;
BEGIN
  -- Get John Lee's user ID
  SELECT id, initial_healthspan, healthspan INTO v_user_id, v_initial_healthspan, v_expected_healthspan
  FROM users
  WHERE name = 'John Lee';
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User John Lee not found'
    );
  END IF;
  
  -- Verify initial_healthspan is set correctly
  IF v_initial_healthspan IS NULL OR v_initial_healthspan != 76 THEN
    -- Update initial_healthspan to 76 if not set correctly
    UPDATE users
    SET initial_healthspan = 76
    WHERE id = v_user_id;
    
    v_initial_healthspan := 76;
  END IF;
  
  -- Calculate correct healthspan_years (should be 0 if current healthspan is also 76)
  DECLARE
    v_correct_healthspan_years NUMERIC(4,2) := v_expected_healthspan - v_initial_healthspan;
  BEGIN
    -- Update the user's healthspan_years
    UPDATE users
    SET healthspan_years = v_correct_healthspan_years
    WHERE id = v_user_id;
    
    -- Get the latest assessment ID
    SELECT id INTO v_latest_assessment_id
    FROM health_assessments
    WHERE user_id = v_user_id
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Update the latest assessment's healthspan_years
    IF v_latest_assessment_id IS NOT NULL THEN
      UPDATE health_assessments
      SET healthspan_years = v_correct_healthspan_years
      WHERE id = v_latest_assessment_id;
    END IF;
  END;
  
  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'initial_healthspan', v_initial_healthspan,
    'expected_healthspan', v_expected_healthspan,
    'corrected_healthspan_years', v_expected_healthspan - v_initial_healthspan
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run the fix function
SELECT fix_john_lee_healthspan();

-- Create a more general function to fix any user's healthspan calculation
CREATE OR REPLACE FUNCTION fix_user_healthspan_calculation(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_initial_healthspan INTEGER;
  v_expected_healthspan INTEGER;
  v_latest_assessment_id UUID;
  v_result JSONB;
BEGIN
  -- Get user's healthspan data
  SELECT initial_healthspan, healthspan INTO v_initial_healthspan, v_expected_healthspan
  FROM users
  WHERE id = p_user_id;
  
  IF v_initial_healthspan IS NULL THEN
    -- If initial_healthspan is not set, get it from the first assessment
    SELECT expected_healthspan INTO v_initial_healthspan
    FROM health_assessments
    WHERE user_id = p_user_id
    ORDER BY created_at ASC
    LIMIT 1;
    
    -- Update the user's initial_healthspan
    IF v_initial_healthspan IS NOT NULL THEN
      UPDATE users
      SET initial_healthspan = v_initial_healthspan
      WHERE id = p_user_id;
    ELSE
      -- If no assessments exist, use current healthspan as initial
      v_initial_healthspan := v_expected_healthspan;
      
      UPDATE users
      SET initial_healthspan = v_expected_healthspan
      WHERE id = p_user_id;
    END IF;
  END IF;
  
  -- Calculate correct healthspan_years
  DECLARE
    v_correct_healthspan_years NUMERIC(4,2) := v_expected_healthspan - v_initial_healthspan;
  BEGIN
    -- Update the user's healthspan_years
    UPDATE users
    SET healthspan_years = v_correct_healthspan_years
    WHERE id = p_user_id;
    
    -- Get the latest assessment ID
    SELECT id INTO v_latest_assessment_id
    FROM health_assessments
    WHERE user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Update the latest assessment's healthspan_years
    IF v_latest_assessment_id IS NOT NULL THEN
      UPDATE health_assessments
      SET healthspan_years = v_correct_healthspan_years
      WHERE id = v_latest_assessment_id;
    END IF;
  END;
  
  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'initial_healthspan', v_initial_healthspan,
    'expected_healthspan', v_expected_healthspan,
    'corrected_healthspan_years', v_expected_healthspan - v_initial_healthspan
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to postgres
GRANT EXECUTE ON FUNCTION fix_user_healthspan_calculation(UUID) TO postgres;