#!/bin/bash

echo "[CRON] Phase2 START $(date)"

echo "cd /var/www/html/opencapture/src"

echo "Execution CRON."

python -m backend.scripts.phase2_from_db

echo "[CRON] Phase2 END $(date)"