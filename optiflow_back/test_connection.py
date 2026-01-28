import os
from supabase import create_client, Client

# --- PASTE YOUR CREDENTIALS HERE ---
url = "https://rtqgwssnrqjjmgpnttgq.supabase.co"  # Paste your Project URL here
key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0cWd3c3NucnFqam1ncG50dGdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk2MTg2MDMsImV4cCI6MjA4NTE5NDYwM30.9xXUA7MxrLgPMi2P9GmcyAnbU242xRgvbmenNLg8iE4"     # Paste your 'anon' Key here
# -----------------------------------

def test_the_brain():
    print("1. Attempting to connect to Supabase...")
    
    # Initialize the connection
    supabase: Client = create_client(url, key)
    
    print("2. Connection object created. Now fetching data...")

    # Ask the database for the list of machines we made earlier
    response = supabase.table('machines').select("*").execute()
    
    # Check if we got data back
    data = response.data
    
    if len(data) > 0:
        print("\nSUCCESS! 🚀 Connected to the database.")
        print("Here are the machines found in your cloud storage:")
        for machine in data:
            print(f" - {machine['name']} (Status: {machine['status']})")
    else:
        print("\nConnected, but the table is empty! (Did you run the INSERT SQL?)")

if __name__ == "__main__":
    test_the_brain()