# تقرير تحليل مشروع PUBG-UNREAL (قبل التعديل)

> هذا التقرير مبني على فحص فعلي لملفات المشروع، وليس على وصف الـ README فقط.
> تم تحليل ملفات الـ Blueprint الثنائية (`.uasset`) بأداة قراءة كتبتها لصيغة حزم UE 4.26
> (جدول الأسماء + جدول الاستيراد/التصدير + القيم الافتراضية CDO) دون الحاجة إلى المحرّر.
> الأدوات موجودة في `Tools/uasset-inspector/`.

## 1. ملاحظات حرجة يجب معرفتها أولاً

| # | الملاحظة | الأثر |
|---|---|---|
| 1 | **ملف ZIP المرفوع لا يحتوي على أصول المشروع الحقيقية.** جميع ملفات `.uasset` و`.umap` (1580 ملفاً) هي مؤشرات Git LFS بحجم ~130 بايت، والمحتوى الحقيقي (~3.4 GB) غير موجود في الـ ZIP. | لا يمكن فتح المشروع في Unreal من هذا الـ ZIP. يجب الحصول على الأصول عبر `git lfs` من المستودع الأصلي (التفاصيل في `03-Build-And-Run.md`). |
| 2 | الـ ZIP مطابق بايت ببايت لآخر commit في المستودع الأصلي `zhenxiao-yu/PUBG-UNREAL` (تم التحقق بـ `diff`). | لا توجد تعديلات محلية مفقودة. |
| 3 | تم تنزيل ملفات مجلد `Blueprints/` فقط (132 ملفاً، 21 MB) من خادم LFS العام والتحقق من كل ملف بـ SHA-256 مقابل المؤشر. | سمح ذلك بتحليل المنطق الفعلي. الخرائط (Level_Battle = 897 MB) والأصول الفنية لم تُنزّل. |
| 4 | **المشروع Blueprint فقط**: لا يوجد مجلد `Source/` ولا وحدات C++ في `.uproject` (رغم أن الـ README يذكر C++). | يجب تحويله إلى مشروع C++ لإضافة طبقة الشبكة (تمت). |
| 5 | **بيئة العمل هنا (حاوية Linux سحابية) لا تحتوي على Unreal Engine 4.26.2**، ولا يمكن تثبيته (المصدر يتطلب حساب Epic مرتبطاً بـ GitHub). | **لم يتم تجميع (Compile) أي كود C++ داخل UE، ولم تُفتح أي Blueprint في المحرّر.** كل ما يخص ذلك موثّق بوضوح في تقرير الاختبار. |

## 2. بنية المشروع

```
PUBG_BP_Project/
├── PUBG_Blueprint.uproject        (EngineAssociation 4.26، بدون Modules)
├── Config/                        (DefaultEngine/Game/Input/Editor .ini)
└── Content/
    ├── Blueprints/   132 أصل  ← كل منطق اللعبة
    ├── Maps/         Level_Test (13 MB)، Level_Battle (897 MB)
    └── Assets/       1439 أصلاً (Humans, Weapons, Maps, Animations, Audio, Particles, UI ...)
```

الإعدادات الحالية (`DefaultEngine.ini`):
- الخريطة الافتراضية: `/Game/Maps/Level_Test`
- GameMode: `MyGameMode` — GameInstance: `MyGameInstance`
- العتاد المستهدف: `Desktop / Maximum` (غير مهيأ للهاتف)
- قناة تصادم مخصصة: `Ground` (`ECC_GameTraceChannel1`)

## 3. الأنظمة الموجودة (من داخل ملفات الـ Blueprint)

### 3.1 الإطار العام (Gameplay Framework)

| Blueprint | الأب (Parent) | الدور الفعلي |
|---|---|---|
| `MyGameMode` | `GameModeBase` | توليد العناصر عشوائياً (`GenerateItems`, `RandomItemType/ID/Number/Location`) ومسار الطائرة (`RandomRoute`). الأصناف الافتراضية: MyGameState / MyPlayerController / MyPlayerState / MyHUD / MyCharacter |
| `MyGameState` | `GameStateBase` | فارغ تقريباً |
| `MyGameInstance` | `GameInstance` | ثوابت: أسماء المقابس (`Socket_Gun_Stand`, `Socket_Gun_Aim`, `Socket_Helmet`...)، `DefaultCapacity=50`، زمن التلقيم، و`GenerateSN` |
| `MyPlayerController` | `PlayerController` | **أكبر ملف (4.8 MB) ويحتوي على معظم منطق اللعب**: كل أحداث الإدخال، الحركة، الالتقاط، التجهيز، الرمي، إعادة التلقيم، الطائرة والمظلة، الكاميرا |
| `MyPlayerState` | `PlayerState` | **بيانات المخزون والصحة**: `Weapon1`, `Weapon2`, `HoldGun`, `Ammo556`, `Ammo762`, `Equipments[]`, `Fashions[]`, `ItemsInBackpack[]`, `HealthPoint`, `EnergyPoint`, `KilledAmount` + Event Dispatchers للتغييرات |
| `MyCharacter` | `Character` | المظهر والكاميرا (SpringArm + Camera + FPSCamera + FPSArm)، 7 مكونات SkeletalMesh للملابس، والمونتاج. متغيرات الحالة: `isCrouching`, `isProne`, `isAiming`, `isSightAiming`, `isHoldWeapon`, `isFiring`, `isReload`, `isDead`, `isOnTheAir`, `isFreeFalling`, `isUmbrellaOpened`, `ForwardValue` ... |
| `MyAnimeBlueprint` | AnimBlueprint | يقرأ متغيرات `MyCharacter` (crouch/prone/aim/holdWeapon/freefall/dead) لتحديد الوضعية |
| `MyHUD` | `HUD` | إنشاء واجهات `ActionTips`, `MessageTips`, `UseItem`, `Parachute` |

### 3.2 نظام العناصر (Items)

```
ItemBase (Actor)  ← ItemType(E_ItemType), ID(Name), SN(String), Name(Text), Amount(Int)
├── PickupBase   ← العنصر الملقى على الأرض (Box overlap + Outline + StaticMesh)
│   ├── PickupWeapon / PickupAmmo / PickupHealth / PickupBoost
│   ├── PickupEquipment / PickupWeaponAcc / PickupFashion
├── ItemWeapon   ← السلاح في يد اللاعب: Ammo, ClipSize, ShootMode, FireInterval, ملحقات، إطلاق، ارتداد
├── ItemAmmo / ItemEquipment / ItemFashion / ItemWeaponAcc
└── ItemUseBase  ← ItemHealth / ItemBoost (UseTime, Value, Limit)
```

`E_ItemType` = Weapon, Accessories, Ammo, Health, Boost, Helmet, Vest, Backpack, Fashion
`E_ShootMode` = Single, Auto — `E_WeaponPosition` = Left, Right

جداول البيانات (DataTables): `DT_Item_Weapon` (Damage, FiringInterval, ClipSize, UseAmmoID, AutoMode, FireSound, SkeletalMesh ...)، `DT_Item_Health` (UseTime, Value, Limit)، `DT_Item_Boost` (BoostValue)، `DT_Item_Equipment` (Type, Capacity)، `DT_Item_Ammo`، `DT_WalkSpeed`، `DT_CameraHeight`، `DT_ProneTime`، وجداول احتمالات التوليد.

### 3.3 الأسلحة والرصاص
- `ItemWeapon.PressFire/ReleaseFire` يطلق `BulletProjectile` (Actor مع ProjectileMovement).
- **`BulletProjectile` لا يطبّق أي ضرر**؛ عند الاصطدام ينشئ فقط `BulletHoleDecal`.
- **لا يوجد أي استدعاء لـ `ApplyDamage` في المشروع كله** ← لا يوجد نظام ضرر أو موت فعلي حالياً رغم وجود `HealthPoint` و`isDead`.
- الأسلحة المتوفرة كأصول: M416, AK47, AWM مع أصوات إطلاق.

### 3.4 الحركة والوضعيات
- الحركة تتم في `MyPlayerController.ExecuteMove` بواسطة **`K2_SetActorLocation` / `K2_SetActorRotation`** وليس `AddMovementInput`.
- الانحناء والانبطاح متغيرات Blueprint (`isCrouching`, `isProne`) + تعديل ارتفاع الكاميرا والسرعة، ولا تستخدم `Character::Crouch`.
- السرعة من `DT_WalkSpeed` و`WalkSpeed=600`.

### 3.5 الإدخال الحالي (DefaultInput.ini)

| Action/Axis | المفتاح | Action/Axis | المفتاح |
|---|---|---|---|
| MoveForward / MoveRight | W S / A D | Fire | LMB |
| Turn / LookUp | Mouse | Aiming (Action + Axis) | RMB |
| Jump | Space | Reload | R |
| Crouch | C | ShootMode | B |
| Prone | Z | KeyBoard1 / KeyBoard2 | 1 / 2 |
| LeftShift (ركض) | L-Shift | DiscardWeapon | G |
| Walk | L-Ctrl | TakeBackGun | X |
| Alt (نظرة حرة) | L-Alt | Interaction | F |
| ShowInventory | Tab | ToggleMapUI | M (لا يوجد له تنفيذ) |

كل أحداث الإدخال موجودة داخل `MyPlayerController` (InputAction / InputAxis events).

### 3.6 الواجهات
`MainUI`, `UserInfoUI` (الصحة)، `CrosshairsUI`, `DirectionUI` (البوصلة)، `ActionTipsUI`, `MessageTipsUI`, `UseItemUI`, `CountDownUI`, وواجهة المخزون الكاملة `InventoryUI` مع السحب والإفلات (`I_BackpackList`, `I_VicinityList`, `I_WeaponItem`, `I_EquipmentItem` ...) ومعاينة ثلاثية الأبعاد للشخصية (`CaptureActor`).

### 3.7 الطائرة والمظلة
`Airplane` (Timeline للطيران + Dispatchers `OnJumpReady/OnJumpLatest`)، `Parachute`, `ParachutePack`، ومنطق القفز والسقوط الحر وفتح المظلة في `MyPlayerController`.

## 4. تقييم الجاهزية للعب الجماعي

**لا يوجد أي كود شبكة في المشروع**: لا توجد دوال Run-on-Server ولا Multicast ولا متغيرات Replicated ولا `HasAuthority`، والعناصر الملقاة ليست `bReplicates`.

| النظام | ماذا يحدث لو شُغّل أونلاين كما هو | السبب |
|---|---|---|
| الحركة | ارتداد/رجوع اللاعب لمكانه (rubber-banding) عند العملاء | `SetActorLocation` على العميل لا يمر عبر `CharacterMovementComponent` فيصحّحه الخادم |
| الوضعيات والتصويب | اللاعبون الآخرون يظهرون واقفين دائماً | `isCrouching/isProne/isAiming` متغيرات محلية غير منسوخة |
| السرعة (ركض/مشي) | ارتداد | `MaxWalkSpeed` يتغير على العميل فقط |
| العناصر على الأرض | لا تظهر عند العملاء | تُولَّد في GameMode (الخادم فقط) وليست Replicated |
| الالتقاط والمخزون | تكرار العناصر، كل جهاز يرى مخزوناً مختلفاً | المنطق يعمل محلياً بالكامل |
| الإطلاق | لا ضرر، والآخرون لا يرون الطلقات | لا يوجد نظام ضرر، والطلقة Actor محلي |
| الصحة والموت | غير موجود فعلياً | لا يوجد ApplyDamage |
| الطائرة/المظلة | تعمل للمضيف فقط | تعتمد على `GetPlayerController(0)` وطائرة غير منسوخة |

**نمط "اللاعب رقم 0"**: الدوال `GetPlayerController(0)` و`GetPlayerCharacter(0)` مستخدمة في `ItemBase`, `ItemWeapon`, `ItemUseBase`, `MyCharacter`, `MyGameMode`, `CaptureActor` وكل واجهات المخزون. هذا صحيح على جهاز اللاعب نفسه، لكنه **خاطئ إذا نُفّذ نفس المنطق على الخادم نيابة عن لاعب آخر**. لذلك لا يمكن ببساطة تشغيل منطق الـ Blueprint الحالي على الخادم.

## 5. الاستراتيجية المختارة (بناءً على التحليل)

1. **الحفاظ على كل الـ Blueprints كما هي** — لم يُعدَّل أي ملف `.uasset`. المنطق الحالي يستمر في العمل على جهاز كل لاعب لِلاعبه المحلي (حيث نمط "اللاعب 0" صحيح): الواجهات، المخزون، الكاميرا، الارتداد.
2. **إضافة وحدة C++ (`PUBG_Blueprint`)** تحتوي طبقة شبكة تُركَّب تلقائياً وقت التشغيل على الـ Blueprints الموجودة (بدون Reparent)، وتعمل **فقط في الألعاب الشبكية**؛ وضع اللاعب الفردي يبقى مطابقاً للأصل 100%.
3. **الخادم هو المرجع (Server Authority)** للأشياء التي تحدد نتيجة المباراة: الصحة والضرر والموت، صحة الإصابات، معدل الإطلاق والذخيرة، وجود العناصر وملكيتها (لا يمكن التقاط نفس العنصر مرتين)، الفوز، والتحقق من سرعة الحركة.
4. **جسر Reflection** يقرأ/يكتب متغيرات الـ Blueprint بالاسم الحقيقي المستخرج أعلاه (مثل `isProne`, `HealthPoint`, `HoldGun`) للمزامنة دون تعديل الـ Blueprint.
5. **التحكم اللمسي يحقن الإدخال في نفس Action Mappings الحالية** (`Fire`, `Jump`, `Crouch`...) عبر مفاتيح افتراضية جديدة، فتعمل كل الأزرار عبر منطق الـ Blueprint الأصلي نفسه.

التفاصيل الكاملة في `02-Architecture.md`، وما يحتاج المحرّر في `04-Editor-Integration.md`.
