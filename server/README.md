# Aurum — سيرفر اللعب الجماعي

نفس مشروع Godot يشتغل كسيرفر مخصّص بدون شاشة (headless) عبر **ENet / UDP 7777**.

## شو بيعمل السيرفر
- **غرفة انتظار:** أول لاعب يدخل يبدأ عدّاد 30 ثانية (أو فوراً عند 24 لاعب)، بعدين تبدأ المباراة للكل.
- **نفس الجزيرة ونفس اللوت** عند كل اللاعبين (بذرة مشتركة)، وكل لاعب ينزل بمكان مختلف.
- **حركة سلسة بدون تأخير:** كل لاعب يتحرك على جهازه فوراً ويرسل حالته 15 مرة بالثانية، والباقين يشوفوه بحركة ناعمة (مع الانحناء والانبطاح والتصويب والسلاح).
- **الضرر يقرره السيرفر:** الإصابات تتأكد على السيرفر وتتوزع على الكل (صحة، قتل، سجل القتلى).
- **البوتات على السيرفر:** تكمّل الأماكن الفاضية لـ24 وتقاتل اللاعبين الحقيقيين.
- **المنطقة (الزون)** يتحكم فيها السيرفر وتتزامن عند الكل. الأسلحة المرمية واللوت المأخوذ يختفي عند الكل.
- بعد نهاية المباراة يرجع السيرفر لغرفة الانتظار تلقائياً.

## سيرفر مجاني (بدون فلوس)

### الخيار 1 (الأفضل): Oracle Cloud — مجاني للأبد
يعطيك جهاز ARM فيه **4 أنوية و24GB رام مجاناً للأبد** (أو جهاز AMD صغير 1GB كبديل).
بيطلب **بطاقة بنكية للتحقق فقط** (بيحجز مبلغ صغير مؤقت وبيرجعه، بدون خصم). البطاقات المسبقة الدفع والافتراضية ما بتنقبل.
1. سجّل على https://www.oracle.com/cloud/free/ واختر أقرب منطقة (مثلاً Frankfurt أو Jeddah أو Dubai).
2. **Compute ← Instances ← Create instance**:
   - Image: **Ubuntu 24.04** — Shape: **VM.Standard.A1.Flex** (2 OCPU و12GB كفاية). إذا طلع *Out of capacity* جرّب Availability Domain تاني أو استخدم **VM.Standard.E2.1.Micro**.
   - **Show advanced options ← Management ← Paste cloud-init script**: الصق محتوى `server/oracle-cloud-init.yaml`.
   - Create. الجهاز بيركّب السيرفر وبيشغّله لحاله (5–10 دقايق).
3. افتح المنفذ: **Networking ← Virtual Cloud Networks ← (شبكتك) ← Security Lists ← Default ← Add Ingress Rules**:
   Source CIDR `0.0.0.0/0` — IP Protocol **UDP** — Destination Port **7777**.
4. انسخ **Public IP** تبع الجهاز وحطه بـ Firebase (تحت).

### الخيار 2: بدون بطاقة — على كمبيوترك + playit.gg (مجاني)
1. نزّل وشغّل `server/run-on-pc.bat` (ويندوز) أو `server/run-on-pc.sh` (ماك/لينكس). خلي النافذة مفتوحة وقت اللعب.
2. نزّل برنامج **playit** من https://playit.gg وسجّل حساب مجاني ← **Add Tunnel** ← النوع **UDP** ← Local Port **7777**.
3. بيعطيك عنوان مثل `xxxx.gl.at.ply.gg:12345` — حطه بـ Firebase (host = الجزء قبل `:` و port = الرقم بعده).
السيرفر بيشتغل طول ما الكمبيوتر شغّال.

### أي سيرفر لينكس تاني (أمر واحد)
```bash
curl -fsSL https://raw.githubusercontent.com/mujahidsa-w/Aurum/claude/awesome-planck-jiaods/server/install.sh | sudo bash
```
بيركّب Godot (x86 أو ARM) واللعبة وخدمة بتشتغل مع الإقلاع وبترجع لحالها إذا وقفت، بيفتح الجدار الناري، بيضيف swap للأجهزة الصغيرة، وبيطبعلك الـIP. لتحديث السيرفر: شغّل نفس الأمر مرة تانية.

## التشغيل على سيرفر (VPS) بـ Docker
أي VPS لينكس فيه Docker (مثلاً Hetzner CX22 أو DigitalOcean 2GB أو أكثر):
```bash
git clone -b claude/awesome-planck-jiaods https://github.com/mujahidsa-w/Aurum.git
cd Aurum
docker compose -f server/docker-compose.yml up -d --build
docker logs -f aurum-server        # لازم يطلع: AURUM SERVER: listening on UDP 7777
```
افتح منفذ **UDP 7777** بجدار الحماية (مثلاً `ufw allow 7777/udp`).

## ربط اللعبة بالسيرفر (بدون إعادة بناء التطبيق)
بـ Firebase Realtime Database أضف:
```json
"config": { "server": { "host": "IP_السيرفر", "port": 7777 } }
```
اللعبة بتقرأه تلقائياً بعد تسجيل الدخول. أو للتجربة: اللوبي ← SETTINGS ← Server ← اكتب `IP:7777` ← SAVE.
بدون عنوان سيرفر (أو إذا السيرفر ما رد) اللعبة بتلعب ضد البوتات مثل قبل.

## تشغيل محلي للتجربة
```bash
godot --headless --path AurumGodot res://scenes/server.tscn -- --server --port=7777 --lobby-seconds=10
```
ثم من جهازين على نفس الشبكة: Server = `IP_الكمبيوتر:7777` ← START.

## ملاحظات
- البروتوكول له رقم إصدار (`scripts/net/net_config.gd` → `PROTOCOL`)؛ نسخة قديمة من اللعبة بتنرفض برسالة "حدّث اللعبة".
- الإصابات يبلّغ عنها جهاز الرامي ويتحقق منها السيرفر (حي، ضمن الحدود). منع الغش الكامل يحتاج محاكاة الرصاص على السيرفر — خطوة لاحقة.
- سيرفر واحد = مباراة وحدة بنفس الوقت (24 لاعب). لأكثر: شغّل أكثر من حاوية على منافذ مختلفة.
