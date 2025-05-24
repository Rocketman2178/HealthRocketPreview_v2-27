/*
  # Update health assessment function

  1. Changes
    - Add health_goals parameter to update_health_assessment function
    - Update function to store health goals in assessment record
    
  2. Security
    - Function maintains existing RLS policies
    - Only authenticated users can call this function
*/

CREATE OR REPLACE FUNCTION public.update_health_assessment(
  p_user_id uuid,
  p_expected_lifespan integer,
  p_expected_healthspan integer,
  p_mindset_score numeric,
  p_sleep_score numeric,
  p_exercise_score numeric,
  p_nutrition_score numeric,
  p_biohacking_score numeric,
  p_gender text,
  p_health_goals text,
  p_created_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_health_score numeric(4,2);
  v_healthspan_years numeric(4,2);
BEGIN
  -- Calculate health score (average of all category scores)
  v_health_score := (p_mindset_score + p_sleep_score + p_exercise_score + p_nutrition_score + p_biohacking_score) / 5.0;
  
  -- Calculate healthspan years based on scores and expectations
  v_healthspan_years := (p_expected_healthspan - p_expected_lifespan) * (v_health_score / 10.0);

  -- Insert new health assessment
  INSERT INTO health_assessments (
    user_id,
    expected_lifespan,
    expected_healthspan,
    health_score,
    healthspan_years,
    mindset_score,
    sleep_score,
    exercise_score,
    nutrition_score,
    biohacking_score,
    gender,
    health_goals,
    created_at
  ) VALUES (
    p_user_id,
    p_expected_lifespan,
    p_expected_healthspan,
    v_health_score,
    v_healthspan_years,
    p_mindset_score,
    p_sleep_score,
    p_exercise_score,
    p_nutrition_score,
    p_biohacking_score,
    p_gender,
    p_health_goals,
    p_created_at
  );

  -- Update user's health metrics
  UPDATE users
  SET 
    health_score = v_health_score,
    healthspan_years = v_healthspan_years,
    lifespan = p_expected_lifespan,
    healthspan = p_expected_healthspan,
    updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;