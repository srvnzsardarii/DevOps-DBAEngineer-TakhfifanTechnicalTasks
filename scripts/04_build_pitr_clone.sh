#!/bin/bash
# ساخت PITR Clone (Forensic Copy): بازیابی از Base Backup + WAL Archive تا لحظه‌ی
# دقیق «قبل از commit تراکنش مخرب». این instance جدا و read-only است و هیچ اثری
# روی Master زنده یا سرویس Payment ندارد => RTO این مرحله صفر است.
#
# استفاده: ./04_build_pitr_clone.sh "2026-09-14 18:18:07.891478+00"
set -euo pipefail

TARGET_TIME="${1:?زمان هدف PITR را به‌عنوان آرگومان بدهید, مثال: '2026-09-14 18:18:07.891478+00'}"
PGVER=16
BASEBACKUP_DIR=/var/lib/postgresql/$PGVER/basebackup
PITR_DIR=/var/lib/postgresql/$PGVER/pitr_clone
WAL_ARCHIVE=/var/lib/postgresql/wal_archive

echo ">>> ساخت instance موقت PITR روی پورت 5434 با هدف زمانی: $TARGET_TIME"

rm -rf "$PITR_DIR"
cp -r "$BASEBACKUP_DIR" "$PITR_DIR"
rm -f "$PITR_DIR/standby.signal"
touch "$PITR_DIR/recovery.signal"

cp /etc/postgresql/$PGVER/main/postgresql.conf "$PITR_DIR/postgresql.conf"
cp /etc/postgresql/$PGVER/main/pg_hba.conf "$PITR_DIR/pg_hba.conf"
cp /etc/postgresql/$PGVER/main/pg_ident.conf "$PITR_DIR/pg_ident.conf"
mkdir -p "$PITR_DIR/conf.d"

sed -i "s|^data_directory.*|data_directory = '$PITR_DIR'|" "$PITR_DIR/postgresql.conf"
sed -i "s|^hba_file.*|hba_file = '$PITR_DIR/pg_hba.conf'|" "$PITR_DIR/postgresql.conf"
sed -i "s|^ident_file.*|ident_file = '$PITR_DIR/pg_ident.conf'|" "$PITR_DIR/postgresql.conf"
sed -i "s/^port.*/port = 5434/" "$PITR_DIR/postgresql.conf"
sed -i "/primary_conninfo/d" "$PITR_DIR/postgresql.auto.conf" 2>/dev/null || true

# اجازه اتصال controlled برای فرآیند بازیابی گزینشی (فقط postgres، فقط از localhost)
sed -i '0,/^host/s//host    all             postgres        127.0.0.1\/32            trust\nhost/' "$PITR_DIR/pg_hba.conf"

cat >> "$PITR_DIR/postgresql.conf" << EOF
restore_command = 'cp $WAL_ARCHIVE/%f %p'
recovery_target_time = '$TARGET_TIME'
recovery_target_action = 'pause'
EOF

chown -R postgres:postgres "$PITR_DIR"

su postgres -c "/usr/lib/postgresql/$PGVER/bin/pg_ctl -D $PITR_DIR -o '-c config_file=$PITR_DIR/postgresql.conf' -l /tmp/pitr.log start"
sleep 4
tail -20 /tmp/pitr.log

echo ""
echo ">>> تایید صحت داده در نسخه Golden Copy (پورت 5434):"
su postgres -c "psql -p 5434 -d payment -c \"SELECT count(*) AS total, count(*) FILTER (WHERE status='corrupted') AS corrupted, count(*) FILTER (WHERE status='dirty_duplicate') AS dirty FROM payment_transactions;\""

echo ""
echo "PITR clone آماده است روی پورت 5434 (read-only, paused در نقطه هدف)."
echo "مرحله بعد: اجرای 05_reconcile_and_recover.sh"
