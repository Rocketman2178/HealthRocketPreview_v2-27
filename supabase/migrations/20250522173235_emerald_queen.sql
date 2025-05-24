/*
  # Fix get_latest_health_assessment function to handle empty results

  1. Changes
    - Drop existing get_latest_health_assessment function
    - Create new version that properly handles empty results
    - Grant execute permission to public
*/

-- Drop the existing function first
DROP FUNCTION IF EXISTS public.get_latest_health_assessment(uuid);

-- Create or replace the function to handle empty results properly
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
  
  -- If no rows are returned, the function will return an empty result set
  -- which is handled better by the client than a PGRST116 error
END;
$$;

-- Grant execute permission to public
GRANT EXECUTE ON FUNCTION public.get_latest_health_assessment(uuid) TO public;