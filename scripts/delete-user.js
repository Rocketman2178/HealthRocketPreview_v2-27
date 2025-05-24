// Script to delete a user from both auth and public tables
const deleteUser = async (email) => {
  try {
    const SUPABASE_URL = process.env.VITE_SUPABASE_URL;
    if (!SUPABASE_URL) {
      throw new Error('SUPABASE_URL environment variable is not set');
    }

    console.log(`Attempting to delete user with email: ${email}`);
    
    const response = await fetch(
      `${SUPABASE_URL}/functions/v1/delete-user`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.VITE_SUPABASE_ANON_KEY}`
        },
        body: JSON.stringify({ email })
      }
    );

    const data = await response.json();
    
    if (!response.ok) {
      throw new Error(data.error || 'Failed to delete user');
    }

    console.log('Success:', data.message);
    return data;
  } catch (error) {
    console.error('Error deleting user:', error);
    throw error;
  }
};

// Execute the function with the specified email
const email = 'everson1818@gmail.com';
deleteUser(email)
  .then(result => console.log('Operation completed successfully'))
  .catch(error => console.error('Operation failed:', error));