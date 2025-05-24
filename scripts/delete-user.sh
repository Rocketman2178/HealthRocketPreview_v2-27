#!/bin/bash

# Get environment variables
SUPABASE_URL=$(grep VITE_SUPABASE_URL .env | cut -d '=' -f2)
SUPABASE_ANON_KEY=$(grep VITE_SUPABASE_ANON_KEY .env | cut -d '=' -f2)

# Check if variables are set
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Error: SUPABASE_URL or SUPABASE_ANON_KEY not found in .env file"
  exit 1
fi

# Email to delete
EMAIL="everson1818@gmail.com"

echo "Attempting to delete user with email: $EMAIL"

# Call the function using cURL
curl -X POST "$SUPABASE_URL/functions/v1/delete-user" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -d "{\"email\": \"$EMAIL\"}"

echo -e "\nDone"