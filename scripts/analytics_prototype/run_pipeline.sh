#!/bin/bash
# scripts/analytics_prototype/run_pipeline.sh
set -e

echo "Running ETL Transformations (RAW -> Dimensional)..."
sudo -u postgres psql -d mica_analytics_prototype -f sql/design/analytics_transformations.sql

echo "Pipeline executed successfully."