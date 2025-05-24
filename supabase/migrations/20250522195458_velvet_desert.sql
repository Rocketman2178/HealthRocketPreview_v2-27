/*
  # Fix health data display in dashboard

  1. New Functions
    - Improved get_latest_health_assessment function to properly return user's health data
    
  2. Changes
    - Adds a more reliable function to fetch the latest health assessment data
    - Ensures health data is properly displayed in the UI
*/

-- Drop the existing function if it exists
DROP FUNCTION IF EXISTS public.get_latest_health_assessment(uuid);

-- Create an improved function to get the latest health assessment
CREATE OR REPLACE FUNCTION public.get_latest_health_assessment(p_user_id uuid)
RETURNS SETOF public.health_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT *
  FROM public.health_assessments
  WHERE user_id = p_user_id
  ORDER BY created_at DESC
  LIMIT 1;
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.get_latest_health_assessment(uuid) TO public;

-- Create a function to get health data directly
CREATE OR REPLACE FUNCTION public.get_user_health_data(p_user_id uuid)
RETURNS TABLE(
  health_score numeric(4,2),
  healthspan_years numeric(4,2),
  expected_lifespan integer,
  expected_healthspan integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ha.health_score,
    ha.healthspan_years,
    ha.expected_lifespan,
    ha.expected_healthspan
  FROM health_assessments ha
  WHERE ha.user_id = p_user_id
  ORDER BY ha.created_at DESC
  LIMIT 1;
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.get_user_health_data(uuid) TO public;