/*
  # Add FP bonus for health assessment updates

  1. New Features
    - Adds FP bonus (10% of next level requirement) for health assessment updates
    - Excludes initial health assessment from receiving the bonus
    - Tracks FP earned in health_assessment_history table
    
  2. Changes
    - Updates the update_health_assessment_v2 function to award FP
    - Creates a function to calculate next level points
    - Adds trigger to handle health assessment completion
*/

-- Create a function to calculate next level points
CREATE OR REPLACE FUNCTION calculate_next_level_points(p_level INTEGER)
RETURNS INTEGER AS $$
DECLARE
  v_base_points INTEGER := 20;
  v_growth_factor NUMERIC := 1.414;
BEGIN
  RETURN ROUND(v_base_points * POWER(v_growth_factor, p_level - 1));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Update the health assessment function to award FP bonus
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
  v_is_first_assessment BOOLEAN;
  v_user_level INTEGER;
  v_fp_bonus INTEGER := 0;
  v_next_level_points INTEGER;
BEGIN
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

  -- Check if this is the first assessment
  v_is_first_assessment := v_previous_healthspan IS NULL;

  -- Calculate healthspan change (difference between new and previous expected healthspan)
  v_healthspan_change := p_expected_healthspan - COALESCE(v_previous_healthspan, p_expected_healthspan);
  
  -- Calculate total healthspan years (previous total + new change)
  -- If this is the first assessment, just use the change value
  v_healthspan_years := COALESCE(v_previous_healthspan_years, 0) + v_healthspan_change;

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

  -- If this is NOT the first assessment, award FP bonus
  IF NOT v_is_first_assessment THEN
    -- Get user's current level
    SELECT level INTO v_user_level
    FROM users
    WHERE id = p_user_id;
    
    -- Calculate next level points
    v_next_level_points := calculate_next_level_points(v_user_level);
    
    -- Calculate FP bonus (10% of next level requirement)
    v_fp_bonus := ROUND(v_next_level_points * 0.1);
    
    -- Award FP bonus
    UPDATE users
    SET 
      fuel_points = fuel_points + v_fp_bonus
    WHERE id = p_user_id;
    
    -- Record FP earning
    INSERT INTO fp_earnings (
      user_id,
      item_id,
      item_name,
      item_type,
      fp_amount,
      metadata
    ) VALUES (
      p_user_id,
      v_assessment_id::TEXT,
      'Health Assessment Update',
      'health_assessment',
      v_fp_bonus,
      jsonb_build_object(
        'health_score', p_health_score,
        'healthspan_years', v_healthspan_years,
        'healthspan_change', v_healthspan_change
      )
    );
  END IF;

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
    'fp_bonus', v_fp_bonus,
    'is_first_assessment', v_is_first_assessment
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
) TO public;

-- Create a function to handle health assessment completion
CREATE OR REPLACE FUNCTION handle_health_assessment_completion()
RETURNS TRIGGER AS $$
BEGIN
  -- Record the assessment in health_assessment_history
  INSERT INTO health_assessment_history (
    assessment_id,
    previous_assessment_id,
    user_id,
    healthscore_change,
    healthspan_change,
    lifespan_change
  )
  SELECT
    NEW.id,
    prev.id,
    NEW.user_id,
    NEW.health_score - COALESCE(prev.health_score, 0),
    NEW.healthspan_years - COALESCE(prev.healthspan_years, 0),
    NEW.expected_lifespan - COALESCE(prev.expected_lifespan, 0)
  FROM (
    SELECT id, health_score, healthspan_years, expected_lifespan
    FROM health_assessments
    WHERE user_id = NEW.user_id
      AND id != NEW.id
    ORDER BY created_at DESC
    LIMIT 1
  ) prev;
  
  -- Record category changes
  INSERT INTO health_category_history (
    assessment_id,
    category,
    previous_score,
    new_score,
    score_change,
    change_percentage
  )
  SELECT
    NEW.id,
    category,
    prev_score,
    new_score,
    new_score - prev_score,
    CASE WHEN prev_score > 0 THEN ((new_score - prev_score) / prev_score) * 100 ELSE 0 END
  FROM (
    SELECT 'mindset' AS category, COALESCE(prev.mindset_score, 0) AS prev_score, NEW.mindset_score AS new_score
    UNION ALL
    SELECT 'sleep', COALESCE(prev.sleep_score, 0), NEW.sleep_score
    UNION ALL
    SELECT 'exercise', COALESCE(prev.exercise_score, 0), NEW.exercise_score
    UNION ALL
    SELECT 'nutrition', COALESCE(prev.nutrition_score, 0), NEW.nutrition_score
    UNION ALL
    SELECT 'biohacking', COALESCE(prev.biohacking_score, 0), NEW.biohacking_score
  ) categories
  CROSS JOIN (
    SELECT mindset_score, sleep_score, exercise_score, nutrition_score, biohacking_score
    FROM health_assessments
    WHERE user_id = NEW.user_id
      AND id != NEW.id
    ORDER BY created_at DESC
    LIMIT 1
  ) prev;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'handle_health_assessment_completion'
  ) THEN
    CREATE TRIGGER handle_health_assessment_completion
    AFTER INSERT ON health_assessments
    FOR EACH ROW
    EXECUTE FUNCTION handle_health_assessment_completion();
  END IF;
END
$$;