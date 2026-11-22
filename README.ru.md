<div align="center">

# OMK PIF Suite

**Настройка и проверка Play Integrity в один тап для Oh My KeyMint и PlayIntegrityFork**

[English](./README.md) | **Русский**

<br>

[![Release](https://img.shields.io/github/v/release/SuspectWorkers/omk-pif-suite?style=flat-square&color=4f8cff&label=release)](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest)
![Android](https://img.shields.io/badge/Android-13%20%E2%86%92%2017%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Next%20%7C%20BakaSU%20%7C%20Magisk%20%7C%20APatch-222938?style=flat-square)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](./LICENSE)

</div>

---

Публичные keybox регулярно улетают в бан, `autopif4` может вытянуть неподходящий под ваш Android профиль, а вручную каждый раз пересинхронизировать `PlayIntegrityFork` с `Oh My KeyMint` и проверять результат в сторонних программах неудобно.

**OMK PIF Suite** объединяет весь цикл Play Integrity в одну кнопку — и сам проверяет, проходит ли устройство реальную аттестацию.

## Что делает модуль

1. **Автосинхронизация с PlayIntegrityFork** — запускает `autopif4.sh`, автоматически подбирает совместимый Pixel Canary профиль под Android SDK вашего устройства (`A13–A17+`) и выставляет нужные флаги в `custom.pif.prop` (`spoofBuild`, `spoofProps`, `spoofVendingFinger`).
2. **Перебор keybox из разных источников и проверка на бан** — по очереди проверяет **Specter**, **MeowDump**, **Yurikey** или ваш URL, валидирует даты X.509 и каждый сертификат цепочки по живому Google CRL (`android.googleapis.com/attestation/status`) *до* установки. Если все публичные keybox отозваны, модуль сам переходит в режим `BASIC`, чтобы не получить `Labels: []`.
3. **Автосинхронизация с Oh My KeyMint** — прописывает `brand`, `device`, `manufacturer`, `model`, `product`, `vb_hash` и все 4 поля патча безопасности в `config.toml`, очищает устаревший кеш Play Store и перезапускает OMK.
4. **Собственная система проверки Integrity** — тихо в фоне запрашивает реальный вердикт Play Integrity (без открытия Play Маркета, тапов по экрану и сторонних чекеров, со сбросом локального лимита `-8`) и сразу показывает, прошло ли устройство проверку. Если профиль не подошёл — автоматически перебирает другие Pixel-профили, выводя понятный лог шагов прямо под спиннером.

---

## `AUTO` и `PRO`

| Режим | Для чего | Что внутри |
|---|---|---|
| **`AUTO`** *(по умолчанию)* | На каждый день | Одна круглая кнопка питания с индикацией состояния (`ON` / `BASIC` / `AUTO`). Запускает полный цикл синхронизации и проверки с живой трассировкой и неоновым экраном результата. |
| **`PRO`** | Ручной контроль | Выбор источника keybox (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), пресеты под Android 12–17+ (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), ручная проверка Integrity / CRL / остатка квоты, вставка своего `keybox.xml` и полный редактор `custom.pif.prop`. |

---

## Требования

- **Zygisk** (`Zygisk Next` / `ReZygisk`)
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Установка

1. Скачайте `omk_pif_suite.zip` из [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest) *(дальше модуль обновляется автоматически через `updateJson`)*.
2. Установите через менеджер root-прав и перезагрузите устройство.
3. Откройте **WebUI** и нажмите кнопку питания в **`AUTO`**.

---

## Флаги (`/data/adb/`)

| Файл | Назначение |
|---|---|
| `omk_pif_sync_keep_keybox` | Не перезаписывать ваш приватный `keybox.xml` при синхронизации |
| `omk_pif_sync_no_tangorpro` | Оставлять случайный профиль от `autopif4.sh` без подбора под SDK |

---

<details>
<summary>Связанные модули для чистых AOSP / кастомных ROM</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync) — прописывает SHA-256 `/dev/block/by-name/vbmeta` в `/data/adb/boot_hash` и `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props) — очистка пропов кастомных ROM / `userdebug` / `test-keys` до старта `zygote`
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks) — оптимизации производительности, DPI и установки пакетов (`CMR-W09`)

</details>
