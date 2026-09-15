#!/bin/bash
# فاز تشخیص (Detection): پیدا کردن زمان دقیق و محدوده رکوردهای آسیب‌دیده
# در محیط Production واقعی، منابع تشخیص باید این‌ها باشند (به‌ترتیب اولویت):
#
#   ۱) لاگ اپلیکیشن/CI-CD: کدام Job/Migration در چه ساعتی روی Master اجرا شده (بهترین منبع)
#   ۲) PostgreSQL log با log_statement=mod یا pgaudit: ثبت دقیق هر DELETE/UPDATE/INSERT
#   ۳) الگوهای غیرعادی در pg_stat_user_tables (جهش ناگهانی n_tup_del/n_tup_upd)
#   ۴) آلارم Prometheus (rate DELETE/UPDATE) که در monitoring/alert-rules.yaml تعریف شده
#   ۵) WAL خودِ Master (pg_waldump) برای تعیین دقیق LSN/timestamp تراکنش مخرب در نبود لاگ کافی
#
# این اسکریپت روش (۵) را نشان می‌دهد چون در سناریوی تسک فرض بر «فقط از طریق لاگ‌ها قابل شناسایی
# است» شده و ابزار قطعی‌تر از خودِ WAL برای این کار وجود ندارد.

set -euo pipefail

echo ">>> استخراج تراکنش‌های مشکوک از WAL (pg_waldump) حول ساعت حادثه"
WAL_ARCHIVE=/var/lib/postgresql/wal_archive
LATEST_WAL=$(ls -t "$WAL_ARCHIVE" | grep -v '\.backup$' | head -1)
echo "آخرین WAL segment آرشیوشده: $LATEST_WAL"

su postgres -c "/usr/lib/postgresql/16/bin/pg_waldump $WAL_ARCHIVE/$LATEST_WAL" 2>&1 | grep -E "COMMIT|desc: (DELETE|UPDATE|INSERT)" | tail -50 || true

echo ""
echo ">>> بررسی آماری جهش ناگهانی DML روی جدول (اگر Prometheus در دسترس نباشد)"
su postgres -c "psql -d payment -c \"
SELECT relname, n_tup_ins, n_tup_upd, n_tup_del, last_autoanalyze
FROM pg_stat_user_tables WHERE relname = 'payment_transactions';\""

echo ""
echo ">>> پیشنهاد: اگر audit trigger (docs/runbook.md بخش پیشگیری) از قبل فعال بود،"
echo "    محدوده‌ی دقیق رکوردهای آسیب‌دیده مستقیماً از جدول audit_log قابل استخراج بود:"
echo "    SELECT * FROM audit_log WHERE table_name='payment_transactions' AND changed_at BETWEEN ... ;"
