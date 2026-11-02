// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общие названия для списка покупок. Вынесены отдельно, чтобы их мог читать и
// код уведомлений, не подтягивая виджеты.

/// Тип связи события «пункт списка»: событие-реакция, привязанное к сообщению со списком
const String dvShopItemRel = 'online.dvbstudio.dvchat.shopping_item';

/// Ключ с данными пункта (id, text, at) в содержимом такого события
const String dvShopItemKey = 'online.dvbstudio.dvchat.shopping_item';
