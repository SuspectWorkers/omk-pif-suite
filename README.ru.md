<div align="center">

# OMK PIF Suite

**Настройка и проверка Play Integrity в один тап для Oh My KeyMint и PlayIntegrityFork**

[English](./README.md) | **Русский**

<br>

[![Release](https://img.shields.io/github/v/release/SuspectWorkers/omk-pif-suite?style=flat-square&color=4f8cff&label=release)](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest)
![Android](https://img.shields.io/badge/Android-13%20to%2017%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Next%20%7C%20BakaSU%20%7C%20Magisk%20%7C%20APatch-222938?style=flat-square)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](./LICENSE)

</div>

---

Публичные keybox постоянно улетают в бан, `autopif4` периодически выбирает профиль не под вашу версию Android, а каждый раз вручную синхронизировать `PlayIntegrityFork` с `Oh My KeyMint` и бегать проверять вердикт в сторонних программах быстро надоедает.

**OMK PIF Suite** собирает всю настройку в одну кнопку питания и сразу внутри модуля показывает, проходит ли устройство Basic, Device и Strong.

## Почему Oh My KeyMint

В отличие от TrickyStore, **Oh My KeyMint** работает как полноценный эмулятор TEE-раздела, а не просто перехватывает вызовы keystore поверх системы. За счёт этого хардварная аттестация выглядит для сервисов Google заметно чище и надёжнее.

## Что делает модуль

1. **Автосинхронизация с PlayIntegrityFork**
   Скачивает свежий Canary через `autopif4.sh`, подбирает совместимый Pixel-профиль под ваш Android SDK (`A13`..`A17+`) и выставляет нужные параметры в `custom.pif.prop` (`spoofBuild`, `spoofProps`, `spoofVendingFinger`).

2. **Перебор keybox из разных источников и проверка на бан**
   По очереди проверяет **Specter**, **MeowDump**, **Yurikey** или ваш собственный URL. Перед установкой валидирует даты X.509 и сверяет каждый сертификат цепочки по живому списку отзывов Google CRL (`android.googleapis.com/attestation/status`). Если все публичные keybox забанены, модуль аккуратно переходит в режим `BASIC`, чтобы не получить пустые `Labels: []`.

3. **Автосинхронизация с Oh My KeyMint**
   Прописывает `brand`, `device`, `manufacturer`, `model`, `product`, `vb_hash` и все 4 поля патча безопасности в `config.toml`, автоматически добавляет все установленные пользовательские приложения в `scoop` `injector.toml` (оставляя `system_server` и системные процессы под защитой фильтра), сбрасывает старый кеш аттестации Play Store и перезапускает OMK.

4. **Собственная система проверки Integrity**
   Тихо в фоне запрашивает реальный вердикт Play Integrity (без открытия Play Маркета, имитации нажатий, сторонних чекеров и со сбросом локального лимита `-8`) и показывает статус по трём уровням: Basic, Device и Strong.
   - Если все три галочки уже есть, модуль не трогает рабочий keybox и фингерпринт.
   - Если Strong или Device не проходит, проверяет keybox: при бане меняет его на живой, а если keybox жив, перебирает профили и проверяет Integrity до прохождения.

---

## `AUTO` и `PRO`

| Режим | Для чего | Что внутри |
|---|---|---|
| **`AUTO`** *(по умолчанию)* | На каждый день | Статусы `Basic`, `Device`, `Strong` над круглой кнопкой питания (`ON` / `BASIC` / `AUTO`). Запускает полный цикл синхронизации, перебора и проверки с живой трассировкой и анимированными галочками результата. |
| **`PRO`** | Ручной контроль | Выбор источника keybox (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), пресеты под Android 12..17+ (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), ручная проверка Integrity / CRL / остатка квоты, вставка своего `keybox.xml` и полный редактор `custom.pif.prop`. |

---

## Что нужно для работы

- **Zygisk**
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Установка

1. Скачайте `omk_pif_suite.zip` из [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest) *(дальше модуль обновляется сам через `updateJson`)*.
2. Установите через менеджер root-прав и перезагрузите устройство.
3. Откройте **WebUI** и нажмите кнопку питания в **`AUTO`**.

---

## Флаги (`/data/adb/`)

| Файл | Назначение |
|---|---|
| `omk_pif_sync_keep_keybox` | Не перезаписывать ваш приватный `keybox.xml` при автосинхронизации |
| `omk_pif_sync_no_tangorpro` | Оставлять случайный профиль от `autopif4.sh` без подбора под SDK |

---

<details>
<summary>Связанные модули для чистых AOSP / кастомных ROM</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync): прописывает SHA-256 `/dev/block/by-name/vbmeta` в `/data/adb/boot_hash` и `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props): очистка пропов кастомных ROM / `userdebug` / `test-keys` до старта `zygote`
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks): оптимизации производительности, DPI и установки пакетов (`CMR-W09`)

</details>
