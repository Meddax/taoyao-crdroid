# crDroid 16.0 для Xiaomi 12 Lite (taoyao): набор для сборки на арендованном сервере

Здесь всё, чтобы взять чистый сервер с Ubuntu 24.04, запустить несколько команд и получить zip
прошивки с вашим ядром (KernelSU-Next) из репозитория `Mi-12-lite-kernel`.

**Что проверено, а что нет.** Здесь, на вашем ПК, проверены: синтаксис скриптов; что все имена пакетов
находятся в Ubuntu 24.04; что манифест `taoyao.xml` склеивается с манифестом crDroid 16.0 настоящим
инструментом `repo` (1187 проектов, без конфликтов путей); что все 7 репозиториев и ветки существуют,
а их коммиты те же, что смотрело исследование; стадия `kernel` на вашем настоящем bundle-файле;
стадия `firmware` на подставных образах; стадия `preflight` на заглушках. **Сама сборка не
запускалась ни разу**: это порт без прецедента (никто не публиковал crDroid 16.0 на этих деревьях), и
ошибки компиляции вероятны. Скрипты устроены так, чтобы каждую стадию можно было повторить, а лог
нужной ошибки легко достать.

Известно, что сообщество уже собирало crDroid для taoyao: у вас в загрузках есть
`crDroidAndroid-16.0-20251005-taoyao-v12.1.zip` (неофициальная сборка октября 2025, Android 16
QPR0, прошивочные разделы те же 17). Какие деревья в ней использованы, неизвестно.

## 1. Какой сервер взять

| Что | Минимум | Лучше |
|---|---|---|
| Процессор | 16 vCPU | 32 vCPU |
| Память | 64 ГБ | 128 ГБ |
| Диск | 400 ГБ SSD/NVMe | 500–600 ГБ |
| Система | Ubuntu 24.04 | то же |

Подойдёт любой почасовой облачный сервер. Цены ниже из исследования (оценки, часть сайтов с вашей
сети не открылась), в сутки столько не нужно: рассчитывайте часов на 5–8 на первый прогон.

| Сервер | Параметры | Цена в час (ориентир) |
|---|---|---|
| Hetzner Cloud CCX53 | 32 vCPU, 128 ГБ, 600 ГБ | около 0,86 € |
| Hetzner Cloud CCX43 | 16 vCPU, 64 ГБ, 360 ГБ | около 0,44 € (диск впритык) |
| OVH b3-128 | 32 vCPU, 128 ГБ | около 0,81 $ |
| AWS c7a.8xlarge | 32 vCPU, 64 ГБ (диск докупается) | 1,64 $ (spot около 0,69 $) |
| GCP n2d-standard-32 | 32 vCPU, 128 ГБ (диск докупается) | 1,35 $ (spot около 0,65 $) |

Время (оценка, не замер): `repo sync` 1–3 часа, сама сборка около 2,5–3 часов на 32 vCPU; итого
порядка 4–6 часов и 3–7 € на первый прогон, если всё пройдёт без остановок. **Удалите сервер сразу,
когда скачали результат**: оплата идёт, пока он существует.

## 2. Что отправить на сервер

С вашего ПК (подставьте адрес; в Windows 10 `scp` есть в системе):

```bash
scp D:\MeruDevTools\ROM_BUILD\kernel\out\Mi-12-lite-kernel-all-branches.bundle root@СЕРВЕР:/root/
scp -r D:\MeruDevTools\ROM_BUILD\crdroid root@СЕРВЕР:/root/crdroid-kit
```

Bundle (213 МБ) это ваш репозиторий ядра с тремя ветками: `taoyao-5.4.302` (ядро прошивки +
KernelSU-Next), `taoyao-5.4.302-hardened` (то же + 10 небольших исправлений) и `taoyao-5.4.302-suki`
(10 исправлений + SukiSU-Ultra вместо KernelSU-Next). GitHub для этого не нужен.

## 3. На сервере

```bash
sudo bash /root/crdroid-kit/server_setup.sh                 # пакеты, repo, git-lfs, пользователь build
cp /root/Mi-12-lite-kernel-all-branches.bundle /home/build/
cp -r /root/crdroid-kit /home/build/crdroid-kit && chmod +x /home/build/crdroid-kit/*.sh && chown -R build:build /home/build
sudo -iu build
tmux new -s crd                                              # сборка идёт часами: только внутри tmux
cd ~/crdroid-kit
KERNEL_BUNDLE=$HOME/Mi-12-lite-kernel-all-branches.bundle ./build_crdroid.sh all
```

Отсоединиться от tmux: `Ctrl+b`, затем `d`; вернуться: `tmux attach -t crd`. Если соединение
оборвётся, сборка продолжится.

### Если сервер без root (например, ServerHive)

[ServerHive](https://github.com/ServerHive-Development) выдаёт общий bare-metal сервер по SSH без
root, с уже поставленными инструментами для сборки Android и с Byobu вместо голого tmux. Тогда
`server_setup.sh` не нужен (ему нужен root), а скрипт сборки root не использует:

```bash
# на вашем ПК
scp D:\MeruDevTools\ROM_BUILD\kernel\out\Mi-12-lite-kernel-all-branches.bundle ИМЯ@server.serverhive.com:~/
scp -r D:\MeruDevTools\ROM_BUILD\crdroid ИМЯ@server.serverhive.com:~/crdroid-kit
# на сервере (вход: ssh ИМЯ@server.serverhive.com; Byobu откроется сам)
cd ~/crdroid-kit && chmod +x *.sh
git config --global user.name "meru-build" && git config --global user.email "build@localhost"   # если ещё не задано
./build_crdroid.sh check            # покажет, чего не хватает; недостающее пакетом просит поставить администратор
KERNEL_BUNDLE=$HOME/Mi-12-lite-kernel-all-branches.bundle ./build_crdroid.sh all
```

- Отсоединиться от Byobu: `F6` (или `Ctrl+a`, затем `d`), вернуться: команда `byobu`. Сборка при этом идёт.
- Не запускайте две ROM в одном окне Byobu.
- Если в `sync.log` появится `429`, Google ограничивает анонимную синхронизацию: сгенерируйте
  git cookies на android.googlesource.com (кнопка «Generate Password», выполнить показанный скрипт) и
  уменьшите `SYNC_JOBS`.
- **По окончании тарифа данные удаляются.** Сразу после стадии `collect` заберите
  `~/crdroid/artifacts` (`scp -r ИМЯ@server.serverhive.com:crdroid/artifacts .`). Уложитесь в срок:
  продление на 2 часа бесплатно, один раз.
- Диск и память общего сервера мне неизвестны. Стадия `check` показывает их, а `smoke` покажет, хватает
  ли памяти для анализа Soong, раньше, чем начнётся многочасовая сборка.

### Стадии

`./build_crdroid.sh <стадия>`; можно запускать по одной и повторять.

| Стадия | Что делает | Время |
|---|---|---|
| `init` | `repo init` для crDroid 16.0 + ваш `taoyao.xml` | минуты |
| `sync` | `repo sync` (повторяет при сбоях) | 1–3 ч |
| `kernel` | ядро из bundle в `kernel/xiaomi/taoyao`; при `KSU=1` (по умолчанию) `taoyao_defconfig` заменяется на `taoyao_ksu_defconfig` | секунды |
| `firmware` | проверяет, что 17 образов прошивки настоящие, а не указатели Git LFS | секунды |
| `preflight` | деревья на месте, нет устаревших переменных сборки, что в BoardConfig | секунды |
| `smoke` | `breakfast taoyao` + `m nothing`: проверяет манифест, дерево устройства и самый прожорливый по памяти шаг | 15–40 мин |
| `build` | `m bacon`: сама прошивка | 2,5–3 ч |
| `collect` | кладёт результат в `~/crdroid/artifacts` | секунды |

Настройки задаются переменными перед командой:

- `KERNEL_BRANCH=taoyao-5.4.302-hardened` берёт ядро с исправлениями (по умолчанию минимальное);
- `KERNEL_BRANCH=taoyao-5.4.302-suki` берёт ядро с SukiSU-Ultra вместо KernelSU-Next (десять исправлений те же);
- `KSU=0` собирает ядро прошивки без KernelSU;
- `VARIANT=user` вместо `userdebug`;
- `FIRMWARE_DIR=/путь` папка с 17 образами, если Git LFS не отдаст их;
- `DEPTH=` (пусто) отключает мелкие клоны: полная история, около +100 ГБ.

## 4. Результат

В `~/crdroid/artifacts/`: zip прошивки `crDroidAndroid-16.0-*-taoyao-*.zip`, `boot.img`,
`vendor_boot.img`, `dtbo.img`, `manifest-pinned.xml` (точные коммиты всех проектов), `kernel.txt`,
`SHA256SUMS`. Забрать: `scp -r build@СЕРВЕР:crdroid/artifacts .`

## 5. Установка на телефон

Тем же порядком, что вы ставите прошивку сейчас (`C:\platform-tools\111.cmd`: `fastboot -w`,
прошивка `vendor_boot`, `boot`, `dtbo`, перезагрузка в recovery, `adb sideload`), но с файлами из
`artifacts`. **`fastboot -w` стирает данные.** Откат это zip текущей прошивки; держите его под рукой.

## 6. Места, где вероятнее всего что-то упадёт

1. **Прошивочные разделы.** Их 17 (`xbl`, `abl`, `tz`, `hyp`, `modem` и другие), и они входят в OTA.
   Образы должны совпадать с теми, что уже на телефоне (OS1.0.39.0.ULIEUXM). Стадия `firmware`
   сохраняет их хеши в `~/crdroid/logs/firmware-sha256.txt`. Не ставьте OTA с другими прошивочными
   образами: про неофициальную сборку /e/OS для taoyao пересказывали, что после неё телефоны уходили
   в EDL (причина не установлена).
2. **Квота Git LFS.** Образы прошивки (около 296 МБ) и камера (MiuiCamera.apk, 131 МБ) лежат в Git
   LFS у `skglab-dev`, квота общая (около 430 МБ на пару). Если `repo sync` упрётся в неё:
   `GIT_LFS_SKIP_SMUDGE=1 ./build_crdroid.sh sync`, а образы прошивки взять из пакета HyperOS 1.0.39.0
   EEA (5,4 ГБ) на своём ПК:
   ```bash
   python D:\MeruDevTools\ROM_BUILD\kernel\tools\payload_extract.py <miui_TAOYAOEEAGlobal_OS1.0.39.0.ULIEUXM...zip> extract fw abl aop bluetooth cpucp devcfg dsp featenabler hyp imagefv keymaster modem qupfw shrm tz uefisecapp xbl xbl_config
   ```
   затем `scp -r fw root@СЕРВЕР:` и `FIRMWARE_DIR=$HOME/fw ./build_crdroid.sh firmware`. Для камеры
   такого запасного пути нет.
3. **Пара `hardware/xiaomi` + `hardware/dolby`.** Из веток Evolution X: единственный вариант,
   подтверждённый выпущенной ROM. `device.mk` включает модуль `DSPVolumeSynchronizer`, который
   объявлен и там, и там, так что возможен дубликат правил. Запасные варианты: ветки crDroid
   `16.0` и `Dolby-Vision-2.0` (`crdroidandroid/android_hardware_xiaomi`, `android_hardware_dolby`).
4. **Устаревшие переменные.** Android 16 запретил шесть переменных; `preflight` их ищет и покажет.
5. **Приложение Updater** будет стучаться на `taoyao.json`, которого нет (404): безвредно.
6. **Ядро.** Собирается платформенным clang r563880c, тем же, что и у прошивки. Если в `smoke` или
   `build` упадёт именно ядро, соберите его отдельно по `ROM_BUILD/kernel/build/build_kernel.sh`:
   это те же исходники.

## 7. Что прислать мне, если что-то упало

Последние 150 строк лога (`tail -150 ~/crdroid/logs/build-*.log`), файл `~/crdroid/out/error.log`
и название стадии. Я разберу и поправлю набор.

## Состав

| Файл | Зачем |
|---|---|
| `taoyao.xml` | local manifest: 7 деревьев сообщества, закреплённых на проверенных коммитах |
| `server_setup.sh` | пакеты, `repo`, git-lfs, swap при нехватке памяти, пользователь `build` |
| `build_crdroid.sh` | стадии `init … collect` |
| `device_taoyao_crdroid.mk` | готовый `lineage_taoyao.mk` для дерева устройства (Q1 плана) |
| `crdroid_taoyao.mk` | готовый `crdroid/crdroid.mk` — наложение crDroid (blur, face unlock, overlay) |
| `taoyao_crdroid_defconfig.fragment` | справочник обязательных флагов ядра + чеклист |
| `system.prop.crdroid` | системные свойства, специфичные для crDroid |

## 8. Как применить файлы порта crDroid к дереву устройства

После стадии `sync` дерево устройства находится по адресу `$WORK/device/xiaomi/taoyao`.
Файлы из этого каталога (`ROM_BUILD/crdroid/`) описывают изменения, которые нужно внести вручную
**один раз**; повторная синхронизация их не затрёт, так как они лежат вне managed repo-проектов
(кроме `lineage_taoyao.mk`, который перезапишется при `repo sync --force-sync` — на этот случай
держите патч в git).

### Шаг 1 — `lineage_taoyao.mk`

```bash
cp ~/crdroid-kit/device_taoyao_crdroid.mk \
   $WORK/device/xiaomi/taoyao/lineage_taoyao.mk
```

Содержимое файла аналогично EvolutionX-версии, но добавляет:
- `inherit-product-if-exists device/xiaomi/taoyao/crdroid/crdroid.mk`
- `PRODUCT_GMS_CLIENTID_BASE := android-xiaomi`

### Шаг 2 — `crdroid/crdroid.mk` и оверлеи

```bash
mkdir -p $WORK/device/xiaomi/taoyao/crdroid/overlay/frameworks/base/core/res/res/values
mkdir -p $WORK/device/xiaomi/taoyao/crdroid/overlay/frameworks/base/packages/SystemUI/res/values

cp ~/crdroid-kit/crdroid_taoyao.mk \
   $WORK/device/xiaomi/taoyao/crdroid/crdroid.mk

# Оверлей framework: punch-hole и скруглённые углы
cat > $WORK/device/xiaomi/taoyao/crdroid/overlay/frameworks/base/core/res/res/values/config.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Нет hardware cutout на taoyao (punch hole сверху по центру, 6.55") -->
    <string name="config_mainBuiltInDisplayCutout" translatable="false"></string>
    <string name="config_mainBuiltInDisplayCutoutRectApproximation" translatable="false"></string>
    <!-- Скруглённые углы панели (stock ~88 dp) -->
    <dimen name="rounded_corner_radius">88dp</dimen>
    <dimen name="rounded_corner_radius_top">88dp</dimen>
    <dimen name="rounded_corner_radius_bottom">40dp</dimen>
</resources>
XML

# Оверлей SystemUI: отключить защиту cutout (нет notch)
cat > $WORK/device/xiaomi/taoyao/crdroid/overlay/frameworks/base/packages/SystemUI/res/values/config.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <bool name="config_enableDisplayCutoutProtection">false</bool>
</resources>
XML
```

### Шаг 3 — `BoardConfig.mk` (две строки)

Дописать в конец `$WORK/device/xiaomi/taoyao/BoardConfig.mk`:

```makefile
# Явно отключаем GCC 4.9 (clang r563880c собирает 5.4 BSP без GCC)
TARGET_KERNEL_NO_GCC := true

# Монолитное ядро — нет модулей .ko
BOARD_VENDOR_KERNEL_MODULES :=
```

### Шаг 4 — проверка дефконфига

```bash
grep -E 'CONFIG_(KSU|KSU_MANUAL_HOOK|MODULES|KPROBES)(=| )|^# CONFIG_(MODULES|KPROBES|KSU_SUSFS|KPM) ' \
    $WORK/kernel/xiaomi/taoyao/arch/arm64/configs/taoyao_defconfig
# Ожидаемый вывод:
# CONFIG_KSU=y
# CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_MODULES=n (или # CONFIG_MODULES is not set)
# CONFIG_KPROBES=n (или # CONFIG_KPROBES is not set)
# # CONFIG_KSU_SUSFS is not set
# # CONFIG_KPM is not set
```

После всех четырёх шагов запускайте `./build_crdroid.sh smoke`, а затем `./build_crdroid.sh build`.
