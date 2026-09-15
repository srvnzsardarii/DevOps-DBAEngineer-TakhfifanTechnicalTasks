-- اقدامات پیشگیرانه سطح دیتابیس (Preventive Measures)
-- هدف: در حادثه بعدی، تشخیص محدوده‌ی دقیق آسیب در چند ثانیه ممکن شود (نه با WAL forensics)
-- و از حذف/آپدیت غیرقابل‌برگشت روی جدول حیاتی تراکنش‌ها جلوگیری شود.

-- ۱) جدول Audit برای ثبت خودکار every DELETE/UPDATE روی payment_transactions
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    row_id BIGINT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT NOT NULL DEFAULT current_user,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_log_table_time ON audit_log (table_name, changed_at);

CREATE OR REPLACE FUNCTION fn_audit_payment_transactions() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, row_id, old_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.id, to_jsonb(OLD), current_user);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, row_id, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(OLD), to_jsonb(NEW), current_user);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_payment_transactions ON payment_transactions;
CREATE TRIGGER trg_audit_payment_transactions
    AFTER UPDATE OR DELETE ON payment_transactions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_payment_transactions();

-- با این جدول، در حادثه‌ی بعدی، بازیابی دقیق این‌طور ساده می‌شود:
--   SELECT * FROM audit_log
--   WHERE table_name = 'payment_transactions' AND changed_at BETWEEN '<incident_start>' AND '<incident_end>';
-- و می‌توان مستقیماً از old_data برای revert استفاده کرد، بدون نیاز به PITR clone.

-- ۲) Soft Delete: به‌جای DELETE واقعی، رکورد را غیرفعال می‌کنیم (برگشت‌پذیری کامل)
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION fn_prevent_hard_delete() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Hard DELETE روی payment_transactions مجاز نیست. از UPDATE deleted_at استفاده کنید.';
END;
$$ LANGUAGE plpgsql;

-- توجه: این تریگر عمداً به‌صورت کامنت گذاشته شده تا بعد از جابه‌جایی اپلیکیشن به الگوی
-- soft-delete، فعال شود (فعال‌سازی زودهنگام می‌تواند اپلیکیشن موجود را بشکند):
-- CREATE TRIGGER trg_prevent_hard_delete
--     BEFORE DELETE ON payment_transactions
--     FOR EACH ROW EXECUTE FUNCTION fn_prevent_hard_delete();

-- ۳) محدودسازی دسترسی: نقش migration فقط از طریق pipeline، نه اتصال مستقیم انسانی
REVOKE ALL ON payment_transactions FROM PUBLIC;
-- GRANT فقط به نقش اپلیکیشن و نقش CI/CD migration (با پسورد/mTLS مجزا و short-lived):
-- GRANT SELECT, INSERT, UPDATE ON payment_transactions TO app_payment_service;
-- GRANT ALL ON payment_transactions TO ci_migration_role; -- فقط از شبکه CI/CD runner
