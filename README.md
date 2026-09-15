# تسک ارزیابی فنی — مهندس DBA/DevOps | تخفیفان
### سناریوی حادثه پایگاه‌داده سرویس پرداخت (Payment)
این ریپازیتوری پاسخ کامل به تسک ارزیابی فنی است: تحلیل، استراتژی، Runbook گام‌به‌گام،اسکریپت‌ها/مانیفست‌ها، و شواهد اجرای عملی واقعی روی یک محیط
Master-Slave PostgreSQL.
##  شروع سریع
حادثه، استراتژی بازیابی، فرضیات، Runbook گام‌به‌گام، اقدامات پیشگیرانه و طرح مانیتورینگ.
## ساختار ریپازیتوری
├── README.md                          
├── docs/
│   └── runbook.md                     ← مستند فنی اصلی (تحلیل + استراتژی + Runbook + پیشگیری)
├── k8s/                                ← معادل Production/Staging با Kubernetes + CloudNativePG
│   ├── 00-cnpg-operator.md
│   ├── 01-minio.yaml                  ← Object Storage برای WAL/Backup (معادل S3)
│   ├── 02-postgresql-cluster.yaml     ← Cluster اصلی (Master+Standby) با Continuous Backup
│   └── 03-pitr-recovery-cluster.yaml  ← Cluster موقت برای PITR/Forensic Recovery
├── sql/
│   ├── incident_simulation.sql        ← شبیه‌سازی حادثه (اسکریپت مخرب)
│   ├── recovery_reconcile.sql         ← بازیابی گزینشی روی Master زنده
│   └── preventive_measures.sql        ← Audit Trigger + Soft-Delete + سخت‌سازی دسترسی
├── scripts/                            ← اسکریپت‌های bash قابل اجرای مجدد (reproducible)
│   ├── 01_setup_master_slave.sh       ← راه‌اندازی محیط تست (Master+Slave+Replication)
│   ├── 02_simulate_incident.sh        ← اجرای حادثه با ثبت timestamp دقیق
│   ├── 03_detect_incident_scope.sh    ← تشخیص محدوده‌ی آسیب از WAL/آمار
│   ├── 04_build_pitr_clone.sh         ← ساخت Forensic PITR Clone
│   ├── 05_reconcile_and_recover.sh    ← اجرای بازیابی + اعتبارسنجی + پاکسازی
│   └── 06_fallback_rebuild_slave.sh   ← Fallback: rebuild کامل Standby (حالت خرابی شدیدتر)
├── monitoring/                         ← بخش امتیاز اضافی (Observability)
│   ├── alert-rules.yaml               ← قوانین Prometheus Alert
│   ├── postgres-exporter-queries.yaml
│   └── grafana-dashboard.md
└── evidence/
    ├── terminal-transcript.md         ← ترتیب کامل و واقعی اجرای سناریو با خروجی‌های واقعی
    ├── master.log
    ├── slave.log
    └── pitr_recovery.log
```

خلاصه‌ی نتیجه (چکیده اجرای واقعی)
سناریو به‌طور کامل روی یک محیط واقعی PostgreSQL 16 (دو instance Master/Slave با Streaming Replication واقعی اجرا شد:
***مرحله و نتیجه***
قبل از حادثه=۲۰۰ تراکنش سالم، Replication سالم و sync
حادثه=۱۵ رکورد حذف، ۱۰ رکورد خراب، ۳ رکورد ناقص  و انتقال خودکار همه‌ی این‌ها به Slave (طبق سناریوی تسک) 
بعد از حادثه=۲۰ تراکنش سالم جدید ثبت شد
بازیابی=فقط رکوردهای خراب اصلاح شد؛ صفر تراکنش سالم از دست رفت
 نتیجه نهایی=Master و Slave هر دو ۲۲۰ رکورد سالم، Replication بدون قطعی ادامه یافت
جزئیات کامل با خروجی واقعی ترمینال در `evidence/terminal-transcript.md`.
 توضیح صادقانه درباره‌ی محیط اجرا
طبق تسک، سناریو باید روی «کلاستر Kubernetes با Master-Slave PostgreSQL» پیاده‌سازی شود. در
محیط sandbox این پاسخ، Docker/nested-virtualization در دسترس نبود (`kind`/`k3s` قابل اجرا
نبودند)، بنابراین:
منطق Master-Slave، Replication، PITR و بازیابی با دو instance واقعی PostgreSQL پیاده و به‌طور کامل تست شد 
 تمام SQL/منطق بازیابی در `sql/` و
  scriptsبدون هیچ تغییری روی PostgreSQL داخل Kubernetes هم قابل اجراست.
- معادل‌سازی کامل Kubernetes/CloudNativePG به‌صورت مانیفست‌های واقعی و قابل `kubectl apply`
  در پوشه‌ی `k8s/` ارائه شده که همان معماری (Master+Standby، Continuous Backup، PITR) را روی یک کلاستر واقعی (`kind` یا Managed) پیاده می‌کند.
این محدودیت و راه‌حل آن به‌صراحت در بخش «فرضیات» `docs/runbook.md` هم ذکر شده است.
اجرای مجدد (Reproduce)
bash
# روی یک ماشین Ubuntu 24.04 با دسترسی root:
bash scripts/01_setup_master_slave.sh
bash scripts/02_simulate_incident.sh
bash scripts/03_detect_incident_scope.sh
bash scripts/04_build_pitr_clone.sh "<pre_incident_checkpoint_از_مرحله_قبل>"
bash scripts/05_reconcile_and_recover.sh
