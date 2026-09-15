#!/bin/bash
# سناریوی Fallback: اگر خرابی آنقدر شدید بود که به Standby اعتماد نبود (مثلاً خرابی
# در سطح فایل/Storage، نه فقط داده منطقی)، یا اگر replication slot/WAL gap باعث شد
# Standby دیگر نتواند به‌سادگی streaming را ادامه دهد، باید Slave را کامل از نو ساخت.
#
# نکته مهم: در سناریوی اصلی این تسک (خرابی صرفاً منطقی/داده‌ای) به این اسکریپت نیازی
# نبود — همان‌طور که evidence/terminal-transcript.md نشان می‌دهد، اصلاح روی Master با
# DML عادی به‌طور خودکار و بدون rebuild به Slave replicate شد. این اسکریپت صرفاً برای
# پوشش حالت بدتر (Disaster Recovery سخت‌گیرانه‌تر) نگه‌داشته شده.
set -euo pipefail

PGVER=16
SLAVE_DIR=/var/lib/postgresql/$PGVER/slave

echo ">>> توقف Slave قدیمی (احتمالاً corrupted/diverged)"
su postgres -c "/usr/lib/postgresql/$PGVER/bin/pg_ctl -D $SLAVE_DIR stop -m immediate" || true
rm -rf "$SLAVE_DIR"

echo ">>> گرفتن Base Backup تازه از Master (که الان تمیز است)"
su postgres -c "PGPASSWORD=repl_pass123 pg_basebackup -h 127.0.0.1 -U replicator -D $SLAVE_DIR -Fp -Xs -P -R --checkpoint=fast"

cp /etc/postgresql/$PGVER/main/postgresql.conf "$SLAVE_DIR/postgresql.conf"
cp /etc/postgresql/$PGVER/main/pg_hba.conf "$SLAVE_DIR/pg_hba.conf"
cp /etc/postgresql/$PGVER/main/pg_ident.conf "$SLAVE_DIR/pg_ident.conf"
mkdir -p "$SLAVE_DIR/conf.d"
sed -i "s|^data_directory.*|data_directory = '$SLAVE_DIR'|" "$SLAVE_DIR/postgresql.conf"
sed -i "s|^hba_file.*|hba_file = '$SLAVE_DIR/pg_hba.conf'|" "$SLAVE_DIR/postgresql.conf"
sed -i "s|^ident_file.*|ident_file = '$SLAVE_DIR/pg_ident.conf'|" "$SLAVE_DIR/postgresql.conf"
sed -i "s/^port.*/port = 5433/" "$SLAVE_DIR/postgresql.conf"
chown -R postgres:postgres "$SLAVE_DIR"

su postgres -c "/usr/lib/postgresql/$PGVER/bin/pg_ctl -D $SLAVE_DIR -o '-c config_file=$SLAVE_DIR/postgresql.conf' -l /tmp/slave.log start"
sleep 3
su postgres -c "psql -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""
echo "Slave از نو ساخته و به Streaming Replication وصل شد."
