-- اسکریپت شبیه‌ساز حادثه: اجرای اشتباه یک migration/اسکریپت مستقیم روی Master
-- این معادل «اسکریپت اشتباه ساعت ۱۲:۴۵» در سناریوی تسک است

BEGIN;

-- ۱) حذف اشتباه ۱۵ تراکنش (id های ۵۰ تا ۶۴)
DELETE FROM payment_transactions WHERE id BETWEEN 50 AND 64;

-- ۲) آپدیت اشتباه مبلغ و وضعیت ۱۰ تراکنش (id های ۸۰ تا ۸۹) - شبیه‌سازی باگ در migration
UPDATE payment_transactions
SET amount = 0.00, status = 'corrupted', updated_at = now()
WHERE id BETWEEN 80 AND 89;

-- ۳) درج ۳ رکورد ناقص/تکراری (کپی اشتباه از رکوردهای موجود بدون amount صحیح)
INSERT INTO payment_transactions (user_id, amount, status, created_at, updated_at)
SELECT user_id, 0.00, 'dirty_duplicate', created_at, now()
FROM payment_transactions WHERE id IN (100, 101, 102);

COMMIT;
