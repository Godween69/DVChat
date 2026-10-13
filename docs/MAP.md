# Карта проекта DVChat

Семейный мессенджер на протоколе Matrix. Клиент — Flutter (форк FluffyChat 2.10.0, AGPL-3.0),
сервер — Synapse. Платформы: `android` (основная) и `web` (задел под PWA для iPhone).

## Как течёт приложение

1. `lib/main.dart` — вход. Сначала переносит старые данные (`utils/legacy_migration.dart`),
   создаёт клиенты Matrix (`utils/client_manager.dart`), запускает `widgets/dvchat_app.dart`.
2. `lib/config/routes.dart` — все экраны и переходы (go_router).
3. `lib/widgets/matrix.dart` — «центральный пульт»: хранит клиенты, вход/выход,
   подписки на уведомления, блокировку приложения.
4. Экраны лежат в `lib/pages/<имя>/` парой: `имя.dart` (логика) + `имя_view.dart` (внешний вид).

## Что есть только в DVChat (не из FluffyChat)

| Файл | Зачем |
|---|---|
| `utils/sign_in_flows/link_login.dart` | Вход по ссылке/QR `dvchat://login#...` — паролей у пользователей нет |
| `utils/dv_api.dart` | Запросы к серверному модулю dv_social: твой ID, друзья, заявки |
| `pages/friends/friends_page.dart` | Экран друзей и заявок |
| `widgets/dv_my_id.dart` | Показ и копирование своего ID |
| `utils/dv_admin.dart` | Определяет администратора (видит служебные сведения) |
| `utils/dv_share.dart` | Передача ссылок/приглашений в другие приложения |
| `utils/update_checker.dart` | Проверка и установка обновлений с нашего сервера (version.json, sha256) |
| `utils/room_archive_extension.dart`, `pages/archive/` | Архив личных чатов без выхода из комнаты |
| `widgets/dv_logo.dart`, `widgets/dv_splash.dart` | Логотип и заставка |
| `utils/legacy_migration.dart` | Перенос данных со старых имён Fluffy (можно удалить, когда все установки обновились) |

## Уведомления (цепочка)

Synapse → свой шлюз dvchatgate → FCM → приложение.
- Android: `android/.../FcmPushService.kt`, `UnifiedPushService.kt`
- Dart: `utils/background_push.dart` (регистрация), `utils/push_helper.dart` (разбор пуша
  в фоне), `utils/notification_background_handler.dart`, `utils/notification_avatar_extension.dart`,
  `widgets/local_notifications_extension.dart`
- Каналы и ключи: `config/app_config.dart` (`pushNotificationsChannelId`)

## Настройки и конфиг

- `config/app_config.dart` — константы приложения (appId, ссылки, цвета)
- `config/setting_keys.dart` — ключи настроек `dvchat.*` и их значения по умолчанию
- `config/themes.dart` — темы
- `utils/account_config.dart` — настройки аккаунта, хранятся на сервере (account data)

## Чат (самая большая часть)

`pages/chat/` — экран переписки: `chat.dart` (логика), `chat_view.dart`, список событий
`chat_event_list.dart`, поле ввода `input_bar.dart` / `chat_input_row.dart`,
запись голоса `recording_*`, вложения `send_file_dialog.dart`, `events/` — пузыри сообщений.

## Остальные экраны (`lib/pages/`)

| Папка | Экран |
|---|---|
| `intro` | Приветствие: скан QR, вставка ссылки |
| `chat_list` | Список чатов |
| `new_private_chat`, `new_group` | Новый личный чат / группа |
| `chat_details`, `chat_members`, `chat_permissions_settings`, `chat_access_settings` | Сведения о чате, участники, права, доступ |
| `chat_search` | Поиск по чату |
| `chat_encryption_settings`, `key_verification`, `bootstrap` | Шифрование, проверка ключей, резервная копия ключей |
| `invitation_selection` | Приглашение в чат |
| `image_viewer` | Просмотр картинок |
| `settings`, `settings_style`, `settings_notifications`, `settings_chat`, `settings_security`, `settings_password`, `settings_emotes`, `settings_ignore_list`, `settings_homeserver`, `settings_3pid`, `settings_feedback`, `device_settings` | Настройки |

## Общие кирпичики

- `lib/widgets/` — переиспользуемые виджеты (аватар, диалоги, блокировка, раскладки `layouts/`)
- `lib/utils/` — вспомогательные функции и расширения над Matrix SDK
  (`matrix_sdk_extensions/` — в т.ч. локальная база данных с шифрованием)
- `lib/l10n/` — тексты. Шаблон `intl_ru.arb`, остальные файлы генерируются (`l10n.yaml`)

## Сборка и выпуск

Скрипт `~/dvchat-build.sh` на worker (в репозитории его нет): собирает APK, считает версию
(`pubspec.yaml` MAJOR.MINOR + счётчик PATCH), публикует на VPS в канал обновлений, ставит тег `vX.Y.Z`.

## Лицензия

AGPL-3.0-or-later. Файлы `LICENSE`, `LICENSES/`, `NOTICE.md`, `licenses.yaml` и строки SPDX в
исходниках не удалять: они сохраняют авторство исходного FluffyChat.
