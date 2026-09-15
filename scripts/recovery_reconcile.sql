-- اسکریپت بازیابی گزینشی (Selective Recovery) روی Master زنده
-- هدف: بازگرداندن فقط رکوردهای آسیب‌دیده از روی PITR clone (نسخه تمیز قبل از ۱۲:۴۵)
-- بدون تاثیر روی تراکنش‌های سالمی که *بعد* از حادثه ثبت شده‌اند.

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP SERVER IF EXISTS pitr_clone CASCADE;
CREATE SERVER pitr_clone FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host '127.0.0.1', port '5434', dbname 'payment');

CREATE USER MAPPING FOR postgres SERVER pitr_clone
  OPTIONS (user 'postgres');

CREATE FOREIGN TABLE clean_payment_transactions (
  id BIGINT,
  user_id INT,
  amount NUMERIC(12,2),
  status VARCHAR(20),
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) SERVER pitr_clone OPTIONS (schema_name 'public', table_name 'payment_transactions');

BEGIN;

-- ۱) بازگرداندن رکوردهای بهاشتباه حذف‌شده (id 50..64)
INSERT INTO payment_transactions (id, user_id, amount, status, created_at, updated_at)
SELECT id, user_id, amount, status, created_at, updated_at
FROM clean_payment_transactions
WHERE id NOT IN (SELECT id FROM payment_transactions)
ON CONFLICT (id) DO NOTHING;

-- ۲) بازگرداندن مقدار صحیح رکوردهای بهاشتباه آپدیت‌شده (id 80..89)
--    فقط رکوردهایی که هنوز روی master به وضعیت 'corrupted' هستند اصلاح می‌شوند
--    (اگر کاربر واقعی بعد از ساعت ۱۲:۴۵ همان رکورد را به‌درستی تغییر داده بود، دست نمی‌خورد)
UPDATE payment_transactions AS live
SET amount = clean.amount,
    status = clean.status,
    updated_at = clean.updated_at
FROM clean_payment_transactions AS clean
WHERE live.id = clean.id
  AND live.status = 'corrupted';

-- ۳) حذف رکوردهای ناقص/تکراری که در حادثه درج شده‌اند (هرگز در نسخه تمیز وجود نداشته‌اند)
DELETE FROM payment_transactions
WHERE status = 'dirty_duplicate';

COMMIT;

-- پاکسازی foreign server بعد از اتمام بازیابی
DROP SERVER pitr_clone CASCADE;
