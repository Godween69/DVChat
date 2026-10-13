<!--
SPDX-FileCopyrightText: 2026-Present DVB Studio

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# DVChat

Закрытый семейный мессенджер на протоколе [Matrix](https://matrix.org). Клиент написан на
[Flutter](https://flutter.dev), работает на Android, веб-версия готовится.
Аккаунты выдаёт администратор: регистрации в приложении нет, вход по ссылке или QR-коду.

DVChat это изменённая версия [FluffyChat](https://github.com/krille-chan/fluffychat) 2.10.0
(см. [NOTICE.md](NOTICE.md)). Исходный код остаётся открытым по лицензии AGPL-3.0-or-later.

## Возможности

- Личные и групповые чаты, сообщения, фото, файлы и голосовые сообщения
- Сквозное шифрование и резервная копия ключей
- Push-уведомления через Firebase, в том числе при закрытом приложении
- Вход по приглашению: ссылка `dvchat://login#...` или QR-код от администратора
- Чат поддержки с администратором и форма обратной связи
- Архив чатов: ушедшие собеседники и скрытые чаты
- Обновления из собственного канала, без магазинов приложений
- Интерфейс только на русском языке

## Как устроено

| Часть | Что делает |
|---|---|
| Этот репозиторий | Клиент: приложение для Android (и веб) |
| Synapse | Сервер Matrix с модулем `dv_social`: комнаты поддержки, связи между людьми |
| Шлюз уведомлений | Принимает пуши от Synapse и передаёт их в Firebase |
| Канал обновлений | Отдаёт `version.json` и APK по секретной ссылке |

Подробная карта кода проекта: [docs/MAP.md](docs/MAP.md) (появится вместе с русскими комментариями в модулях).

## Сборка

Нужны [Flutter](https://flutter.dev) (версия указана в `.tool_versions.yaml`) и [Rust](https://www.rust-lang.org/tools/install)
(для библиотеки шифрования), а также Android SDK.

```sh
git clone https://github.com/Godween69/DVChat.git
cd DVChat
flutter pub get
flutter gen-l10n
flutter analyze        # перед сборкой не должно быть замечаний
flutter run            # отладочный запуск
```

В репозитории намеренно нет секретов. Для сборки релиза нужно положить рядом:

- `android/app/google-services.json`: проект Firebase для push-уведомлений;
- `android/key.properties` и файл ключа подписи (`*.jks`);
- адрес канала обновлений передаётся при сборке: `--dart-define=DVCHAT_UPDATE_URL=...`.

Версия приложения имеет вид `MAJOR.MINOR.PATCH`: первые две цифры лежат в `pubspec.yaml`,
третья и номер сборки подставляются при выпуске.

## Лицензия

AGPL-3.0-or-later, текст в [LICENSE](LICENSE) и [LICENSES/](LICENSES/).
Авторские права на исходный код FluffyChat принадлежат Christian Kußowski и участникам FluffyChat,
заголовки файлов сохранены. Сведения о сторонних материалах (звук уведомления, логотипы, эмодзи для проверки устройств)
лежат в [REUSE.toml](REUSE.toml), общий список зависимостей в `licenses.yaml`.

## Благодарности

- Команде FluffyChat и Christian Kußowski за основу этого приложения.
- Matrix Foundation за перевод эмодзи для проверки устройств (Apache-2.0).
- Фонду Matrix и разработчикам Synapse.
