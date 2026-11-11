# Руководство по сборке crDroid 16 для Xiaomi 12 Lite (taoyao)

Ubuntu 24.04 LTS, SM7325 (holi), ядро MeruLink (SukiSU-Ultra + XHID).

---

## Требования

### Железо сервера

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| CPU | 16 vCPU | 32 vCPU |
| RAM | 64 ГБ | 128 ГБ |
| Диск | 400 ГБ SSD | 500–600 ГБ NVMe |
| ОС | Ubuntu 24.04 LTS | то же |

Рекомендуемые провайдеры (ориентировочные цены):
- Hetzner CCX53: 32 vCPU / 128 ГБ — ~0,86 €/час
- Hetzner CCX43: 16 vCPU / 64 ГБ — ~0,44 €/час
- OVH b3-128: 32 vCPU / 128 ГБ — ~0,81 $/час

Удаляйте сервер сразу после того как скачали артефакты — оплата идёт пока он существует.

### Программные зависимости

Устанавливаются автоматически скриптом `server_setup.sh`:

```
git git-lfs curl wget python3 python3-pip repo
build-essential libncurses5-dev libssl-dev bc bison flex
libelf-dev libxml2-utils libz-dev liblz4-tool rsync zip unzip
openjdk-21-jdk
```

---

## Пошаговая инструкция

### Шаг 1. Подготовить сервер

```bash
# Скопировать kit с вашего ПК на сервер (Windows):
scp -r D:\MeruDevTools\ROM_BUILD\crdroid root@СЕРВЕР:/root/crdroid-kit

# На сервере:
sudo bash /root/crdroid-kit/server_setup.sh
```

Скрипт:
- Устанавливает все зависимости
- Создаёт пользователя `build`
- Настраивает swap если RAM < 64 ГБ
- Устанавливает `repo` и `git-lfs`

### Шаг 2. Перейти на пользователя build и запустить tmux

```bash
cp -r /root/crdroid-kit /home/build/crdroid-kit
chmod +x /home/build/crdroid-kit/*.sh
chown -R build:build /home/build
sudo -iu build
tmux new -s crd
cd ~/crdroid-kit
```

**Всегда работайте внутри tmux**: сборка идёт часами, разрыв SSH не прерывает её.
Отсоединиться: `Ctrl+b`, затем `d`. Вернуться: `tmux attach -t crd`.

### Шаг 3. Запустить сборку

```bash
./build_crdroid.sh all
```

Или по стадиям:

```bash
./build_crdroid.sh init      # repo init + taoyao.xml (~5 мин)
./build_crdroid.sh sync      # repo sync (~1-3 ч)
./build_crdroid.sh kernel    # клон ядра из Meddax/taoyao-kernel
./build_crdroid.sh firmware  # проверка образов прошивки
./build_crdroid.sh preflight # проверка деревьев и конфигов
./build_crdroid.sh smoke     # breakfast + m nothing (~15-40 мин)
./build_crdroid.sh build     # m bacon (~2.5-3 ч)
./build_crdroid.sh collect   # артефакты в ~/crdroid/artifacts
```

### Шаг 4. Забрать результат

```bash
# С вашего ПК:
scp -r build@СЕРВЕР:crdroid/artifacts D:\MeruDevTools\ROM_BUILD\artifacts
```

---

## Переменные окружения

```bash
VARIANT=user              # user вместо userdebug
CRDROID_BRANCH=16.0       # ветка crDroid (по умолчанию)
DEPTH=1                   # shallow clone (по умолчанию, экономит ~100 ГБ)
DEPTH=                    # полная история
SYNC_JOBS=16              # параллельные fetches (по умолчанию 8)
FIRMWARE_DIR=/path/fw     # папка с 17 *.img если LFS недоступен
```

Пример:

```bash
VARIANT=user SYNC_JOBS=16 ./build_crdroid.sh all
```

---

## Troubleshooting

### `repo sync` выдаёт ошибку 429

Google ограничивает анонимную синхронизацию. Решение:

1. Перейдите на android.googlesource.com
2. Нажмите "Generate Password"
3. Выполните показанный скрипт на сервере
4. Уменьшите `SYNC_JOBS=4` и повторите

### Git LFS: образы прошивки не скачались

```bash
# Пропустить LFS при sync:
GIT_LFS_SKIP_SMUDGE=1 ./build_crdroid.sh sync

# Извлечь образы из пакета HyperOS 1.0.39.0 EEA на вашем ПК:
python D:\MeruDevTools\ROM_BUILD\kernel\tools\payload_extract.py \
    <путь_к_zip> extract fw \
    abl aop bluetooth cpucp devcfg dsp featenabler hyp imagefv \
    keymaster modem qupfw shrm tz uefisecapp xbl xbl_config

# Загрузить на сервер и собрать:
scp -r fw root@СЕРВЕР:
FIRMWARE_DIR=$HOME/fw ./build_crdroid.sh firmware
```

### Ошибка компиляции ядра

Соберите ядро отдельно для диагностики:

```bash
bash ROM_BUILD/kernel/build/build_kernel.sh
```

Если упал `smoke` или `build` именно на ядре, пришлите последние 150 строк лога:

```bash
tail -150 ~/crdroid/logs/build-*.log
```

### Дублирующиеся правила `DSPVolumeSynchronizer`

Это известная проблема с `hardware/xiaomi` + `hardware/dolby`. Запасные ветки:

```xml
<!-- В taoyao.xml заменить:
<project path="hardware/xiaomi" ... upstream="bka-no-dsp" />
на: -->
<project path="hardware/xiaomi" name="crdroidandroid/android_hardware_xiaomi"
         remote="crdroid" revision="16.0" />
```

### Устаревшие переменные сборки

Android 16 запрещает ряд переменных. Стадия `preflight` их находит.
Список смотрите в `~/crdroid/logs/preflight-*.log`.

### Нехватка памяти при Soong analysis (smoke)

```bash
# Добавить swap вручную:
sudo fallocate -l 32G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
```

---

## Результаты сборки

После успешного `collect` в `~/crdroid/artifacts/`:

| Файл | Описание |
|---|---|
| `crDroidAndroid-16.0-*-taoyao-*.zip` | OTA пакет прошивки |
| `boot.img` | Образ загрузчика |
| `vendor_boot.img` | Vendor boot |
| `dtbo.img` | Device tree blob overlay |
| `manifest-pinned.xml` | Точные коммиты всех проектов |
| `kernel.txt` | Информация о ядре |
| `SHA256SUMS` | Контрольные суммы |

---

## Установка на телефон

```bash
# Windows (PowerShell):
fastboot -w
fastboot flash vendor_boot vendor_boot.img
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot reboot recovery
adb sideload crDroidAndroid-16.0-*-taoyao-*.zip
```

**`fastboot -w` стирает данные.** Держите zip текущей прошивки как резервную копию.

---

## Прошивочные разделы

Образы должны совпадать с OS1.0.39.0.ULIEUXM на телефоне (17 разделов: `xbl`, `abl`, `tz`, `hyp`,
`modem` и другие). Стадия `firmware` сохраняет их хеши в `~/crdroid/logs/firmware-sha256.txt`.

Не устанавливайте OTA с другими прошивочными образами без проверки совместимости.

---

## Ссылки

- crDroid 16.0 manifest: https://github.com/crdroidandroid/android/tree/16.0
- taoyao-crdroid: https://github.com/Meddax/taoyao-crdroid
- taoyao-kernel (MeruLink): https://github.com/Meddax/taoyao-kernel
- SukiSU-Ultra: https://github.com/SukiSU-Ultra/SukiSU-Ultra (builtin branch)
