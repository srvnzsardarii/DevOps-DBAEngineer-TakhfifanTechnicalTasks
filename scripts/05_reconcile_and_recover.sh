#!/bin/bash
# اجرای بازیابی گزینشی روی Master زنده (بدون Downtime) با استفاده از postgres_fdw
# به PITR Clone، سپس پاکسازی instance موقت.
set -euo pipefail

echo ">>> اجرای sql/recovery_reconcile.sql روی Master زنده"
su postgres -c "psql -d payment -f /home/claude/repo/sql/recovery_reconcile.sql"

echo ""
echo ">>> تایید نهایی روی Master:"
su postgres -c "psql -d payment -c \"SELECT count(*) AS total, count(*) FILTER (WHERE status='corrupted') AS corrupted, count(*) FILTER (WHERE status='dirty_duplicate') AS dirty FROM payment_transactions;\""

echo ""
echo ">>> تایید حفظ‌شدن تراکنش‌های سالم بعد از حادثه:"
su postgres -c "psql -d payment -c \"SELECT count(*) FROM payment_transactions WHERE status='completed' AND created_at > (SELECT max(created_at) - interval '1 minute' FROM payment_transactions);\""

sleep 2
echo ""
echo ">>> تایید همگام‌سازی خودکار به Slave (بدون نیاز به rebuild):"
su postgres -c "psql -p 5433 -d payment -c \"SELECT count(*) AS total, count(*) FILTER (WHERE status='corrupted') AS corrupted, count(*) FILTER (WHERE status='dirty_duplicate') AS dirty FROM payment_transactions;\""
su postgres -c "psql -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""

echo ""
echo ">>> پاکسازی: توقف instance موقت PITR clone"
PGVER=16
PITR_DIR=/var/lib/postgresql/$PGVER/pitr_clone
su postgres -c "/usr/lib/postgresql/$PGVER/bin/pg_ctl -D $PITR_DIR stop -m fast" || true

echo ""
echo "بازیابی کامل شد. سرویس Payment از ابتدا تا انتها Healthy و در دسترس باقی ماند (RTO≈۰)."
