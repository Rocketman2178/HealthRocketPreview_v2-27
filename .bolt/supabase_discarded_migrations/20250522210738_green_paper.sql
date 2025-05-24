/*
  # Fix HealthSpan Accumulation

  1. Changes
    - Improves the update_health_assessment_v2 function to properly accumulate healthspan years
    - Ensures each assessment adds to the previous total rather than just showing the difference
    - Adds a function to correct existing healthspan values for users
    
  2. Security
    - Maintains existing security settings
    - Function runs with SECURITY DEFINER to ensure proper access control
*/

-- Drop the existing function to replace it
DROP FUNCTION IF EXISTS update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
);

-- Create updated function with proper healthspan accumulation
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
  v_previous_healthspan_years NUMERIC(4,2);
  v_result JSONB;
  v_assessment_id UUID;
  v_healthspan_years NUMERIC(4,2);
  v_healthspan_change NUMERIC(4,2);
  v_initial_assessment BOOLEAN;
BEGIN
  -- Check if this is the first assessment
  SELECT COUNT(*) = 0 INTO v_initial_assessment
  FROM health_assessments
  WHERE user_id = p_user_id;

  -- Get previous healthspan and healthspan_years from most recent assessment
  SELECT 
    expected_healthspan, 
    healthspan_years 
  INTO 
    v_previous_healthspan,
    v_previous_healthspan_years
  FROM health_assessments
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Calculate healthspan change (difference between new and previous expected healthspan)
  v_healthspan_change := p_expected_healthspan - COALESCE(v_previous_healthspan, p_expected_healthspan);
  
  -- Calculate total healthspan years (previous total + new change)
  -- If this is the first assessment, start with 0 and add the expected healthspan
  IF v_initial_assessment THEN
    v_healthspan_years := p_expected_healthspan - 75; -- Assuming 75 is the baseline healthspan
  ELSE
    -- Add the change to the previous accumulated total
    v_healthspan_years := COALESCE(v_previous_healthspan_years, 0) + v_healthspan_change;
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
    'healthspan_years', v_healthspan_years,
    'healthspan_change', v_healthspan_change,
    'is_initial', v_initial_assessment
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
) TO public;

-- Create a function to fix existing healthspan values for a specific user
CREATE OR REPLACE FUNCTION fix_user_healthspan(p_user_id UUID) RETURNS JSONB AS $$
DECLARE
  v_assessments RECORD;
  v_accumulated_healthspan NUMERIC(4,2) := 0;
  v_previous_healthspan INTEGER := NULL;
  v_result JSONB;
  v_count INTEGER := 0;
BEGIN
  -- Process each assessment in chronological order
  FOR v_assessments IN 
    SELECT id, expected_healthspan
    FROM health_assessments
    WHERE user_id = p_user_id
    ORDER BY created_at ASC
  LOOP
    -- Calculate change for this assessment
    IF v_previous_healthspan IS NULL THEN
      -- First assessment - assume starting from 75 (default healthspan)
      v_accumulated_healthspan := v_assessments.expected_healthspan - 75;
    ELSE
      -- Subsequent assessments - add the change
      v_accumulated_healthspan := v_accumulated_healthspan + (v_assessments.expected_healthspan - v_previous_healthspan);
    END IF;
    
    -- Update this assessment
    UPDATE health_assessments
    SET healthspan_years = v_accumulated_healthspan,
        previous_healthspan = v_previous_healthspan
    WHERE id = v_assessments.id;
    
    -- Store current healthspan for next iteration
    v_previous_healthspan := v_assessments.expected_healthspan;
    v_count := v_count + 1;
  END LOOP;
  
  -- Update the user's current healthspan_years
  IF v_count > 0 THEN
    UPDATE users
    SET healthspan_years = v_accumulated_healthspan
    WHERE id = p_user_id;
  END IF;
  
  -- Return result
  v_result := jsonb_build_object(
    'success', true,
    'assessments_updated', v_count,
    'final_healthspan_years', v_accumulated_healthspan
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION fix_user_healthspan(UUID) TO public;

-- Create a function to fix all users' healthspan values
CREATE OR REPLACE FUNCTION fix_all_healthspans() RETURNS JSONB AS $$
DECLARE
  v_user RECORD;
  v_result JSONB;
  v_users_fixed INTEGER := 0;
  v_user_result JSONB;
BEGIN
  -- Process each user
  FOR v_user IN 
    SELECT DISTINCT user_id
    FROM health_assessments
  LOOP
    -- Fix this user's healthspan
    v_user_result := fix_user_healthspan(v_user.user_id);
    
    -- Count successful fixes
    IF (v_user_result->>'success')::BOOLEAN THEN
      v_users_fixed := v_users_fixed + 1;
    END IF;
  END LOOP;
  
  -- Return result
  v_result := jsonb_build_object(
    'success', true,
    'users_fixed', v_users_fixed
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION fix_all_healthspans() TO public;

-- Fix healthspan for user clay@healthrocket.life
DO $$
DECLARE
  v_user_id UUID;
  v_result JSONB;
BEGIN
  -- Get user ID for clay@healthrocket.life
  SELECT id INTO v_user_id
  FROM users
  WHERE email = 'clay@healthrocket.life';
  
  -- Fix healthspan for this user if found
  IF v_user_id IS NOT NULL THEN
    v_result := fix_user_healthspan(v_user_id);
    RAISE NOTICE 'Fixed healthspan for clay@healthrocket.life: %', v_result;
  END IF;
END $$;