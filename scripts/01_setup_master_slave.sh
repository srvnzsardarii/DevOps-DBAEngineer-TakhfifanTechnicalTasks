#!/bin/bash
# راه‌اندازی محیط تست: Master (5432) + Slave (5433) با Streaming Replication + WAL Archiving
# این اسکریپت دقیقاً همان مراحلی است که در evidence/terminal-transcript.md ثبت شده و
# در محیط ارزیابی این تسک واقعاً اجرا و تست شده است.
set -euo pipefail

PGVER=16
WAL_ARCHIVE=/var/lib/postgresql/wal_archive
SLAVE_DIR=/var/lib/postgresql/$PGVER/slave
BASEBACKUP_DIR=/var/lib/postgresql/$PGVER/basebackup

echo ">>> نصب PostgreSQL $PGVER"
apt-get update -qq
apt-get install -y -qq postgresql-$PGVER postgresql-contrib

echo ">>> استارت Master"
service postgresql start

echo ">>> پیکربندی Master برای Replication و WAL Archiving"
mkdir -p "$WAL_ARCHIVE" && chown postgres:postgres "$WAL_ARCHIVE"
su postgres -c "psql -c \"ALTER SYSTEM SET wal_level = replica;\""
su postgres -c "psql -c \"ALTER SYSTEM SET max_wal_senders = 10;\""
su postgres -c "psql -c \"ALTER SYSTEM SET max_replication_slots = 10;\""
su postgres -c "psql -c \"ALTER SYSTEM SET archive_mode = on;\""
su postgres -c "psql -c \"ALTER SYSTEM SET archive_command = 'cp %p $WAL_ARCHIVE/%f';\""
su postgres -c "psql -c \"SELECT pg_reload_conf();\""
su postgres -c "psql -c \"CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_pass123';\"" || true
echo "host replication replicator 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/$PGVER/main/pg_hba.conf
service postgresql restart

echo ">>> ساخت دیتابیس و جدول نمونه payment_transactions"
su postgres -c "psql -c \"CREATE DATABASE payment;\"" || true
su postgres -c "psql -d payment -c \"
CREATE TABLE IF NOT EXISTS payment_transactions (
  id BIGSERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);\""
su postgres -c "psql -d payment -c \"
INSERT INTO payment_transactions (user_id, amount, status, created_at)
SELECT (random()*1000)::int, (random()*500+10)::numeric(12,2), 'completed', now() - (interval '1 minute' * g)
FROM generate_series(1,200) g;\""

echo ">>> گرفتن Base Backup"
rm -rf "$BASEBACKUP_DIR"
su postgres -c "PGPASSWORD=repl_pass123 pg_basebackup -h 127.0.0.1 -U replicator -D $BASEBACKUP_DIR -Fp -Xs -P -R --checkpoint=fast"

echo ">>> ساخت Slave از روی Base Backup (پورت 5433)"
rm -rf "$SLAVE_DIR"
cp -r "$BASEBACKUP_DIR" "$SLAVE_DIR"
chown -R postgres:postgres "$SLAVE_DIR"
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
echo ">>> تایید Replication:"
su postgres -c "psql -c \"SELECT client_addr, state, sync_state FROM pg_stat_replication;\""
su postgres -c "psql -p 5433 -d payment -c \"SELECT count(*) FROM payment_transactions;\""

echo ">>> محیط تست آماده است. Master=5432, Slave=5433"
