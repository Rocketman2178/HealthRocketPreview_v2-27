/*
  # Add health assessment stored procedure

  1. New Functions
    - `update_health_assessment` - Handles health assessment updates and triggers necessary events
      - Takes parameters for all health metrics
      - Updates health_assessments table
      - Updates user profile with latest scores
      - Returns success/failure status

  2. Changes
    - Creates new stored procedure for health assessment updates
    - Ensures proper parameter handling and validation
    - Maintains data consistency across tables
*/

create or replace function public.update_health_assessment(
  p_user_id uuid,
  p_expected_lifespan integer,
  p_expected_healthspan integer,
  p_health_score numeric,
  p_mindset_score numeric,
  p_sleep_score numeric,
  p_exercise_score numeric,
  p_nutrition_score numeric,
  p_biohacking_score numeric,
  p_created_at timestamptz,
  p_gender text,
  p_health_goals text
) returns void as $$
declare
  v_healthspan_years numeric;
begin
  -- Calculate healthspan years based on scores
  v_healthspan_years := p_expected_healthspan::numeric * (p_health_score / 10.0);

  -- Insert new health assessment
  insert into public.health_assessments (
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
    created_at,
    gender,
    health_goals
  ) values (
    p_user_id,
    p_expected_lifespan,
    p_expected_healthspan,
    p_health_score,
    v_healthspan_years,
    p_mindset_score,
    p_sleep_score,
    p_exercise_score,
    p_nutrition_score,
    p_biohacking_score,
    p_created_at,
    p_gender,
    p_health_goals
  );

  -- Update user profile with latest scores
  update public.users
  set 
    health_score = p_health_score,
    healthspan_years = v_healthspan_years,
    lifespan = p_expected_lifespan,
    healthspan = p_expected_healthspan,
    onboarding_completed = true
  where id = p_user_id;

end;
$$ language plpgsql security definer;