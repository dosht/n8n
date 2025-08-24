#!/bin/bash
set -e

# This script runs when the PostgreSQL container starts for the first time
# It's used to initialize the database with any required extensions or data

echo "Initializing n8n database..."

# Create database if it doesn't exist
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create any extensions if needed
    -- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    
    -- Grant permissions
    GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;
EOSQL

echo "Database initialization complete."
