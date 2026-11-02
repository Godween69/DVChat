<!--
SPDX-FileCopyrightText: 2026-Present DVB Studio

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Карта проекта DVChat

Семейный мессенджер на протоколе Matrix. Клиент это Flutter (форк FluffyChat 2.10.0, AGPL-3.0),
сервер это Synapse с модулями из каталога `server/`. Платформы: `android` (основная) и `web`.

## Как течёт приложение

1. `lib/main.dart`: вход. Сначала переносит старые данные (`utils/legacy_migration.dart`),
   создаёт клиенты Matrix (`utils/client_manager.dart`), запускает `widgets/dvchat_app.dart`.
2. `lib/config/routes.dart`: все экраны и переходы (go_router).
3. `lib/widgets/matrix.dart`: «центральный пульт»: хранит клиенты, вход и выход,
   подписки на уведомления, блокировку приложения.
4. Экраны лежат в `lib/pages/<имя>/` парой: `имя.dart` (логика) и `имя_view.dart` (внешний вид).

## Что есть только в DVChat (не из FluffyChat)

- `utils/sign_in_flows/link_login.dart`: вход по ссылке или QR `dvchat://login#...`
- `utils/dv_api.dart`: запросы к серверному модулю `dv_social` (ID, друзья, заявки, профиль)
- `pages/friends/`: экран друзей и заявок
- `widgets/dv_my_id.dart`: показ и копирование своего ID
- `widgets/dv_qr.dart`: единая отрисовка QR-кода (на экране и PNG для сохранения)
- `utils/dv_admin.dart`: определяет администратора (видит служебные сведения)
- `utils/dv_share.dart`: передача ссылок и приглашений в другие приложения
- `utils/update_checker.dart`: проверка и установка обновлений (`version.json`, контрольная сумма sha256)
- `utils/room_archive_extension.dart` и `pages/archive/`: архив личных чатов без выхода из комнаты
- `pages/stories/`: истории на сутки (серверная часть: `server/dv_stories.py`)
- `pages/games/`: игры на двоих и против компьютера, статистика (подробнее ниже)
- `pages/liza/`: вкладка «Лиза» (подробнее ниже)
- `widgets/dv_logo.dart`, `widgets/dv_splash.dart`: логотип и заставка
- `utils/legacy_migration.dart`: перенос данных со старых имён (можно удалить, когда все установки обновились)

## Игры (`lib/pages/games/`)

Каждая игра это пара файлов: `*_logic.dart` (правила, ход компьютера) и `*_page.dart` (экран).
Общие части: `game_rules.dart` (справка по правилам), `dv_game_net.dart` (каркас игры с другом:
приглашение, ходы и итог идут служебными событиями `dv.game` в личном чате), `dv_game_sound.dart`
(звуки), `dv_local_stats.dart` и `stats_page.dart` (счёт партий против компьютера).

- `chess_*`: шахматы
- `ckr_*`: русские шашки
- `nardy_*`: короткие нарды
- `domino_*`: домино
- `durak_*`: «Дурак» (подкидной и переводной)
- `bs_*`: морской бой
- `c4_*`: «Четыре в ряд»
- `ttt_*`: крестики-нолики на тетрадном листе

Игры работают без дополнительных сервисов. Против компьютера можно играть без интернета,
с другом ходы идут через личный чат (в зашифрованной комнате события шифруются).

## Лиза (`lib/pages/liza/`)

Помощник на основе ИИ. Клиент ничего не знает о ключах доступа к модели: он отправляет
серверу только токен Matrix самого пользователя. Ключ ИИ, список допущенных людей и лимиты
хранятся на стороне сервера и в этот репозиторий не входят.

- `liza_client.dart`: запросы `status` (можно ли мне пользоваться) и `chat` (ответ потоком) к `/lisa/v1/`
- `liza_page.dart`: выбирает, что показать: чат, анонс или ошибку связи
- `liza_chat.dart`, `liza_announce.dart`: чат и экран «скоро в приложении»
- `liza_history.dart`, `liza_store.dart`, `liza_markdown.dart`: история бесед, хранение и разметка ответов

Без серверного сервиса вкладка недоступна, остальное приложение это не затрагивает.

## Уведомления (цепочка)

Synapse → шлюз уведомлений (Matrix push gateway) → FCM → приложение.

- Android: `android/.../FcmPushService.kt`
- Dart: `utils/background_push.dart` (регистрация), `utils/push_helper.dart` (разбор пуша
  в фоне), `utils/notification_background_handler.dart`, `utils/notification_avatar_extension.dart`,
  `widgets/local_notifications_extension.dart`
- Каналы и идентификаторы: `config/app_config.dart` (`pushNotificationsChannelId`, `pushNotificationsAppId`)
- Адрес шлюза: `config/app_config.dart` (`pushGatewayUrl`, значение из `dvchat.env`)

## Настройки и конфигурация

- `config/app_config.dart`: константы приложения (идентификатор, ссылки, цвета) и значения из `dvchat.env` (сервер, шлюз уведомлений, канал обновлений)
- `dvchat.env.example`: образец файла настроек сборки (настоящий `dvchat.env` в репозиторий не попадает)
- `config/setting_keys.dart`: ключи настроек `dvchat.*` и значения по умолчанию
- `config/themes.dart`: темы
- `utils/account_config.dart`: настройки аккаунта, хранятся на сервере (account data)

## Чат (самая большая часть)

`pages/chat/`: экран переписки: `chat.dart` (логика), `chat_view.dart`, список событий
`chat_event_list.dart`, поле ввода `input_bar.dart` и `chat_input_row.dart`,
запись голоса `recording_*`, вложения `send_file_dialog.dart`, `events/` (пузыри сообщений).

## Остальные экраны (`lib/pages/`)

- `intro`: приветствие, скан QR, вставка ссылки
- `chat_list`: список чатов
- `new_private_chat`, `new_group`: новый личный чат или группа
- `chat_details`, `chat_members`, `chat_permissions_settings`, `chat_access_settings`: сведения о чате, участники, права, доступ
- `chat_search`: поиск по чату
- `chat_encryption_settings`, `key_verification`, `bootstrap`: шифрование, проверка ключей, резервная копия ключей
- `invitation_selection`: приглашение в чат
- `image_viewer`: просмотр картинок
- `settings*`, `device_settings`: настройки (оформление, уведомления, чат, безопасность, пароль, эмодзи, игнор-лист, обратная связь)

## Общие кирпичики

- `lib/widgets/`: переиспользуемые виджеты (аватар, диалоги, блокировка, раскладки `layouts/`)
- `lib/utils/`: вспомогательные функции и расширения над Matrix SDK
  (`matrix_sdk_extensions/`, в том числе локальная база данных с шифрованием)
- `lib/l10n/`: тексты. Шаблон `intl_ru.arb`, остальные файлы генерируются (`l10n.yaml`)

## Сервер (`server/`)

Модули для Synapse на Python. Описание, установка и список адресов: [server/README.md](../server/README.md).

## Сборка и выпуск

Подробно в [DEPLOY.md](DEPLOY.md): сборка Android и веб-версии, подпись, канал обновлений.

## Лицензия

AGPL-3.0-or-later. Файлы `LICENSE`, `LICENSES/`, `NOTICE.md`, `licenses.yaml` и строки SPDX в
исходниках не удалять: они сохраняют авторство исходного FluffyChat.
