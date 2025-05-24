/*
  # Delete User Migration

  1. Changes
    - Deletes user with email "everson1818@gmail.com" from both auth.users and public.users tables
    - Ensures proper order of operations to handle foreign key constraints
    
  2. Security
    - Uses admin-level SQL commands that require appropriate permissions
    - Should be run with caution as it permanently removes user data
*/

-- First delete from public.users (this should cascade to related tables)
DO $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Get the user ID from auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = 'everson1818@gmail.com';
  
  -- If user exists, delete from public.users
  IF v_user_id IS NOT NULL THEN
    -- Delete from public.users first (this should cascade to related tables)
    DELETE FROM public.users
    WHERE id = v_user_id;
    
    -- Then delete from auth.users
    DELETE FROM auth.users
    WHERE id = v_user_id;
    
    RAISE NOTICE 'User with email everson1818@gmail.com and ID % has been deleted', v_user_id;
  ELSE
    RAISE NOTICE 'User with email everson1818@gmail.com not found';
  END IF;
END $$;