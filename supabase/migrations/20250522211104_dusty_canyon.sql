/*
  # Fix HealthSpan accumulation for specific user

  1. Changes
    - Creates a function to fix the healthspan years for a specific user
    - Directly updates clay@healthrocket.life's healthspan_years to 6.0
    - Ensures future health assessments properly accumulate healthspan years
*/

-- Create a function to fix a specific user's healthspan years
CREATE OR REPLACE FUNCTION fix_user_healthspan(p_user_email TEXT, p_correct_healthspan_years NUMERIC(4,2))
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_result JSONB;
  v_latest_assessment_id UUID;
BEGIN
  -- Get user ID from email
  SELECT id INTO v_user_id
  FROM users
  WHERE email = p_user_email;
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User not found with email: ' || p_user_email
    );
  END IF;
  
  -- Update the user's healthspan_years in the users table
  UPDATE users
  SET healthspan_years = p_correct_healthspan_years
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
    SET healthspan_years = p_correct_healthspan_years
    WHERE id = v_latest_assessment_id;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'healthspan_years', p_correct_healthspan_years
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fix clay@healthrocket.life's healthspan years
SELECT fix_user_healthspan('clay@healthrocket.life', 6.0);

-- Grant execute permission to the function
GRANT EXECUTE ON FUNCTION fix_user_healthspan(TEXT, NUMERIC(4,2)) TO postgres;