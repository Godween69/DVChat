// Интерфейс админки. Данные вставляются только через textContent, без innerHTML.
(function () {
  'use strict';
  var $ = function (s) { return document.querySelector(s); };
  function h(tag, attrs) {
    var el = document.createElement(tag);
    attrs = attrs || {};
    Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (k === 'class') el.className = v; else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
      else if (k === 'checked' || k === 'disabled' || k === 'value') el[k] = v; else el.setAttribute(k, v);
    });
    for (var i = 2; i < arguments.length; i++) { var c = arguments[i]; if (c == null || c === false) continue; el.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c); }
    return el;
  }
  function toast(msg) { var t = $('#toast'); t.textContent = msg; t.classList.remove('hidden'); clearTimeout(toast.t); toast.t = setTimeout(function () { t.classList.add('hidden'); }, 3500); }

  function api(method, path, body) {
    var opt = { method: method, headers: { 'X-Requested-With': 'dvchat-admin' }, credentials: 'same-origin' };
    if (body !== undefined) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
    return fetch(path, opt).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (r.status === 401 && j.code === 'LOGIN') { showLogin(); throw new Error('Нужен вход'); }
        if (!r.ok) throw new Error(j.error || ('Ошибка ' + r.status));
        return j;
      });
    });
  }
  var get = function (p) { return api('GET', p); }, post = function (p, b) { return api('POST', p, b || {}); };
  function fail(e) { toast(e.message || 'Ошибка'); }

  function modal(content) { var b = $('#modalBody'); b.textContent = ''; b.appendChild(content); $('#modal').classList.remove('hidden'); }
  function closeModal() { $('#modal').classList.add('hidden'); }
  $('#modal').addEventListener('mousedown', function (e) { if (e.target.id === 'modal') closeModal(); });
  var date = function (ms) { return ms ? new Date(ms).toLocaleString('ru-RU') : '—'; };

  function copyField(text) {
    var inp = h('input', { readonly: 'readonly', value: text });
    return h('div', { class: 'copy' }, inp, h('button', { onclick: function () { inp.select(); navigator.clipboard && navigator.clipboard.writeText(text).then(function () { toast('Скопировано'); }); } }, 'Копировать'));
  }

  // Подтверждение опасного действия вводом имени
  function confirmDanger(title, text, expected, action, label) {
    var inp = h('input', { placeholder: expected });
    var btn = h('button', { class: 'danger', disabled: true, onclick: function () { btn.disabled = true; action(inp.value).then(function () { closeModal(); }).catch(function (e) { fail(e); btn.disabled = false; }); } }, label || 'Удалить');
    inp.addEventListener('input', function () { btn.disabled = inp.value.trim() !== expected; });
    modal(h('div', null, h('h2', null, title), h('p', null, text), h('p', { class: 'muted' }, 'Для подтверждения введите: ', h('b', null, expected)), inp, h('div', { class: 'row mt14',  }, btn, h('button', { onclick: closeModal }, 'Отмена'))));
  }

  function showIssued(res, name) {
    var qr = h('div', { class: 'qrbox' });
    var svg = window.DVQR.svg(res.link, 240);
    if (svg) qr.innerHTML = svg; else qr.textContent = 'Ссылка слишком длинная для QR';
    modal(h('div', null, h('h2', null, 'Ссылка для входа: ' + name),
      h('p', { class: 'muted' }, 'Одноразовая, действует ' + res.ttl_hours + ' ч. Передайте человеку безопасным способом. Повторно этот экран не показывается.'),
      qr, copyField(res.link), h('div', { class: 'row mt14',  }, h('button', { class: 'primary', onclick: closeModal }, 'Готово'))));
  }

  // ---------- Обзор ----------
  function viewOverview(v) {
    v.appendChild(h('h1', null, 'Обзор'));
    var box = h('div', { class: 'grid mt16',  }); v.appendChild(box);
    get('/api/overview').then(function (o) {
      [['Люди', o.users_active], ['Группы', o.rooms_groups], ['Комнат всего', o.rooms_total], ['Осиротевших комнат', o.rooms_orphans], ['Версия Synapse', o.synapse || '—']].forEach(function (p) {
        box.appendChild(h('div', { class: 'stat' }, h('b', null, p[1]), h('span', null, p[0])));
      });
    }).catch(fail);
  }

  // ---------- Люди ----------
  function viewPeople(v) {
    var q = h('input', { placeholder: 'Поиск по имени' });
    var deact = h('input', { type: 'checkbox' });
    var tbody = h('tbody');
    function load() {
      get('/api/users?q=' + encodeURIComponent(q.value) + (deact.checked ? '&deactivated=1' : '')).then(function (r) {
        tbody.textContent = '';
        r.users.forEach(function (u) {
          tbody.appendChild(h('tr', { class: 'click', onclick: function () { userCard(u, load); } },
            h('td', null, u.displayname || u.user_id.slice(1).split(':')[0]), h('td', { class: 'muted' }, u.user_id),
            h('td', null, u.dv_id), h('td', null, u.admin ? h('span', { class: 'tag' }, 'админ') : '', u.deactivated ? h('span', { class: 'tag bad' }, 'удалён') : ''),
            h('td', { class: 'muted' }, date(u.created))));
        });
        if (!r.users.length) tbody.appendChild(h('tr', null, h('td', { colspan: 5, class: 'muted' }, 'Никого нет')));
      }).catch(fail);
    }
    q.addEventListener('input', function () { clearTimeout(q.t); q.t = setTimeout(load, 300); });
    deact.addEventListener('change', load);
    v.appendChild(h('div', { class: 'row' }, h('h1', { class: 'grow' }, 'Люди'), h('button', { class: 'primary', onclick: function () { createUser(load); } }, 'Создать человека')));
    v.appendChild(h('div', { class: 'row mt12',  }, h('div', { class: 'grow' }, q), h('label', { class: 'muted' }, deact, ' удалённые')));
    v.appendChild(h('table', null, h('thead', null, h('tr', null, h('th', null, 'Имя'), h('th', null, 'Учётная запись'), h('th', null, 'ID'), h('th', null, 'Статус'), h('th', null, 'Создан'))), tbody));
    load();
  }

  function createUser(done) {
    var name = h('input', { placeholder: 'Логин: латиница и цифры', autocomplete: 'off' });
    var disp = h('input', { placeholder: 'Отображаемое имя (необязательно)' });
    var ttl = h('select', null, h('option', { value: 24 }, 'Ссылка действует 24 часа'), h('option', { value: 72 }, '72 часа'), h('option', { value: 1 }, '1 час'));
    var btn = h('button', { class: 'primary', onclick: function () {
      btn.disabled = true;
      post('/api/users', { username: name.value, displayname: disp.value, ttl_hours: Number(ttl.value) })
        .then(function (r) { done(); showIssued(r, r.user_id); }).catch(function (e) { fail(e); btn.disabled = false; });
    } }, 'Создать и выдать ссылку');
    modal(h('div', null, h('h2', null, 'Новый человек'), h('div', { class: 'checks' }), name, h('div', { class: 'sp8' }), disp, h('div', { class: 'sp8' }), ttl, h('div', { class: 'row mt14',  }, btn, h('button', { onclick: closeModal }, 'Отмена'))));
    name.focus();
  }

  function userCard(u, reload) {
    var short = u.user_id.slice(1).split(':')[0];
    var info = h('div');
    function act(label, fn, cls) { return h('button', { class: cls || '', onclick: fn }, label); }
    modal(h('div', null, h('h2', null, u.displayname || short), h('p', { class: 'muted' }, u.user_id + (u.dv_id ? ' · ID ' + u.dv_id : '')),
      u.deactivated ? h('p', { class: 'err' }, 'Учётная запись удалена') : h('div', { class: 'row' },
        act('Новая ссылка для входа', function () { post('/api/users/link', { user_id: u.user_id, ttl_hours: 24 }).then(function (r) { showIssued(r, short); }).catch(fail); }),
        act('Выйти на устройствах…', function () { logoutDialog(u); }),
        act('Переименовать', function () { var n = prompt('Новое имя', u.displayname || short); if (n) post('/api/users/rename', { user_id: u.user_id, displayname: n }).then(function () { toast('Готово'); reload(); closeModal(); }).catch(fail); })),
      h('h3', null, 'Устройства'), info,
      u.deactivated || u.admin ? '' : h('div', { class: 'row mt18',  },
        act('Удалить человека…', function () {
          confirmDanger('Удалить ' + short + '?', 'Человек будет выведен из всех групп и чатов, учётная запись деактивирована, вход станет невозможен. Переписка остальных останется.', short,
            function (c) { return post('/api/users/deactivate', { user_id: u.user_id, confirm: c }).then(function () { toast('Удалён'); reload(); }); });
        }, 'danger')),
      h('div', { class: 'mt12' }, h('button', { onclick: closeModal }, 'Закрыть'))));
    if (!u.deactivated) post('/api/users/devices', { user_id: u.user_id }).then(function (r) {
      if (!r.devices.length) info.appendChild(h('p', { class: 'muted' }, 'Нет активных устройств'));
      r.devices.forEach(function (d) { info.appendChild(h('div', { class: 'muted' }, (d.name || d.id) + ' · ' + date(d.last_seen) + (d.ip ? ' · ' + d.ip : ''))); });
    }).catch(function () {});
  }

  // Выход на устройствах: на всех или на всех, кроме выбранного (потеряли или украли телефон)
  function logoutDialog(u) {
    var short = u.user_id.slice(1).split(':')[0];
    var list = h('div', { class: 'mt10' });
    post('/api/users/devices', { user_id: u.user_id }).then(function (r) {
      if (!r.devices.length) list.appendChild(h('p', { class: 'muted' }, 'Нет активных устройств'));
      r.devices.forEach(function (d) {
        list.appendChild(h('div', { class: 'card memberbox' }, h('div', { class: 'row' }, h('div', { class: 'grow' }, h('b', null, d.name || d.id), h('div', { class: 'muted' }, 'был в сети: ' + date(d.last_seen) + (d.ip ? ' · ' + d.ip : ''))),
          h('button', { onclick: function () { post('/api/users/logout-others', { user_id: u.user_id, keep: d.id }).then(function (x) { toast('Остальных устройств отключено: ' + x.devices_removed); closeModal(); }).catch(fail); } }, 'Оставить это, выйти на остальных'))));
      });
    }).catch(fail);
    modal(h('div', null, h('h2', null, 'Выход на устройствах: ' + short),
      h('p', { class: 'muted' }, 'Потеряли или украли телефон: человек входит по новой ссылке на новом устройстве, затем здесь вы оставляете новое устройство и отключаете остальные. Старая переписка вернётся с новым входом, если сервер хранит кодовую фразу шифрования.'),
      list,
      h('div', { class: 'row mt14',  }, h('button', { class: 'danger', onclick: function () { post('/api/users/logout-all', { user_id: u.user_id }).then(function (r) { toast('Устройств отключено: ' + r.devices_removed); closeModal(); }).catch(fail); } }, 'Выйти на всех устройствах'), h('button', { onclick: closeModal }, 'Закрыть')),
      h('p', { class: 'muted' }, 'Внимание: «на всех» отключит и новое устройство. После этого нужна ещё одна ссылка входа.')));
  }

  // ---------- Комнаты ----------
  function viewRooms(v) {
    var KIND = { group: 'группа', direct: 'личная', empty: 'пустая', service: 'служебная', support: 'поддержка' };
    var filter = h('select', null, h('option', { value: '' }, 'Все'), h('option', { value: 'direct' }, 'Личные'), h('option', { value: 'groups' }, 'Группы'), h('option', { value: 'support' }, 'Обращения в поддержку'),
      h('option', { value: 'empty' }, 'Пустые (никого внутри)'), h('option', { value: 'deleted' }, 'С удалёнными аккаунтами'));
    var q = h('input', { placeholder: 'Поиск по названию' });
    var tbody = h('tbody');
    var bar = h('div', { class: 'row mt12' });
    function load() {
      get('/api/rooms?q=' + encodeURIComponent(q.value) + '&filter=' + filter.value).then(function (r) {
        tbody.textContent = ''; bar.textContent = '';
        if (r.empty_count) bar.appendChild(h('button', { class: 'danger', onclick: function () {
          confirmDanger('Удалить пустые комнаты?', 'Будут удалены все комнаты, где никого нет: ' + r.empty_count + '. Служебная комната админки не затрагивается. Это нельзя отменить.', String(r.empty_count),
            function (c) { return post('/api/rooms/delete-empty', { confirm: c }).then(function (x) { toast('Удалено комнат: ' + x.deleted); setTimeout(load, 1500); }); }, 'Удалить пустые');
        } }, 'Удалить пустые комнаты (' + r.empty_count + ')'));
        r.rooms.forEach(function (x) {
          var who = x.people.map(function (p) { return p.label; }).join(', ');
          var expected = x.name || 'удалить';
          tbody.appendChild(h('tr', null, h('td', null, x.label, x.has_deleted ? h('span', { class: 'tag bad' }, 'есть удалённый') : ''),
            h('td', null, KIND[x.kind] || x.kind), h('td', { class: 'muted' }, who || '—', x.note ? h('div', { class: 'muted' }, x.note) : ''),
            h('td', null, x.encrypted ? h('span', { class: 'tag ok' }, 'шифр.') : h('span', { class: 'tag' }, 'без шифр.')),
            h('td', null, x.kind === 'service' ? '' : h('div', { class: 'row' }, h('button', { onclick: function () {
              confirmDanger('Очистить переписку?', 'Все сообщения комнаты «' + x.label + '» будут стёрты на сервере. Комната, участники, друзья и группы останутся. Это нельзя отменить. Файлы и картинки из зашифрованных чатов этой кнопкой с сервера не удаляются. На телефонах, где чат уже открыт, старые сообщения могут оставаться в памяти приложения до его обновления.', 'очистить',
                function (c) { return post('/api/rooms/clear', { room_id: x.room_id, confirm: c }).then(function () { toast('Переписка очищена'); setTimeout(load, 1000); }); }, 'Очистить');
            } }, 'Очистить…'), h('button', { class: 'danger', onclick: function () { confirmDanger('Удалить комнату?', 'Комната «' + x.label + '» будет удалена с сервера у всех участников. Это нельзя отменить.', expected, function (c) { return post('/api/rooms/delete', { room_id: x.room_id, confirm: c }).then(function () { toast('Удаление запущено'); setTimeout(load, 1500); }); }); } }, 'Удалить…')))));
        });
        if (!r.rooms.length) tbody.appendChild(h('tr', null, h('td', { colspan: 5, class: 'muted' }, 'Ничего нет')));
      }).catch(fail);
    }
    q.addEventListener('input', function () { clearTimeout(q.t); q.t = setTimeout(load, 300); }); filter.addEventListener('change', load);
    v.appendChild(h('h1', null, 'Комнаты'));
    v.appendChild(h('div', { class: 'row mt12',  }, h('div', { class: 'grow' }, q), filter));
    v.appendChild(bar);
    v.appendChild(h('table', null, h('thead', null, h('tr', null, h('th', null, 'Комната'), h('th', null, 'Тип'), h('th', null, 'Внутри'), h('th', null, 'Шифрование'), h('th', null, ''))), tbody));
    load();
  }

  // ---------- Группы ----------
  var LADDER = [];
  function viewGroups(v) {
    var tbody = h('tbody');
    function load() {
      get('/api/groups').then(function (r) {
        LADDER = r.ladder; tbody.textContent = '';
        r.groups.forEach(function (g) {
          tbody.appendChild(h('tr', { class: 'click', onclick: function () { groupCard(g, load); } }, h('td', null, g.name || g.room_id), h('td', null, g.members), h('td', null, g.encrypted ? h('span', { class: 'tag ok' }, 'шифр.') : h('span', { class: 'tag' }, 'без шифр.'))));
        });
        if (!r.groups.length) tbody.appendChild(h('tr', null, h('td', { colspan: 3, class: 'muted' }, 'Групп пока нет')));
      }).catch(fail);
    }
    v.appendChild(h('div', { class: 'row' }, h('h1', { class: 'grow' }, 'Группы'), h('button', { class: 'primary', onclick: function () { createGroup(load); } }, 'Создать группу')));
    v.appendChild(h('p', { class: 'muted' }, 'Администратор создаёт группу и сразу выходит из неё: в списках у людей его нет. Права выдаются флажками.'));
    v.appendChild(h('table', null, h('thead', null, h('tr', null, h('th', null, 'Группа'), h('th', null, 'Людей'), h('th', null, 'Защита'))), tbody));
    load();
  }

  function userList(sel) {
    return get('/api/users').then(function (r) { r.users.forEach(function (u) { if (!u.admin) sel(u); }); });
  }

  function createGroup(done) {
    var name = h('input', { placeholder: 'Название группы' }), topic = h('input', { placeholder: 'Тема (необязательно)' });
    var owner = h('select'), boxes = h('div', { class: 'checks' });
    var enc = h('input', { type: 'checkbox', checked: true });
    var hint = h('p', { class: 'muted' });
    var people = [];
    function chosen() { return people.filter(function (p) { return p.cb.checked; }); }
    // Владельца выбирают из тех, кого отметили; пока никого нет, список пуст
    function refresh() {
      var sel = chosen(), prev = owner.value;
      owner.textContent = '';
      if (!sel.length) owner.appendChild(h('option', { value: '' }, 'Сначала выберите участников'));
      sel.forEach(function (p) { owner.appendChild(h('option', { value: p.id }, p.label)); });
      if (sel.some(function (p) { return p.id === prev; })) owner.value = prev;
      owner.disabled = !sel.length;
      var ok = sel.length >= 2 && name.value.trim().length > 0;
      btn.disabled = !ok;
      hint.textContent = sel.length < 2 ? 'Группа — это два человека и больше. Отметьте участников: ' + sel.length + ' из 2.' : (name.value.trim() ? '' : 'Введите название группы.');
    }
    var btn = h('button', { class: 'primary', disabled: true, onclick: function () {
      btn.disabled = true;
      post('/api/groups', { name: name.value, topic: topic.value, owner: owner.value, encrypted: enc.checked, members: chosen().map(function (p) { return p.id; }) })
        .then(function (r) { toast(r.failed.length ? 'Создана, но не все добавлены: ' + r.failed.length : 'Группа создана'); done(); closeModal(); }).catch(function (e) { fail(e); refresh(); });
    } }, 'Создать');
    userList(function (u) {
      var id = u.user_id, label = u.displayname || id;
      var cb = h('input', { type: 'checkbox' }); cb.addEventListener('change', refresh); people.push({ id: id, label: label, cb: cb });
      boxes.appendChild(h('label', null, cb, label));
    }).then(refresh).catch(fail);
    name.addEventListener('input', refresh);
    modal(h('div', null, h('h2', null, 'Новая группа'), name, h('div', { class: 'sp8' }), topic,
      h('h3', null, 'Участники (минимум двое)'), boxes,
      h('h3', null, 'Владелец (получает все права)'), owner,
      h('h3', null, 'Параметры'), h('div', { class: 'card memberbox' }, h('label', { class: 'permrow' }, enc, 'Шифровать группу (сквозное шифрование)'), h('p', { class: 'muted' }, 'Рекомендуется: сообщения читают только участники группы.')),
      hint,
      h('div', { class: 'row mt14',  }, btn, h('button', { onclick: closeModal }, 'Отмена'))));
    refresh();
  }

  function groupCard(g, reload) {
    var body = h('div');
    function draw() {
      post('/api/groups/details', { room_id: g.room_id }).then(function (d) {
        body.textContent = '';
        body.appendChild(h('p', { class: 'muted' }, 'Права устроены лестницей: выдавая «выше», вы автоматически даёте и «ниже».'));
        d.members.forEach(function (m) {
          var boxes = LADDER.map(function (p) {
            var cb = h('input', { type: 'checkbox', checked: m.perms[p.key] });
            cb.addEventListener('change', function () {
              var perms = {}; LADDER.forEach(function (q) { perms[q.key] = false; });
              var lvl = cb.checked ? p.level : LADDER.filter(function (q) { return q.level < p.level; }).pop();
              var target = cb.checked ? p.level : (lvl ? lvl.level : 0);
              LADDER.forEach(function (q) { perms[q.key] = q.level <= target && target > 0; });
              post('/api/groups/perms', { room_id: g.room_id, user_id: m.user_id, perms: perms }).then(draw).catch(function (e) { fail(e); draw(); });
            });
            return h('label', { class: 'muted permrow',  }, cb, p.label);
          });
          body.appendChild(h('div', { class: 'card memberbox',  },
            h('div', { class: 'row' }, h('b', { class: 'grow' }, (m.displayname || m.user_id.slice(1).split(':')[0]) + (m.deactivated ? ' (удалён)' : ''), h('span', { class: 'muted' }, '  ' + m.user_id)),
              h('button', { class: 'danger', onclick: function () { confirmDanger('Убрать из группы?', m.user_id, m.user_id.slice(1).split(':')[0], function () { return post('/api/groups/remove', { room_id: g.room_id, user_id: m.user_id }).then(function () { toast('Убран'); draw(); }); }, 'Убрать'); } }, 'Убрать')),
            (function () { var w = h('div', { class: 'mt6' }); boxes.forEach(function (b) { w.appendChild(b); }); return w; })()));
        });
        var add = h('select'); userList(function (u) { if (!d.members.some(function (m) { return m.user_id === u.user_id; })) add.appendChild(h('option', { value: u.user_id }, u.displayname || u.user_id)); }).then(function () {
          if (add.options.length) body.appendChild(h('div', { class: 'row' }, h('div', { class: 'grow' }, add), h('button', { onclick: function () { post('/api/groups/add', { room_id: g.room_id, members: [add.value] }).then(function (r) { toast(r.failed.length ? 'Не удалось добавить' : 'Добавлен'); draw(); }).catch(fail); } }, 'Добавить в группу')));
        });
      }).catch(fail);
    }
    modal(h('div', null, h('h2', null, g.name || g.room_id), body, h('div', { class: 'mt14' }, h('button', { onclick: function () { closeModal(); reload(); } }, 'Закрыть'))));
    draw();
  }


  // ---------- Лиза: ключ, модели, деньги, запросы ----------
  function usd(n) { n = Number(n) || 0; return '$' + (n < 1 ? n.toFixed(4) : n.toFixed(2)); }
  function num(n) { return (Number(n) || 0).toLocaleString('ru-RU'); }
  function ago(sec) { if (sec == null) return '—'; if (sec < 90) return 'только что'; if (sec < 5400) return Math.round(sec / 60) + ' мин назад'; return Math.round(sec / 3600) + ' ч назад'; }

  function lisaOverview(box, o, reload) {
    var st = o.state;
    var top = h('div', { class: 'card' }, h('h2', null, 'Ключ и состояние'));
    if (!o.panel) top.appendChild(h('p', { class: 'muted' }, 'Каталог данных Лизы не подключён (DVADMIN_LISA_PANEL_DIR): ключ, цены и статистика недоступны.'));
    else if (!st) top.appendChild(h('p', { class: 'muted' }, 'Лиза ещё не записала состояние. Нужен сервер Лизы версии 3.'));
    else {
      var k = st.key || {};
      var stale = st.age > 180;
      top.appendChild(h('p', null, h('span', { class: 'tag ' + (stale ? 'bad' : 'ok') }, stale ? 'Лиза молчит ' + ago(st.age) : 'Лиза работает'), ' версия сервера ' + st.version));
      top.appendChild(h('p', null, 'Ключ OpenRouter: ', h('b', null, k.mask || '—'), ' ', h('span', { class: 'tag ' + (k.ok ? 'ok' : 'bad') }, k.ok ? 'принят' : ('проблема: ' + (k.error || 'не проверен')))));
      top.appendChild(h('p', null, 'Потрачено по ключу: ' + (k.usage == null ? '—' : usd(k.usage)) + '. ' +
        (k.limit == null ? 'Лимит на ключе не задан.' : ('Лимит: ' + usd(k.limit) + ', остаток: ' + (k.remaining == null ? '—' : usd(k.remaining)) + '.'))));
      top.appendChild(h('p', { class: 'muted' }, 'Проверено ' + ago(k.checked ? (Date.now() / 1000 - k.checked) : null) + '. Сам ключ здесь не показывается и не меняется: замена только отдельным скриптом на сервере со скрытым вводом.'));
      var warn = h('input', { type: 'number', step: '0.5', value: o.key_warn_usd });
      top.appendChild(h('div', { class: 'row mt6' }, h('span', { class: 'grow muted' }, 'Предупредить администратора, когда остаток ключа меньше (доллары)'), h('div', null, warn),
        h('button', { onclick: function () { post('/api/lisa/global', { key_warn_usd: Number(warn.value) }).then(function () { toast('Сохранено'); }).catch(fail); } }, 'Сохранить')));
    }
    box.appendChild(top);

    // Модели: порядок = очередь. Первая главная, остальные запасные
    var ids = o.models.map(function (m) { return m.id; });
    var mc = h('div', { class: 'card mt12' }, h('h2', null, 'Модель под именем Лиза'),
      h('p', { class: 'muted' }, 'Первая в списке отвечает людям. Если она не отвечает, подставляется следующая, администратор получает сообщение от служебного бота. Цены за миллион токенов.'));
    function saveModels(list) { return post('/api/lisa/models', { models: list }).then(function () { toast('Порядок моделей сохранён'); reload(); }).catch(fail); }
    o.models.forEach(function (m, i) {
      var active = st && st.active === m.id;
      var price = m.price_in == null ? 'цена неизвестна' : ('вход $' + m.price_in + ' / выход $' + m.price_out);
      var up = h('button', { disabled: i === 0, onclick: function () { var l = ids.slice(); l.splice(i - 1, 2, l[i], l[i - 1]); saveModels(l); } }, '↑');
      var rm = h('button', { disabled: ids.length < 2, onclick: function () { var l = ids.slice(); l.splice(i, 1); saveModels(l); } }, 'Убрать');
      mc.appendChild(h('div', { class: 'row mt6' },
        h('div', { class: 'grow' }, h('b', null, (i === 0 ? 'Главная: ' : 'Запасная ' + i + ': ') + m.id), h('div', { class: 'muted' }, price + (m.vision ? ', понимает картинки' : '') + (m.up === false ? ', причина: ' + (m.error || 'недоступна') : ''))),
        active ? h('span', { class: 'tag ok' }, 'сейчас отвечает') : null,
        m.up === false ? h('span', { class: 'tag bad' }, 'недоступна') : null, up, rm));
    });
    var q = h('input', { placeholder: 'Найти модель в каталоге OpenRouter (например, haiku)' });
    var res = h('div', { class: 'mt6' });
    var timer = null;
    q.addEventListener('input', function () {
      clearTimeout(timer);
      timer = setTimeout(function () {
        get('/api/lisa/catalog?q=' + encodeURIComponent(q.value)).then(function (c) {
          res.textContent = '';
          if (!c.ready) { res.appendChild(h('p', { class: 'muted' }, 'Каталог ещё не загружен Лизой.')); return; }
          c.models.filter(function (m) { return ids.indexOf(m.id) < 0; }).slice(0, 12).forEach(function (m) {
            res.appendChild(h('div', { class: 'row mt6' }, h('div', { class: 'grow' }, h('b', null, m.id), h('div', { class: 'muted' }, 'вход $' + m.price_in + ' / выход $' + m.price_out + (m.context ? ', контекст ' + num(m.context) : ''))),
              h('button', { disabled: ids.length >= 6, onclick: function () { saveModels(ids.concat([m.id])); } }, 'Добавить в конец')));
          });
        }).catch(fail);
      }, 300);
    });
    mc.appendChild(h('h3', null, 'Добавить запасную')); mc.appendChild(q); mc.appendChild(res);
    box.appendChild(mc);

    // Деньги и токены
    var sm = o.stats;
    var money = h('div', { class: 'card mt12' }, h('h2', null, 'Расход'));
    if (!sm) money.appendChild(h('p', { class: 'muted' }, 'Статистики пока нет.'));
    else {
      function line(name, t) { return h('div', { class: 'row mt6' }, h('span', { class: 'grow' }, name), h('span', null, 'запросов: ' + num(t.n) + ', токенов: ' + num(t.tin + t.tout) + ', ' + usd(t.cost))); }
      money.appendChild(line('Сегодня', sm.totals.today)); money.appendChild(line('7 дней', sm.totals.d7)); money.appendChild(line('30 дней', sm.totals.d30));
      var max = Math.max.apply(null, sm.series.map(function (r) { return r.cost; }).concat([0.0001]));
      var bars = h('div', { class: 'bars' });
      sm.series.forEach(function (r) { var b = h('div', { class: 'bar', title: r.day + ': ' + usd(r.cost) + ', запросов ' + r.n }); b.style.height = Math.max(2, Math.round(r.cost / max * 100)) + '%'; bars.appendChild(b); });
      money.appendChild(h('h3', null, 'Деньги по дням (30 дней)')); money.appendChild(bars);
      money.appendChild(h('h3', null, 'По людям'));
      sm.users.forEach(function (u) { money.appendChild(h('div', { class: 'row mt6' }, h('b', { class: 'grow' }, u.label || u.user), h('span', { class: 'muted' }, 'сегодня ' + usd(u.today.cost) + ' · 7 дн ' + usd(u.d7.cost) + ' · 30 дн ' + usd(u.d30.cost) + ' · запросов за 30 дн ' + num(u.d30.n)))); });
      money.appendChild(h('h3', null, 'По моделям (30 дней)'));
      sm.models.forEach(function (m) { money.appendChild(h('div', { class: 'row mt6' }, h('b', { class: 'grow' }, m.model), h('span', { class: 'muted' }, 'ответов: ' + num(m.n) + ', вход: ' + num(m.tin) + ', выход: ' + num(m.tout) + ', ' + usd(m.cost)))); });
      money.appendChild(h('p', { class: 'muted mt6' }, 'Суммы взяты из ответов OpenRouter. Данные обновлены ' + ago(o.stats_age) + '.'));
    }
    box.appendChild(money);
  }

  function lisaGuide(box) {
    var card = h('div', { class: 'card mt12' }, h('h2', null, 'Справочник по DVChat'),
      h('p', { class: 'muted' }, 'Это знания Лизы о приложении: отвечая на вопросы о DVChat, она опирается на этот текст. Добавьте новую функцию или поправьте описание и нажмите «Сохранить»: Лиза подхватит правку сама, в течение нескольких секунд, без перезапуска. Старые версии сохраняются как копии.'));
    get('/api/lisa/guide').then(function (g) {
      if (!g.enabled) { card.appendChild(h('p', { class: 'muted' }, 'Файл справочника не подключён (DVADMIN_LISA_GUIDE).')); return; }
      var ta = h('textarea', { rows: 18 }); ta.value = g.text;
      var cnt = h('span', { class: 'muted' });
      function upd() { cnt.textContent = 'Знаков: ' + ta.value.length + ' из ' + g.max; cnt.style.color = ta.value.length > g.max ? 'var(--danger)' : ''; }
      ta.addEventListener('input', upd); upd();
      card.appendChild(ta);
      card.appendChild(h('div', { class: 'row mt6' }, h('div', { class: 'grow' }, cnt), h('button', { class: 'primary', onclick: function () {
        post('/api/lisa/guide', { text: ta.value }).then(function () { toast('Справочник сохранён'); }).catch(fail);
      } }, 'Сохранить справочник')));
    }).catch(fail);
    box.appendChild(card);
  }

  function lisaRequests(box, o) {
    var card = h('div', { class: 'card mt12' }, h('h2', null, 'Запросы людей'));
    card.appendChild(h('p', { class: 'muted' }, o.settings.log_questions_days > 0
      ? 'Вопросы хранятся ' + o.settings.log_questions_days + ' дн., затем стираются. Людей об этом предупреждает приложение. Читайте только по необходимости.'
      : 'Хранение вопросов выключено: видны только числа.'));
    var list = h('div'); card.appendChild(list);
    var btn = h('button', { onclick: function () {
      btn.disabled = true;
      get('/api/lisa/requests').then(function (r) {
        list.textContent = '';
        if (!r.items.length) list.appendChild(h('p', { class: 'muted' }, 'Пока пусто.'));
        r.items.forEach(function (x) {
          list.appendChild(h('div', { class: 'card memberbox' }, h('div', { class: 'row' }, h('b', { class: 'grow' }, x.label || x.user), h('span', { class: 'muted' }, date(x.ts * 1000) + ' · ' + usd(x.cost))),
            h('div', { class: 'muted' }, x.model + (x.tool && x.tool !== 'none' ? ' · ' + x.tool : '') + (x.ok ? '' : ' · ошибка')),
            h('div', null, x.question || '(вопрос не сохранён)')));
        });
      }).catch(fail).then(function () { btn.disabled = false; });
    } }, 'Показать последние запросы');
    card.appendChild(btn);
    box.appendChild(card);
  }

  // ---------- Лиза ----------
  function viewLisa(v) {
    v.appendChild(h('h1', null, 'Лиза'));
    var root = h('div'); v.appendChild(root);
    function saveGlobal(patch) { return post('/api/lisa/global', patch).then(function () { toast('Сохранено'); }).catch(fail); }
    function saveUser(id, patch) { return post('/api/lisa/user', Object.assign({ user_id: id }, patch)).then(function () { toast('Сохранено'); }).catch(function (e) { fail(e); load(); }); }
    function check(label, on, fn) { var cb = h('input', { type: 'checkbox', checked: on }); cb.addEventListener('change', function () { fn(cb.checked); }); return h('label', { class: 'permrow' }, cb, label); }
    function load() {
      get('/api/lisa').then(function (d) {
        root.textContent = '';
        if (!d.enabled) { root.appendChild(h('p', { class: 'muted' }, 'Файл настроек Лизы не подключён (переменная DVADMIN_LISA_CONFIG).')); return; }
        var ov = h('div'); root.appendChild(ov);
        get('/api/lisa/overview').then(function (o) { lisaOverview(ov, o, load); lisaGuide(ov); lisaRequests(ov, o); }).catch(fail);
        var prompt = h('textarea', { rows: 8 }); prompt.value = d.system_prompt;
        var S = d.settings || {};
        var sset = {
          log_questions_days: h('input', { type: 'number', value: S.log_questions_days }), model_timeout: h('input', { type: 'number', value: S.model_timeout }),
          read_pages: h('input', { type: 'number', value: S.read_pages }), key_warn_usd: h('input', { type: 'number', step: '0.5', value: S.key_warn_usd }),
          search_engines: h('input', { value: (S.search_engines || []).join(', '), placeholder: 'пусто = как настроено в SearXNG' }),
          safesearch: h('select', null, h('option', { value: '2' }, 'строгий (рекомендуется)'), h('option', { value: '1' }, 'умеренный')),
          news_range: h('select', null, h('option', { value: 'day' }, 'за сутки'), h('option', { value: 'week' }, 'за неделю'), h('option', { value: 'month' }, 'за месяц')) };
        sset.safesearch.value = String(S.safesearch || 2); sset.news_range.value = S.news_range || 'week';
        var city = h('input', { value: d.default_city }), search = h('input', { value: d.search_url });
        var lim = {}; ['per_user_per_day', 'global_per_day', 'max_output_tokens', 'max_history_messages'].forEach(function (k) { lim[k] = h('input', { type: 'number', value: d.limits[k] }); });
        var featBoxes = d.features.map(function (f) { return check(f[1] + ' (по умолчанию для всех)', d.features_defaults[f[0]], function (on) { var o = {}; o[f[0]] = on; saveGlobal({ features_defaults: o }); }); });
        var gl = h('div', { class: 'card' }, h('h2', null, 'Общие настройки'),
          check('Лиза доступна всем (иначе только списку ниже)', d.allow_all, function (on) { saveGlobal({ allow_all: on }); }),
          check('Лиза использует поиск и погоду', d.tools_enabled, function (on) { saveGlobal({ tools_enabled: on }); }));
        featBoxes.forEach(function (b) { gl.appendChild(b); });
        gl.appendChild(h('h3', null, 'Инструкция Лизы')); gl.appendChild(prompt);
        gl.appendChild(h('h3', null, 'Город по умолчанию')); gl.appendChild(city);
        gl.appendChild(h('h3', null, 'Адрес поиска (SearXNG)')); gl.appendChild(search);
        gl.appendChild(h('h3', null, 'Интернет-поиск: фильтр взрослого содержимого')); gl.appendChild(sset.safesearch);
        gl.appendChild(h('h3', null, 'Поисковые движки SearXNG (через запятую)')); gl.appendChild(sset.search_engines);
        gl.appendChild(h('h3', null, 'Сколько страниц из результатов читать целиком (0–4)')); gl.appendChild(sset.read_pages);
        gl.appendChild(h('h3', null, 'Свежесть новостей')); gl.appendChild(sset.news_range);
        gl.appendChild(h('h3', null, 'Ждать ответ модели, секунд (потом запасная)')); gl.appendChild(sset.model_timeout);
        gl.appendChild(h('h3', null, 'Хранить вопросы людей, дней (0 = не хранить)')); gl.appendChild(sset.log_questions_days);
        gl.appendChild(h('h3', null, 'Запросов на человека в сутки')); gl.appendChild(lim.per_user_per_day);
        gl.appendChild(h('h3', null, 'Запросов всего в сутки')); gl.appendChild(lim.global_per_day);
        gl.appendChild(h('h3', null, 'Длина ответа (токены)')); gl.appendChild(lim.max_output_tokens);
        gl.appendChild(h('h3', null, 'Сообщений истории')); gl.appendChild(lim.max_history_messages);
        gl.appendChild(h('div', { class: 'mt14' }, h('button', { class: 'primary', onclick: function () {
          saveGlobal({ system_prompt: prompt.value, default_city: city.value, search_url: search.value,
            safesearch: Number(sset.safesearch.value), news_range: sset.news_range.value, read_pages: Number(sset.read_pages.value),
            model_timeout: Number(sset.model_timeout.value), log_questions_days: Number(sset.log_questions_days.value),
            search_engines: sset.search_engines.value.split(',').map(function (x) { return x.trim(); }).filter(Boolean), limits: {
            per_user_per_day: Number(lim.per_user_per_day.value), global_per_day: Number(lim.global_per_day.value),
            max_output_tokens: Number(lim.max_output_tokens.value), max_history_messages: Number(lim.max_history_messages.value) } });
        } }, 'Сохранить общие настройки')));
        root.appendChild(gl);
        var ppl = h('details', { class: 'mt16' }, h('summary', null, 'Люди: доступ, лимиты, возможности и игры (' + d.people.length + ')')); root.appendChild(ppl);
        ppl.appendChild(h('p', { class: 'muted' }, 'Свои права для каждого: доступ, лимит, возможности и игры. Пустой флажок возможности = как по умолчанию. Доступ к чатам включайте только с согласия человека: Лиза видит лишь то, что приложение отправит по его команде.'));
        d.people.forEach(function (p) {
          var name = p.displayname || p.user_id;
          var box = h('div', { class: 'card memberbox' }, h('div', { class: 'row' }, h('b', { class: 'grow' }, name), p.admin ? h('span', { class: 'tag' }, 'админ') : null, p.dv_id ? h('span', { class: 'tag' }, 'ID ' + p.dv_id) : h('span', { class: 'tag bad' }, 'ещё не входил')));
          if (!p.admin) {
            box.appendChild(check('Лиза разрешена', p.allowed, function (on) { saveUser(p.user_id, { allowed: on }); }));
            var lm = h('input', { type: 'number', placeholder: 'свой лимит в сутки', value: p.limit == null ? '' : p.limit });
            lm.addEventListener('change', function () { saveUser(p.user_id, { limit: lm.value === '' ? null : Number(lm.value) }); });
            box.appendChild(h('div', { class: 'mt6' }, lm));
          }
          d.features.forEach(function (f) {
            var cur = p.features[f[0]]; var sel = h('select', null, h('option', { value: '' }, 'как у всех'), h('option', { value: '1' }, 'включено'), h('option', { value: '0' }, 'выключено'));
            sel.value = cur === undefined ? '' : (cur ? '1' : '0');
            sel.addEventListener('change', function () { var o = {}; o[f[0]] = sel.value === '' ? null : sel.value === '1'; saveUser(p.user_id, { features: o }); });
            box.appendChild(h('div', { class: 'row mt6' }, h('span', { class: 'grow muted' }, f[1]), h('div', null, sel)));
          });
          box.appendChild(h('h3', null, 'Игры (флажок = доступна)'));
          var off = p.games_off.slice();
          d.games.forEach(function (g) {
            box.appendChild(check(g[1], off.indexOf(g[0]) < 0, function (on) {
              off = off.filter(function (x) { return x !== g[0]; }); if (!on) off.push(g[0]);
              saveUser(p.user_id, { games_off: off });
            }));
          });
          ppl.appendChild(box);
        });
      }).catch(fail);
    }
    load();
  }

  // ---------- Настройка ----------
  function viewSetup(v) {
    v.appendChild(h('h1', null, 'Настройка'));
    var checks = h('div', { class: 'card mt12',  }, h('h2', null, 'Проверка сервера'));
    v.appendChild(checks);
    get('/api/setup/check').then(function (r) { r.checks.forEach(function (c) { checks.appendChild(h('p', null, h('span', { class: 'tag ' + (c.ok ? 'ok' : 'bad') }, c.ok ? 'ок' : 'проблема'), c.text)); }); }).catch(fail);

    var hs = h('input', { placeholder: 'chat.example.org' }), push = h('input', { placeholder: 'https://push.example.org (необязательно)' }), upd = h('input', { placeholder: 'https://updates.example.org/путь (необязательно)' });
    var out = h('pre', { class: 'hidden' });
    get('/api/setup/env').then(function (r) {
      r.text.split('\n').forEach(function (l) { var m = /^(\w+)=(.*)$/.exec(l); if (!m) return; if (m[1] === 'DVCHAT_HOMESERVER') hs.value = m[2]; if (m[1] === 'DVCHAT_PUSH_GATEWAY') push.value = m[2]; if (m[1] === 'DVCHAT_UPDATE_URL') upd.value = m[2]; });
    }).catch(function () {});
    function vals(save) { return { homeserver: hs.value, pushGateway: push.value, updateUrl: upd.value, save: save }; }
    v.appendChild(h('div', { class: 'card mt16',  }, h('h2', null, 'Файл настроек сборки (dvchat.env)'),
      h('p', { class: 'muted' }, 'Мастер для тех, кто разворачивает свой DVChat: заполните поля, и файл будет создан. Вручную править файл не нужно.'),
      h('h3', null, 'Адрес вашего сервера Matrix'), hs, h('h3', null, 'Шлюз уведомлений'), push, h('h3', null, 'Канал обновлений'), upd,
      h('div', { class: 'row mt14',  },
        h('button', { onclick: function () { post('/api/setup/env', vals(false)).then(function (r) { out.textContent = r.text; out.classList.remove('hidden'); }).catch(fail); } }, 'Показать файл'),
        h('button', { class: 'primary', onclick: function () { post('/api/setup/env', vals(true)).then(function (r) { out.textContent = r.text; out.classList.remove('hidden'); toast('Сохранено: ' + r.path); }).catch(fail); } }, 'Сохранить файл')), out));
  }

  // ---------- Каркас ----------
  var views = { overview: viewOverview, people: viewPeople, groups: viewGroups, rooms: viewRooms, lisa: viewLisa, setup: viewSetup };
  function route() {
    var tab = (location.hash || '#overview').slice(1); if (!views[tab]) tab = 'overview';
    document.querySelectorAll('.side a').forEach(function (a) { a.classList.toggle('on', a.dataset.tab === tab); });
    var v = $('#view'); v.textContent = ''; views[tab](v);
  }
  function showLogin() { $('#app').classList.add('hidden'); $('#login').classList.remove('hidden'); $('#pw').focus(); }
  function showApp(s) { $('#login').classList.add('hidden'); $('#app').classList.remove('hidden'); $('#srv').textContent = s.server_name || ''; route(); }
  window.addEventListener('hashchange', route);
  $('#loginForm').addEventListener('submit', function (e) {
    e.preventDefault(); $('#loginErr').textContent = '';
    post('/api/login', { password: $('#pw').value }).then(function () { $('#pw').value = ''; return get('/api/session'); }).then(showApp).catch(function (er) { $('#loginErr').textContent = er.message; });
  });
  $('#logout').addEventListener('click', function () { post('/api/logout').then(showLogin); });
  get('/api/session').then(showApp).catch(function (e) { if (e.message !== 'Нужен вход') { showLogin(); $('#loginErr').textContent = e.message; } });
})();
