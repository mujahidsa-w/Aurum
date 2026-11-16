# التكامل مع المحرّر: ما يعمل تلقائياً وما يحتاج تعديلاً يدوياً

## 1. ما يعمل بدون أي تعديل على الـ Blueprints

بعد نسخ الملفات والبناء، لا يلزم فتح أي Blueprint. كل ما يلي يعمل لأن طبقة C++ تُركَّب وقت التشغيل:

- القائمة الرئيسية، الغرف (LAN / IP / Online)، اللوبي، شاشة الشخصية، الإعدادات.
- التحكم اللمسي الكامل لكل أوامر المشروع الأصلية + محرر التخطيط.
- في المباراة الشبكية: ظهور العناصر عند الجميع، الالتقاط بدون تكرار، الإسقاط الحقيقي، الوضعيات والتصويب والسقوط الحر للآخرين، الإطلاق بأصوات ومونتاج الآخرين، الضرر والصحة والموت على الخادم، الخوذة/السترة تخفّض الضرر، الشفاء من المستهلكات، الفوز والترتيب والعودة للّوبي.

## 2. حدود معروفة سببها تصميم الـ Blueprints الأصلية

هذه ليست أخطاء في الطبقة الجديدة بل نتيجة أن المنطق الأصلي محلي بالكامل ويعتمد على `GetPlayerController(0)`. حلها الكامل يتطلب تعديلاً داخل المحرّر (الأقسام التالية):

| الحد | التفاصيل |
|---|---|
| الطائرة والمظلة | `MyGameMode.RandomRoute` يُنشئ `Airplane` على الخادم فقط وغير منسوخة، و`MyPlayerController` يربط أحداثها عبر اللاعب 0. في اللعب الجماعي تعمل للمضيف فقط؛ العملاء يبدؤون على الأرض |
| الحركة | `MyPlayerController.ExecuteMove` يستخدم `SetActorLocation`، لذا الخادم يقبل موقع العميل مع فحص السرعة (لا محاكاة كاملة على الخادم) |
| مظهر الآخرين | `MyCharacter.BeginPlay` قد يطبّق ملابس اللاعب المحلي على كل الشخصيات (اللاعب 0)؛ الطبقة الجديدة تعيد تطبيق الملابس الصحيحة بعد نصف ثانية |
| سباق الالتقاط | إذا التقط لاعبان نفس العنصر في نفس اللحظة، الخادم يعطيه للأسبق ويزيل النسخة غير الموثقة من حقيبة الآخر مع رسالة. الأسلحة المرفوضة تبقى ظاهرة محلياً لكنها لا تُحدث ضرراً |
| الرصاص | الضرر يُحسب كطلقة فورية من مركز الشاشة مع تشتت بسيط (لا سقوط ولا زمن طيران). المقذوف الأصلي `BulletProjectile` يبقى تأثيراً بصرياً محلياً |
| المضيف | في Listen Server المضيف موثوق (منطقه يعمل على الخادم). استخدم Dedicated Server للمباريات التنافسية |

## 3. تعديلات Blueprint اختيارية (موصى بها للحصول على سلطة كاملة)

كل خطوة مستقلة. بعد كل خطوة شغّل اختبار PIE بلاعبين.

### 3.1 الحركة عبر CharacterMovement (يزيل الحاجة لقبول موقع العميل)
1. افتح `MyPlayerController` ← الدالة `ExecuteMove` (ومعها `MovingOnTheGround`).
2. استبدل عقدة `SetActorLocation` المستخدمة للمشي بـ `Add Movement Input` على `MyCharacterRef` (Direction = اتجاه الحركة، Scale = `MoveForwardAxis`/`MoveRightAxis`).
3. استبدل `SetActorRotation` بـ `Set Control Rotation` أو فعّل `Use Controller Rotation Yaw`.
4. في `DefaultGame.ini` تحت `[/Script/PUBG_Blueprint.PUBGSettings]` ضع `bClientAuthoritativeMovement=False`.

### 3.2 الطائرة والمظلة للجميع
1. `Airplane`: Class Defaults ← **Replicates** ✓ و **Replicate Movement** ✓.
2. في `MyGameMode` بعد إنشاء الطائرة: مرّ على كل PlayerController (Get All Actors of Class) بدل `GetPlayerController(0)` واستدعِ الحدث الذي يربط `OnFlying/OnJumpReady/OnJumpLatest`.
3. حوّل `Eject` و`OpenTheParachute` إلى Custom Events بخاصية **Run on Server**، وادعها من الإدخال المحلي.

### 3.3 إزالة نمط "اللاعب 0"
ابحث في هذه الـ Blueprints عن `Get Player Controller (Index 0)` و`Get Player Character (Index 0)` واستبدلها بالمالك الفعلي:
`ItemBase`, `ItemWeapon`, `ItemUseBase`, `MyCharacter`, `CaptureActor` ← استخدم `Get Owner` / `Get Instigator` / المتغير `CharcterRef` بعد تعيينه عند الإنشاء.
واجهات المخزون (`I_*`, `InventoryUI`) تعمل محلياً فقط، فاستخدام الـ index 0 فيها مقبول.

### 3.4 جعل المخزون Replicated بالكامل (بديل لسجل C++)
إذا أردت أن يكون مخزون الـ Blueprint نفسه هو المرجع:
1. `MyPlayerState`: علّم `Weapon1`, `Weapon2`, `HoldGun`, `Ammo556`, `Ammo762`, `Equipments`, `Fashions`, `ItemsInBackpack`, `HealthPoint`, `EnergyPoint` بـ **Replicated** (أو RepNotify لتحديث الواجهة).
2. `ItemBase` وأبناؤه: **Replicates** ✓.
3. حوّل `PickupItem`, `DiscardItem`, `EquipWeapon`, `ConsumeItem`, `TakeBackWeapon` في `MyPlayerController` إلى أحداث **Run on Server** واستدعها من الإدخال.
4. احذف الاستدعاءات المحلية لـ `SetHealthPoint` (الخادم هو المرجع).
عندها يمكن تعطيل `UPUBGPlayerNetComponent` من `UPUBGNetBootstrapSubsystem::SetupActor`.

## 4. أين تغيّر أسماء أو مسارات بدون إعادة تجميع
كل أسماء متغيرات/دوال الـ Blueprint ومسارات الأصناف والجداول موجودة في:
**Project Settings ← Game ← PUBG Multiplayer & Mobile** (تُحفظ في `DefaultGame.ini`).
إذا أعدت تسمية متغير في Blueprint، صحّح اسمه هناك؛ وإلا سيظهر تحذير واحد في السجل (`Blueprint variable 'X' not found`) وتتعطل تلك الميزة فقط.

## 5. إنشاء خرائط مخصصة للقائمة واللوبي (اختياري)
الآن تُستخدم `Level_Test` كخلفية للقائمة واللوبي. لتسريع التحميل على الهاتف:
1. File ← New Level ← Empty Level (أضف ضوءاً وسماءً بسيطة) ← احفظها `/Game/Maps/MainMenu` و`/Game/Maps/Lobby`.
2. في `DefaultGame.ini`:
   ```ini
   [/Script/PUBG_Blueprint.PUBGSettings]
   MenuMap=/Game/Maps/MainMenu
   LobbyMap=/Game/Maps/Lobby
   ```
3. في `DefaultEngine.ini` غيّر `GameDefaultMap` إلى `/Game/Maps/MainMenu.MainMenu` وأضف الخريطتين إلى `MapsToCook`.
