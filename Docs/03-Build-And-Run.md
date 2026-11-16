# البناء والتشغيل والاختبار

> **تنبيه صادق:** هذا الكود لم يُجمَّع (Compile) داخل Unreal Engine لأن بيئة العمل لم تكن تحتوي على المحرك. أول بناء على جهازك قد يُظهر أخطاء تجميع بسيطة (اختلاف توقيع دالة بين إصدارات المحرك مثلاً). راجع `05-Testing-Report.md` لمعرفة ما تم اختباره فعلاً وما يحتاج تحققك.

## 1. المتطلبات

| الغرض | المطلوب |
|---|---|
| المحرّر (Windows) | Unreal Engine **4.26.2**، Visual Studio 2019 مع "Game development with C++" و .NET Framework 4.6.2 SDK |
| Android | Android Studio 3.5.3 (أو ما يوصي به 4.26)، ثم تشغيل `Engine/Extras/Android/SetupAndroid.bat` (يثبّت SDK 29 و NDK r21b) |
| iOS | جهاز Mac + Xcode 12.x + حساب Apple Developer + شهادة وملف Provisioning (مشاريع C++ تتطلب Mac أو Remote Build) |
| Dedicated Server | نسخة **مصدرية** من UE 4.26.2 من GitHub (لا يمكن بناء هدف Server بنسخة Launcher) |
| خدمة الغرف | Node.js 18 أو أحدث، خادم Linux/Windows بعنوان IP عام |

## 2. الحصول على أصول المشروع الحقيقية (خطوة إلزامية)

ملف الـ ZIP المرفوع يحتوي فقط على مؤشرات Git LFS. احصل على الأصول من المستودع الأصلي:

```bash
git lfs install
git clone https://github.com/zhenxiao-yu/PUBG-UNREAL.git
cd PUBG-UNREAL
git lfs pull        # ~3.4 GB
```

> إذا ظهر خطأ "bandwidth limit exceeded" فهذا حد GitHub LFS لصاحب المستودع الأصلي؛ استخدم نسختك المحلية الأصلية من المشروع إن كانت لديك.

ثم انسخ طبقة اللعب الجماعي من هذا المستودع فوقها (لا تلمس مجلد `Content`، وتحفظ نسخة احتياطية مما تستبدله):

```bash
# Linux / macOS
./Tools/scripts/apply-to-project.sh /path/to/PUBG-UNREAL
# Windows
powershell -ExecutionPolicy Bypass -File Tools\scripts\apply-to-project.ps1 C:\path\to\PUBG-UNREAL
```

## 3. البناء الأول في المحرّر

1. انقر بزر الفأرة الأيمن على `PUBG_Blueprint.uproject` ← **Generate Visual Studio project files**.
2. افتح `PUBG_Blueprint.sln`، اختر `Development Editor` / `Win64`، ثم **Build**.
3. افتح المشروع. إذا سُئلت "Missing modules – rebuild?" اختر Yes.
4. تحقق من **Project Settings ← Game ← PUBG Multiplayer & Mobile** (كل الإعدادات هناك).

## 4. الاختبار داخل المحرّر

### 4.1 اختبار طبقة الشبكة مباشرة في المعركة (أسرع طريقة)
1. افتح `Level_Test`.
2. **Play ← Advanced Settings**: Number of Players = **2** (أو 3)، Net Mode = **Play As Listen Server**، وأزل علامة **Run Under One Process** لاختبار أقرب للواقع.
3. اضغط Play. يجب أن ترى:
   - العناصر على الأرض تظهر عند الجميع (لا تظهر عند العميل في المشروع الأصلي).
   - الانحناء/الانبطاح/التصويب يظهر على اللاعب الآخر.
   - الالتقاط عند لاعب يُخفي العنصر عند الآخرين، ولا يمكن التقاطه مرتين.
   - الإطلاق يُنقص الصحة عند الهدف، وتظهر علامة الإصابة X عند المطلق، والموت يشغّل رسوم الموت.
   - في أعلى الشاشة: ALIVE / KILLS، وسجل القتل على اليمين.
4. سجل `Output Log` بفلتر `LogPUBG` يوضح ما يحدث (طلقات مرفوضة تظهر بمستوى Verbose: `log LogPUBG Verbose`).

> ملاحظة: PIE لا يمر بالقائمة الرئيسية ولا باللوبي لأنه يبدأ الخريطة مباشرة بـ GameMode الخاص بها.

### 4.2 اختبار القائمة واللوبي (Standalone)
شغّل نسختين من اللعبة على نفس الجهاز أو جهازين في نفس الشبكة:
```bat
"C:\Program Files\Epic Games\UE_4.26\Engine\Binaries\Win64\UE4Editor.exe" "C:\path\PUBG_BP_Project\PUBG_Blueprint.uproject" -game -windowed -resx=1280 -resy=720 -log
```
- النسخة الأولى: MULTIPLAYER ← CREATE ROOM ← CREATE.
- النسخة الثانية: MULTIPLAYER ← LAN ← REFRESH ← JOIN (أو DIRECT IP بعنوان المضيف المعروض في شاشة الغرفة).
- الثانية تضغط READY، المضيف يضغط START MATCH ← عد تنازلي ← المعركة ← بعد فوز أحدكما يعود الجميع للّوبي تلقائياً.

### 4.3 اختبار التحكم اللمسي على الكمبيوتر
- Project Settings ← Input ← فعّل **Use Mouse for Touch**.
- شغّل بالخيار `-ForceTouchUI` (أو ضع `bForceTouchControls=True` تحت `[/Script/PUBG_Blueprint.PUBGSettings]` في `DefaultGame.ini`).
- زر MENU ← EDIT BUTTON LAYOUT لتجربة محرر التخطيط.

### 4.4 اختبارات الأتمتة
Window ← Developer Tools ← **Session Frontend** ← Automation ← ابحث عن `PUBG` ← Start Tests. أو من سطر الأوامر:
```bat
UE4Editor-Cmd.exe "PUBG_Blueprint.uproject" -ExecCmds="Automation RunTests PUBG; Quit" -unattended -nopause -nullrhi -log
```

## 5. Android

1. شغّل `SetupAndroid.bat` مرة واحدة، ثم في Project Settings ← Platforms ← Android اضغط **Configure Now** إذا طُلب.
2. غيّر `PackageName` (حالياً `com.aurum.battle`) إلى معرّفك.
3. File ← **Package Project ← Android ← Android (ASTC)** (للأجهزة الحديثة) أو (ETC2) لتوافق أوسع.
4. ثبّت بالملف `Install_PUBG_Blueprint-arm64.bat` الناتج (يتطلب `adb` وتفعيل USB debugging).
5. للعب على الشبكة المحلية: هاتفان على نفس الـ Wi-Fi. إذا لم تظهر الغرفة في LAN (بعض الأجهزة تحجب البث UDP)، استخدم **DIRECT IP** بالعنوان المعروض عند المضيف.

> **Google Play:** UE 4.26 يدعم رسمياً حتى `TargetSDKVersion=29`. متجر Google Play يطلب حالياً إصداراً أحدث، وهذا يحتاج تعديلات على المحرك/الـ Manifest (`android:exported` وغيرها) أو الترقية إلى UE 4.27/5.x. البناء الحالي مناسب للتثبيت المباشر والاختبار.

## 6. iOS

1. على Mac: افتح المشروع، Project Settings ← Platforms ← iOS: ضع **Bundle Identifier** المطابق لملف الـ Provisioning واستورد الشهادة والملف.
2. File ← Package Project ← iOS.
3. iOS 14+ يطلب إذن الشبكة المحلية (النص موجود في `AdditionalPlistData`). اكتشاف غرف LAN بالبث قد يحتاج صلاحية Apple الخاصة `com.apple.developer.networking.multicast`؛ بدونها استخدم **DIRECT IP** أو الغرف الأونلاين.

## 7. الخادم المخصص (Dedicated Server)

1. ابنِ UE 4.26.2 من المصدر (GitHub: `EpicGames/UnrealEngine`, tag `4.26.2-release`)، واربط المشروع به (Switch Unreal Engine version).
2. في Visual Studio اختر **Development Server** وابنِ، أو استخدم UAT:
   ```bat
   Engine\Build\BatchFiles\RunUAT.bat BuildCookRun -project="C:\path\PUBG_Blueprint.uproject" -noclient -server -serverplatform=Linux -serverconfig=Development -cook -build -stage -pak -archive -archivedirectory="C:\Builds\Server"
   ```
   (لـ Linux تحتاج Cross-Compile Toolchain الخاص بـ 4.26 على Windows.)
3. التشغيل اليدوي:
   ```bash
   ./PUBG_BlueprintServer.sh "/Game/Maps/Level_Test?game=Lobby?RoomName=Public?MaxPlayers=16" -port=7777 -log
   ```
   اللاعبون ينضمون بـ DIRECT IP. الخادم يبدأ المباراة تلقائياً عندما يكون الجميع جاهزين (لاعبان على الأقل).
4. افتح منفذ **UDP 7777** في الجدار الناري.

## 8. خدمة الغرف (غرف الإنترنت)

الهواتف عادةً خلف NAT ولا يمكنها استضافة مباراة عبر الإنترنت. خدمة الغرف تشغّل خادماً مخصصاً لكل غرفة:

```bash
cd Tools/RoomService
PORT=8080 \
PUBLIC_HOST=203.0.113.10 \
SERVER_BINARY=/opt/pubg/LinuxServer/PUBG_BlueprintServer.sh \
SERVER_PORT_MIN=7777 SERVER_PORT_MAX=7796 \
node index.js
```

- افتح **TCP 8080** و **UDP 7777–7796**.
- في `DefaultGame.ini`: `RoomServiceURL=http://203.0.113.10:8080` ثم أعد تحزيم اللعبة.
- في اللعبة: MULTIPLAYER ← ONLINE ← CREATE ONLINE ROOM، والآخرون ينضمون من القائمة أو برمز الانضمام المكوّن من 6 أحرف.
- التفاصيل والـ API في `Tools/RoomService/README.md`.
- للإنتاج: ضع الخدمة خلف HTTPS (Nginx/Caddy) واستخدم `https://` في `RoomServiceURL`.

## 9. تشغيل كل الاختبارات التي لا تحتاج Unreal

```bash
Tools/ci/run_all_tests.sh
```
يشغّل: اختبارات المنطق بـ C++ (g++/clang++)، فاحص قواعد Unreal على الكود، اختبار الطفرات للفاحص، واختبارات خدمة الغرف.

## 10. مشاكل شائعة

| المشكلة | الحل |
|---|---|
| "Could not be compiled. Try rebuilding from source manually" | ابنِ من Visual Studio وراجع أول خطأ في Output؛ أرسل نصه لتصحيحه |
| اللعبة تبدأ مباشرة بالمعركة لا بالقائمة | تأكد من نسخ `Config/DefaultEngine.ini` (السطر `LocalMapOptions=?game=FrontEnd`) وأنك تشغّل `-game` وليس PIE |
| تحذيرات `Blueprint variable 'X' not found` | تمت إعادة تسمية متغير في Blueprint؛ صحّح الاسم في Project Settings ← PUBG Multiplayer & Mobile ← Blueprint Integration |
| العميل يرى العناصر بلا شكل | راجع أن `PickupBaseClass` صحيح، وأن العناصر تولد على الخادم |
| الغرف لا تظهر في LAN | جدار ناري يحجب UDP 14001 (بث جلسات Null) أو 7777 — استخدم Direct IP |
| الهاتف ساخن / بطيء | الإعدادات ← GRAPHICS: LOW و 30 FPS ودقة 70% |
