/*
  # Add FP Bonus for Health Assessment Updates

  1. New Features
    - Adds FP bonus (10% of next level requirement) for health assessment updates
    - Tracks FP earnings in fp_earnings table
    - Excludes initial health assessment from receiving bonus
    
  2. Changes
    - Creates calculate_next_level_points function to determine FP needed for next level
    - Updates update_health_assessment_v2 function to award FP bonus
    - Adds proper tracking of FP earnings
*/

-- Create function to calculate next level points (same formula as frontend)
CREATE OR REPLACE FUNCTION calculate_next_level_points(p_level INTEGER)
RETURNS INTEGER AS $$
DECLARE
  v_base_points INTEGER := 20;
  v_growth_factor NUMERIC := 1.414;
BEGIN
  RETURN ROUND(v_base_points * POWER(v_growth_factor, p_level - 1));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION calculate_next_level_points(INTEGER) TO public;

-- Drop the existing function to replace it
DROP FUNCTION IF EXISTS update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
);

-- Create updated function with FP bonus for non-first assessments
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
  v_next_level_points INTEGER;
  v_fp_bonus INTEGER;
  v_fp_earning_id UUID;
BEGIN
  -- Check if this is the first assessment
  SELECT COUNT(*) = 0 INTO v_is_first_assessment
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

  -- Update user's health metrics
  UPDATE users
  SET 
    health_score = p_health_score,
    healthspan_years = v_healthspan_years,
    lifespan = p_expected_lifespan,
    healthspan = p_expected_healthspan
  WHERE id = p_user_id;
  
  -- Award FP bonus for non-first assessments (10% of next level requirement)
  IF NOT v_is_first_assessment THEN
    -- Get user's current level
    SELECT level INTO v_user_level
    FROM users
    WHERE id = p_user_id;
    
    -- Calculate next level points
    v_next_level_points := calculate_next_level_points(v_user_level);
    
    -- Calculate FP bonus (10% of next level requirement)
    v_fp_bonus := GREATEST(1, ROUND(v_next_level_points * 0.1));
    
    -- Update user's fuel points
    UPDATE users
    SET fuel_points = fuel_points + v_fp_bonus,
        days_since_fp = 0
    WHERE id = p_user_id;
    
    -- Record FP earning
    INSERT INTO fp_earnings (
      user_id,
      item_id,
      item_name,
      item_type,
      health_category,
      fp_amount,
      metadata
    ) VALUES (
      p_user_id,
      v_assessment_id::TEXT,
      'Health Assessment Update',
      'health_assessment',
      'general',
      v_fp_bonus,
      jsonb_build_object(
        'assessment_id', v_assessment_id,
        'health_score', p_health_score,
        'healthspan_years', v_healthspan_years,
        'healthspan_change', v_healthspan_change
      )
    )
    RETURNING id INTO v_fp_earning_id;
  ELSE
    -- No FP bonus for first assessment
    v_fp_bonus := 0;
  END IF;

  -- Return success with assessment details and FP bonus
  v_result := jsonb_build_object(
    'success', true,
    'assessment_id', v_assessment_id,
    'healthspan_years', v_healthspan_years,
    'healthspan_change', v_healthspan_change,
    'is_first_assessment', v_is_first_assessment,
    'fp_bonus', v_fp_bonus
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION update_health_assessment_v2(
  UUID, INTEGER, INTEGER, NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), 
  NUMERIC(4,2), NUMERIC(4,2), NUMERIC(4,2), TIMESTAMPTZ, TEXT, TEXT
) TO public;

-- Create a trigger function to record health assessment history
CREATE OR REPLACE FUNCTION handle_health_assessment_completion()
RETURNS TRIGGER AS $$
DECLARE
  v_previous_assessment_id UUID;
  v_previous_health_score NUMERIC(4,2);
  v_previous_healthspan_years NUMERIC(4,2);
  v_healthscore_change NUMERIC(4,2);
  v_healthspan_change NUMERIC(4,2);
  v_lifespan_change INTEGER;
  v_history_id UUID;
  v_category_names TEXT[] := ARRAY['mindset', 'sleep', 'exercise', 'nutrition', 'biohacking'];
  v_category TEXT;
  v_new_score NUMERIC(4,2);
  v_previous_score NUMERIC(4,2);
  v_score_change NUMERIC(4,2);
  v_change_percentage NUMERIC(5,2);
BEGIN
  -- Get previous assessment
  SELECT 
    id, 
    health_score,
    healthspan_years
  INTO 
    v_previous_assessment_id,
    v_previous_health_score,
    v_previous_healthspan_years
  FROM health_assessments
  WHERE user_id = NEW.user_id
    AND id != NEW.id
  ORDER BY created_at DESC
  LIMIT 1;
  
  -- Calculate changes
  v_healthscore_change := NEW.health_score - COALESCE(v_previous_health_score, NEW.health_score);
  v_healthspan_change := NEW.healthspan_years - COALESCE(v_previous_healthspan_years, 0);
  v_lifespan_change := NEW.expected_lifespan - COALESCE(
    (SELECT expected_lifespan FROM health_assessments WHERE id = v_previous_assessment_id),
    NEW.expected_lifespan
  );
  
  -- Record assessment history
  INSERT INTO health_assessment_history (
    assessment_id,
    previous_assessment_id,
    user_id,
    healthscore_change,
    healthspan_change,
    lifespan_change
  ) VALUES (
    NEW.id,
    v_previous_assessment_id,
    NEW.user_id,
    v_healthscore_change,
    v_healthspan_change,
    v_lifespan_change
  )
  RETURNING id INTO v_history_id;
  
  -- Record category-specific changes
  FOREACH v_category IN ARRAY v_category_names
  LOOP
    EXECUTE format('SELECT $1.%I', v_category || '_score')
    USING NEW
    INTO v_new_score;
    
    IF v_previous_assessment_id IS NOT NULL THEN
      EXECUTE format('SELECT $1.%I', v_category || '_score')
      USING (SELECT * FROM health_assessments WHERE id = v_previous_assessment_id)
      INTO v_previous_score;
    ELSE
      v_previous_score := v_new_score;
    END IF;
    
    v_score_change := v_new_score - v_previous_score;
    
    -- Calculate percentage change (avoid division by zero)
    IF v_previous_score > 0 THEN
      v_change_percentage := (v_score_change / v_previous_score) * 100;
    ELSE
      v_change_percentage := 0;
    END IF;
    
    -- Insert category history
    INSERT INTO health_category_history (
      assessment_id,
      category,
      previous_score,
      new_score,
      score_change,
      change_percentage
    ) VALUES (
      NEW.id,
      v_category,
      v_previous_score,
      v_new_score,
      v_score_change,
      v_change_percentage
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create or replace the trigger
DROP TRIGGER IF EXISTS handle_health_assessment_completion ON health_assessments;
CREATE TRIGGER handle_health_assessment_completion
AFTER INSERT ON health_assessments
FOR EACH ROW
EXECUTE FUNCTION handle_health_assessment_completion();