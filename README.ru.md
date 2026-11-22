<div align="center">

# OMK PIF Suite

**Настройка Play Integrity в один тап для Oh My KeyMint и PlayIntegrityFork**

[English](./README.md) | **Русский**

<br>

[![Release](https://img.shields.io/github/v/release/SuspectWorkers/omk-pif-suite?style=flat-square&color=4f8cff&label=release)](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest)
![Android](https://img.shields.io/badge/Android-13%20%E2%86%92%2017%2B-3ddc84?style=flat-square)
![Root](https://img.shields.io/badge/KernelSU%20%7C%20Next%20%7C%20BakaSU%20%7C%20Magisk%20%7C%20APatch-222938?style=flat-square)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](./LICENSE)

</div>

---

Публичные keybox отзывают каждые пару дней, `autopif4` периодически подсовывает забаненный профиль, а одна сбитая настройка в `injector.toml` способна заблокировать разблокировку телефона по PIN-коду.

**OMK PIF Suite** убирает ручную возню с конфигами: модуль сам находит живой keybox, проверяет реальный вердикт на серверах Google и следит, чтобы фильтры Oh My KeyMint никогда не сломали систему.

## Почему это удобно

- **Режим `AUTO` с одной кнопкой** — нажимаете центральную кнопку питания и забываете. Модуль сам скачивает свежий Canary, подбирает Pixel-профиль под Android вашего устройства (`A13–A17+`), перебирает провайдеров keybox до первого живого, сверяет всю цепочку сертификатов с CRL Google, синхронизирует OMK и проверяет итоговый вердикт. Если все публичные keybox мертвы — сам откатывается на безопасный режим `BASIC`, чтобы не словить `Labels: []`.
- **Собственная автономная система проверки Integrity** — проверяет реальный вердикт полностью в фоне: без открытия Play Маркета, эмуляции нажатий на экран и сторонних чекеров. Умеет сбрасывать локальный 5-запросный лимит Play Store (ошибка `-8 TOO_MANY_REQUESTS`) при переборе профилей и показывает дневной запас проверок прямо в статусе.
- **Живая трассировка под спиннером** — вместо глухого ожидания на экране в реальном времени бежит понятный лог каждого шага: загрузка Canary, проверка CRL, синхронизация OMK, попытки подбора фингерпринта — и финальный 3-секундный неоновый экран результата.
- **Защита от бутлупа экрана блокировки** — перед включением `[main].enabled = true` в `/data/misc/keystore/omk/injector.toml` модуль проверяет секцию `[filter]` (`enabled = true` и `block_android_package = true`). Если фильтр небезопасен, включение жёстко блокируется, чтобы `system_server` всегда шёл в системный Keystore и PIN-код не ломался.
- **Атомарная запись и чистый `uninstall.sh`** — любые правки конфигов OMK сохраняются через временный файл с сохранением владельца, прав и SELinux-контекста, а при удалении модуля аккуратно откатываются только собственные изменения.
- **Авто-обновление** — встроен `updateJson`, менеджеры (KernelSU / Next / BakaSU / Magisk) видят новые версии сами.

---

## `AUTO` и `PRO`

| Режим | Для чего | Что на экране |
|---|---|---|
| **`AUTO`** *(по умолчанию)* | На каждый день | Одна круглая кнопка питания с индикатором состояния (`ON` / `BASIC` / `AUTO`). Запускает полный цикл настройки и проверки. |
| **`PRO`** | Тонкая настройка | Выбор провайдера keybox (`Auto`, `Specter`, `MeowDump`, `Yurikey`, `Custom URL`), пресеты под Android 12–17+ (`kodiak`, `frankel`, `tegu`, `tangorpro`, `felix`, `bluejay`), ручная проверка Integrity и запаса квоты, вставка своего `keybox.xml`, редакторы `Build Fields` / `System Props` / `Raw`. |

---

## Что нужно для работы

- **Zygisk** (`Zygisk Next` / `ReZygisk`)
- **PlayIntegrityFork** (`v19+`)
- **Oh My KeyMint** (`1.2.6+`)

---

## Установка

1. Скачайте `omk_pif_suite.zip` из [**Latest Release**](https://github.com/SuspectWorkers/omk-pif-suite/releases/latest).
2. Установите через менеджер root-прав и перезагрузите устройство.
3. Откройте **WebUI** и нажмите центральную кнопку питания в **`AUTO`**.

---

## Флаги (`/data/adb/`)

| Файл | Что делает |
|---|---|
| `omk_pif_sync_keep_keybox` | Не перезаписывать ваш приватный `keybox.xml` при автосинхронизации |
| `omk_pif_sync_no_tangorpro` | Оставлять случайный профиль от `autopif4.sh` без подбора под SDK |

---

<details>
<summary>Связанные модули для чистых AOSP / кастомных ROM</summary>

- [**vbmeta-sync**](https://github.com/SuspectWorkers/vbmeta-sync) — прописывает SHA-256 `/dev/block/by-name/vbmeta` в `/data/adb/boot_hash` и `ro.boot.vbmeta.*` (`CMR-W09`)
- [**hide-lineage-props**](https://github.com/SuspectWorkers/hide-lineage-props) — очистка пропов кастомных ROM / `userdebug` / `test-keys` до старта `zygote`
- [**m5-system-tweaks**](https://github.com/SuspectWorkers/m5-system-tweaks) — оптимизации производительности, DPI и установки пакетов (`CMR-W09`)

</details>
