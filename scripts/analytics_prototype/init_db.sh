#!/bin/bash
# scripts/analytics_prototype/init_db.sh
set -e

echo "Initializing Ephemeral PostgreSQL DB for Analytics Prototype..."
# Using the default postgres DB available in the sandbox. We'll create the schema.
sudo -u postgres psql -c "DROP DATABASE IF EXISTS mica_analytics_prototype;"
sudo -u postgres psql -c "CREATE DATABASE mica_analytics_prototype;"

echo "Loading RAW Schema..."
sudo -u postgres psql -d mica_analytics_prototype -f sql/design/analytics_raw_schema.sql

echo "Loading Dimensional Schema..."
sudo -u postgres psql -d mica_analytics_prototype -f sql/design/analytics_schema.sql

echo "Database initialization complete."