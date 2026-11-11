# crDroid 16 для Xiaomi 12 Lite (taoyao / SM7325)

Конфигурация сборки crDroid 16 для Xiaomi 12 Lite.
Включает MeruLink kernel (SukiSU-Ultra + XHID stealth).

## Быстрая сборка

### 1. Настройка сервера

```bash
bash server_setup.sh
```

### 2. Инициализация репо

```bash
repo init -u https://github.com/crdroidandroid/android -b 16.0
cp taoyao.xml .repo/local_manifests/
repo sync -c --no-clone-bundle -j$(nproc)
```

### 3. Сборка

```bash
bash build_crdroid.sh all
```

## Что проверено

- Синтаксис скриптов, имена пакетов Ubuntu 24.04
- Манифест `taoyao.xml` совместим с crDroid 16.0 (1187+ проектов, без конфликтов путей)
- Все репозитории и ветки существуют и доступны
- Стадии `kernel`, `firmware`, `preflight` на заглушках

**Сама сборка не запускалась**: это порт без прецедента, ошибки компиляции вероятны.
Скрипты устроены так, чтобы каждую стадию можно было повторить.

## Структура репозитория

```
taoyao-crdroid/
├── README.md                        ← этот файл
├── taoyao.xml                       ← local manifest (device/vendor + kernel)
├── build_crdroid.sh                 ← полный build script (стадии init..collect)
├── server_setup.sh                  ← Ubuntu 24.04 server setup
├── device_config/
│   ├── device_taoyao_crdroid.mk     ← lineage_taoyao.mk для дерева устройства
│   ├── crdroid_taoyao.mk            ← crdroid/crdroid.mk наложение
│   ├── system.prop.crdroid          ← системные свойства crDroid
│   ├── system.prop.merulink         ← системные свойства MeruLink/XHID
│   └── taoyao_crdroid_defconfig.fragment  ← обязательные флаги ядра + чеклист
└── docs/
    └── BUILD_GUIDE.md               ← пошаговая инструкция сборки
```

## Требования к серверу

| Что | Минимум | Лучше |
|---|---|---|
| CPU | 16 vCPU | 32 vCPU |
| RAM | 64 ГБ | 128 ГБ |
| Диск | 400 ГБ SSD | 500–600 ГБ NVMe |
| ОС | Ubuntu 24.04 | то же |

Время: `repo sync` 1–3 ч, сборка ~2,5–3 ч на 32 vCPU. Итого ~4–6 ч, ~3–7 € на Hetzner CCX53.

## Переменные сборки

| Переменная | Значение по умолчанию | Описание |
|---|---|---|
| `VARIANT` | `userdebug` | user/userdebug |
| `CRDROID_BRANCH` | `16.0` | ветка crDroid |
| `DEPTH` | `1` | shallow clone (экономит ~100 ГБ) |
| `SYNC_JOBS` | `8` | параллельные fetches |
| `FIRMWARE_DIR` | — | папка с 17 *.img, если LFS недоступен |

## Стадии

```
./build_crdroid.sh <стадия>
```

| Стадия | Что делает |
|---|---|
| `init` | repo init + taoyao.xml |
| `sync` | repo sync с retry |
| `kernel` | ядро из Meddax/taoyao-kernel в kernel/xiaomi/sm7325 |
| `firmware` | проверка 17 образов прошивки |
| `preflight` | деревья, переменные, BoardConfig |
| `smoke` | breakfast taoyao + m nothing |
| `build` | m bacon |
| `collect` | артефакты в ~/crdroid/artifacts |
| `all` | все стадии по порядку |

## Результат

`~/crdroid/artifacts/`: zip прошивки, `boot.img`, `vendor_boot.img`, `dtbo.img`,
`manifest-pinned.xml`, `kernel.txt`, `SHA256SUMS`.

## Репозиторий

GitHub: https://github.com/Meddax/taoyao-crdroid

## Ядро

GitHub: https://github.com/Meddax/taoyao-kernel (ветка `main`)
SukiSU-Ultra builtin + XHID stealth gadget (MeruLink v3).
