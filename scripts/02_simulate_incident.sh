#!/bin/bash
# شبیه‌سازی حادثه: اجرای مستقیم یک اسکریپت اشتباه روی Master
# این اسکریپت زمان دقیق شروع/پایان را ثبت می‌کند تا در فاز تشخیص (Detection) قابل استفاده باشد.
set -euo pipefail

echo ">>> ثبت نقطه امن (Pre-Incident Checkpoint) برای استفاده در PITR"
su postgres -c "psql -d payment -t -c \"SELECT now();\"" | tee /tmp/pre_incident_checkpoint.txt

echo ">>> اجرای اسکریپت مخرب روی Master (شبیه‌سازی حادثه ساعت ۱۲:۴۵)"
su postgres -c "psql -d payment -t -c \"SELECT now();\"" | tee /tmp/incident_start.txt
su postgres -c "psql -d payment -f /home/claude/repo/sql/incident_simulation.sql"
su postgres -c "psql -d payment -t -c \"SELECT now();\"" | tee /tmp/incident_end.txt

echo ">>> وادار کردن Master به آرشیو کردن WAL جاری (شامل تراکنش حادثه)"
su postgres -c "psql -c \"SELECT pg_switch_wal();\""
sleep 1
su postgres -c "psql -c \"SELECT pg_switch_wal();\""

echo ">>> شبیه‌سازی تراکنش‌های سالم بعد از حادثه (که باید در بازیابی حفظ شوند)"
su postgres -c "psql -d payment -c \"
INSERT INTO payment_transactions (user_id, amount, status, created_at)
SELECT (random()*1000)::int, (random()*500+10)::numeric(12,2), 'completed', now()
FROM generate_series(1,20) g;\""

echo ">>> وضعیت فعلی Master:"
su postgres -c "psql -d payment -c \"SELECT count(*) AS total, count(*) FILTER (WHERE status='corrupted') AS corrupted, count(*) FILTER (WHERE status='dirty_duplicate') AS dirty FROM payment_transactions;\""

echo ">>> بررسی انتقال حادثه به Slave (باید 'کثیف' باشد)"
sleep 2
su postgres -c "psql -p 5433 -d payment -c \"SELECT count(*) AS total, count(*) FILTER (WHERE status='corrupted') AS corrupted, count(*) FILTER (WHERE status='dirty_duplicate') AS dirty FROM payment_transactions;\""

echo ""
echo "زمان‌های ثبت‌شده برای فاز بازیابی:"
echo "  pre_incident_checkpoint: $(cat /tmp/pre_incident_checkpoint.txt)"
echo "  incident_start:          $(cat /tmp/incident_start.txt)"
echo "  incident_end:            $(cat /tmp/incident_end.txt)"
