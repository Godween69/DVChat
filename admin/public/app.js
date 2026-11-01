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

  // Кнопка «⋯» с всплывающим меню действий: строка таблицы остаётся одной высоты
  function closeMenus() { document.querySelectorAll('.menu').forEach(function (m) { m.classList.add('hidden'); }); }
  document.addEventListener('click', closeMenus);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeMenus(); });
  function menuButton(items) {
    var pop = h('div', { class: 'menu hidden', role: 'menu' });
    items.forEach(function (it) { pop.appendChild(h('button', { class: 'menuitem' + (it.danger ? ' danger' : ''), role: 'menuitem', onclick: function (e) { e.stopPropagation(); closeMenus(); it.onclick(); } }, it.label)); });
    var btn = h('button', { class: 'dots', title: 'Действия', 'aria-label': 'Действия', 'aria-haspopup': 'menu', onclick: function (e) { e.stopPropagation(); var open = !pop.classList.contains('hidden'); closeMenus(); if (!open) pop.classList.remove('hidden'); } }, '⋯');
    return h('div', { class: 'menuwrap' }, btn, pop);
  }

  // ---------- Статистика игр (общий блок) ----------
  function gamesStatsView(box) {
    box.textContent = '';
    return get('/api/games/stats').then(function (g) {
      if (!g.with_data) {
        box.appendChild(h('p', { class: 'muted' }, 'Данных пока нет. Приложение сохраняет итоги партий в профиле человека (после выхода обновления приложения). Партии внутри зашифрованных чатов сервер не видит, поэтому статистику присылает само приложение. Когда данные появятся, здесь будут: сколько партий, кто во что играет, как часто и кто побеждает.'));
        return g;
      }
      box.appendChild(h('p', { class: 'muted small' }, 'Играли ' + g.with_data + ' из ' + g.people_total + ' человек. Всего партий: ' + num(g.total_played) + '.'));
      var maxP = Math.max.apply(null, g.games.map(function (x) { return x.played; }).concat([1]));
      box.appendChild(h('h3', null, 'Игры'));
      g.games.forEach(function (x) {
        if (!x.played) return;
        var bar = h('div', { class: 'gbar' }); bar.style.width = Math.max(3, Math.round(x.played / maxP * 100)) + '%';
        box.appendChild(h('div', { class: 'gline' }, h('div', { class: 'row' }, h('b', { class: 'grow' }, x.name), h('span', { class: 'muted' }, num(x.played) + ' партий · играют ' + x.players + ' · побед ' + x.won + (x.drawn ? ' · ничьих ' + x.drawn : ''))), bar,
          h('div', { class: 'muted small' }, 'чаще всех: ' + x.top.map(function (t) { return t.label + ' (' + t.played + ')'; }).join(', ') + (x.last ? ' · последняя партия ' + sinceText(x.last) : ''))));
      });
      if (g.has_days) { box.appendChild(h('h3', null, 'Партий по дням (14 дней)')); box.appendChild(barChart(g.series, 'n', function (n) { return n + ' партий'; })); }
      box.appendChild(h('h3', null, 'Люди'));
      var tb = h('tbody');
      g.people.forEach(function (p) {
        tb.appendChild(h('tr', null, h('td', null, p.label), h('td', null, p.favorite_name || '—'), h('td', { class: 'c' }, String(p.played)), h('td', { class: 'c' }, String(p.won)), h('td', { class: 'muted' }, p.last ? sinceText(p.last) : '—')));
      });
      box.appendChild(h('div', { class: 'scroll' }, h('table', null, h('thead', null, h('tr', null, h('th', null, 'Человек'), h('th', null, 'Любимая игра'), h('th', { class: 'c' }, 'Партий'), h('th', { class: 'c' }, 'Побед'), h('th', null, 'Последняя'))), tb)));
      return g;
    });
  }

  // ---------- Обзор ----------
  function sinceText(ms) {
    if (!ms) return 'не заходил';
    var m = Math.round((Date.now() - ms) / 60000);
    if (m < 2) return 'сейчас'; if (m < 90) return m + ' мин назад';
    var hr = Math.round(m / 60); if (hr < 36) return hr + ' ч назад';
    return Math.round(hr / 24) + ' дн назад';
  }
  function barChart(rows, key, fmt) {
    var max = Math.max.apply(null, rows.map(function (r) { return r[key]; }).concat([1]));
    var bars = h('div', { class: 'bars' });
    rows.forEach(function (r) { var b = h('div', { class: 'bar', title: r.day + ': ' + fmt(r[key]) }); b.style.height = Math.max(3, Math.round(r[key] / max * 100)) + '%'; if (!r[key]) b.classList.add('zero'); bars.appendChild(b); });
    return h('div', null, bars, h('div', { class: 'row axis' }, h('span', { class: 'muted grow' }, rows[0].day.slice(5)), h('span', { class: 'muted' }, rows[rows.length - 1].day.slice(5))));
  }
  function viewOverview(v) {
    v.appendChild(h('h1', null, 'Обзор'));
    var box = h('div', { class: 'grid mt16' }); v.appendChild(box);
    var rest = h('div', { class: 'cols mt16' }); v.appendChild(rest);
    get('/api/overview').then(function (o) {
      function tile(val, label, tag, sub, more) {
        var t = h('div', { class: 'stat' + (more ? ' click' : ''), title: more ? 'Нажмите, чтобы посмотреть подробнее' : '' }, h('b', null, val), h('span', null, label), tag || null, sub ? h('div', { class: 'muted small' }, sub) : null, more ? h('div', { class: 'more' }, 'подробнее ›') : null);
        if (more) t.addEventListener('click', more);
        return t;
      }
      function listModal(title, sections) {
        var body = h('div', null, h('h2', null, title));
        sections.forEach(function (sec) {
          body.appendChild(h('h3', null, sec.title + ' (' + sec.rows.length + ')'));
          if (!sec.rows.length) body.appendChild(h('p', { class: 'muted' }, 'Никого'));
          sec.rows.forEach(function (r) { body.appendChild(h('div', { class: 'row mt6 line' }, h('b', { class: 'grow' }, r[0]), h('span', { class: 'muted' }, r[1] || ''))); });
        });
        body.appendChild(h('div', { class: 'mt12' }, h('button', { onclick: closeModal }, 'Закрыть')));
        modal(body);
      }
      var a = o.activity || { d1: 0, d7: 0, d30: 0, total: 0, never: 0, series: [], recent: [] }, k = o.rooms_kinds || {};
      if (o.lisa && o.lisa.connected) {
        var L = o.lisa;
        box.appendChild(tile(L.alive ? 'работает' : 'молчит', 'Лиза', h('span', { class: 'tag ' + (L.alive && L.key_ok !== false ? 'ok' : 'bad') }, L.alive ? (L.key_ok === false ? 'ключ не принят' : 'всё в порядке') : 'нет связи ' + ago(L.age)),
          (L.active ? 'отвечает ' + L.active : 'ни одна модель не отвечает') + ' · моделей в строю ' + L.models_up + ' из ' + L.models_total));
        box.appendChild(tile(num(L.today ? L.today.n : 0), 'Запросов к Лизе сегодня', null, L.today ? usd(L.today.cost) + ' сегодня, ' + usd(L.d7 ? L.d7.cost : 0) + ' за неделю' : '', function () {
          listModal('Запросы к Лизе по людям', [{ title: 'Сегодня', rows: (L.by_user || []).filter(function (u) { return u.n; }).map(function (u) { return [u.label, num(u.n) + ' запр., ' + usd(u.cost)]; }) },
            { title: 'За неделю', rows: (L.by_user || []).map(function (u) { return [u.label, num(u.n7) + ' запр., ' + usd(u.cost7)]; }) }]);
        }));
      } else box.appendChild(tile('—', 'Лиза', h('span', { class: 'tag' }, 'не подключена')));
      box.appendChild(tile(o.users_active, 'Людей', null, 'сегодня заходили ' + a.d1 + ', за неделю ' + a.d7 + (a.never ? ', ещё не входили ' + a.never : ''), function () {
        var all = a.all || [], now = Date.now();
        var row = function (x) { return [x.label, sinceText(x.last_seen)]; };
        listModal('Люди', [{ title: 'Заходили сегодня', rows: all.filter(function (x) { return x.last_seen && now - x.last_seen < 86400e3; }).map(row) },
          { title: 'Заходили за неделю', rows: all.filter(function (x) { return x.last_seen && now - x.last_seen < 7 * 86400e3; }).map(row) },
          { title: 'Давно не заходили', rows: all.filter(function (x) { return x.last_seen && now - x.last_seen >= 7 * 86400e3; }).map(row) },
          { title: 'Ещё не входили', rows: all.filter(function (x) { return !x.last_seen; }).map(row) }]);
      }));
      box.appendChild(tile(k.groups == null ? o.rooms_groups : k.groups, 'Групп', null, (o.groups_list || []).slice(0, 2).map(function (g) { return g.name; }).join(', '), function () {
        listModal('Группы', [{ title: 'Все группы', rows: (o.groups_list || []).map(function (g) { return [g.name, g.members + ' чел.' + (g.encrypted ? ', зашифрована' : '')]; }) }]);
      }));
      box.appendChild(tile(k.direct == null ? '—' : k.direct, 'Личных чатов', null, k.support ? 'и обращений в поддержку: ' + k.support : ''));
      box.appendChild(tile(k.encrypted == null ? '—' : k.encrypted, 'Зашифрованных комнат', null, 'из ' + o.rooms_total));
      box.appendChild(tile(o.rooms_orphans, 'Пустых комнат', o.rooms_orphans ? h('span', { class: 'tag bad' }, 'можно убрать') : h('span', { class: 'tag ok' }, 'порядок')));
      var gt = tile('…', 'Партий сыграно', null, 'статистика игр', function () {
        var body = h('div'), holder = h('div'); body.appendChild(h('h2', null, 'Игры: кто во что играет')); body.appendChild(holder);
        body.appendChild(h('div', { class: 'mt12' }, h('button', { onclick: closeModal }, 'Закрыть')));
        modal(body); gamesStatsView(holder).catch(fail);
      });
      box.appendChild(gt);
      get('/api/games/stats').then(function (g) {
        gt.querySelector('b').textContent = g.with_data ? num(g.total_played) : '—';
        var sub = gt.querySelector('.muted.small'); if (sub) sub.textContent = g.with_data ? 'играли ' + g.with_data + ' из ' + g.people_total + (g.games[0] && g.games[0].played ? ', популярнее всех: ' + g.games[0].name : '') : 'данных пока нет (появятся после обновления приложения)';
      }).catch(function () { gt.querySelector('b').textContent = '—'; });
      box.appendChild(tile(o.synapse || '—', 'Версия Synapse'));

      var c1 = h('div', { class: 'card' }, h('h2', null, 'Заходы людей за 14 дней'), h('p', { class: 'muted small' }, 'Сколько людей в этот день последний раз были в сети. Переписка не читается.'));
      if (a.series.length) c1.appendChild(barChart(a.series, 'n', function (x) { return x + ' чел.'; }));
      c1.appendChild(h('h3', null, 'Кто когда был в сети'));
      a.recent.forEach(function (x) { c1.appendChild(h('div', { class: 'row mt6' }, h('b', { class: 'grow' }, x.label), h('span', { class: 'muted' }, sinceText(x.last_seen)))); });
      rest.appendChild(c1);
      var L2 = o.lisa && o.lisa.series ? o.lisa.series : [];
      var c2 = h('div', { class: 'card' }, h('h2', null, 'Запросы к Лизе за 30 дней'));
      if (L2.length) { c2.appendChild(barChart(L2, 'n', function (x) { return x + ' запросов'; })); c2.appendChild(h('h3', null, 'Расход по дням')); c2.appendChild(barChart(L2, 'cost', usd)); }
      else c2.appendChild(h('p', { class: 'muted' }, 'Статистики пока нет.'));
      rest.appendChild(c2);
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
            h('td', null, u.dv_id), h('td', null, u.root ? h('span', { class: 'tag ok' }, 'корневой админ') : (u.admin ? h('span', { class: 'tag' }, 'админ') : ''), u.deactivated ? h('span', { class: 'tag bad' }, 'удалён') : ''),
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
      u.deactivated ? '' : h('div', null, h('h3', null, 'Друзья и заявки'), friendsBox(u), h('h3', null, 'Уведомления'), notifyBox(u)),
      u.deactivated || u.root ? (u.root ? h('p', { class: 'muted mt12' }, 'Это корневая учётная запись админки: её удалить нельзя.') : '') : h('div', { class: 'row mt18',  },
        act('Удалить человека…', function () {
          confirmDanger('Удалить ' + short + '?', 'Человек будет выведен из всех групп и чатов, учётная запись деактивирована, вход станет невозможен. Переписка остальных останется.', short,
            function (c) { return post('/api/users/deactivate', { user_id: u.user_id, confirm: c }).then(function () { toast('Удалён'); closeModal(); reload(); setTimeout(reload, 1500); }); });
        }, 'danger')),
      h('div', { class: 'mt12' }, h('button', { onclick: closeModal }, 'Закрыть'))));
    if (!u.deactivated) post('/api/users/devices', { user_id: u.user_id }).then(function (r) {
      if (!r.devices.length) info.appendChild(h('p', { class: 'muted' }, 'Нет активных устройств'));
      r.devices.forEach(function (d) { info.appendChild(h('div', { class: 'muted' }, (d.name || d.id) + ' · ' + date(d.last_seen) + (d.ip ? ' · ' + d.ip : ''))); });
    }).catch(function () {});
  }

  // Друзья человека: список связей и входящие заявки. Переписка не читается.
  function friendsBox(u) {
    var box = h('div');
    var btn = h('button', { onclick: function () {
      btn.disabled = true;
      post('/api/users/friends', { user_id: u.user_id }).then(function (r) {
        box.textContent = '';
        if (r.error) { box.appendChild(h('p', { class: 'err' }, 'Не удалось получить: ' + r.error)); return; }
        if (r.all_users) { box.appendChild(h('p', { class: 'muted' }, 'Это администратор: ему видны все люди сервера, отдельного списка друзей нет.')); return; }
        box.appendChild(h('p', { class: 'muted' }, 'Друзей: ' + r.friends.length + (r.requests.length ? ', ждут ответа: ' + r.requests.length : '')));
        r.friends.forEach(function (f) { box.appendChild(h('div', { class: 'row mt6' }, h('b', { class: 'grow' }, f.label), f.best ? h('span', { class: 'tag ok' }, 'лучший') : null, f.dv_id ? h('span', { class: 'tag' }, 'ID ' + f.dv_id) : null)); });
        if (r.requests.length) box.appendChild(h('h3', null, 'Заявки, ожидающие ответа'));
        r.requests.forEach(function (f) { box.appendChild(h('div', { class: 'row mt6' }, h('b', { class: 'grow' }, f.label), f.dv_id ? h('span', { class: 'tag' }, 'ID ' + f.dv_id) : null)); });
        if (!r.friends.length && !r.requests.length) box.appendChild(h('p', { class: 'muted' }, 'Пока никого.'));
      }).catch(fail).then(function () { btn.disabled = false; });
    } }, 'Показать друзей');
    return h('div', null, btn, box);
  }

  // Уведомления человека: на каких устройствах подключены и какие категории включены
  function notifyBox(u) {
    var box = h('div');
    var btn = h('button', { onclick: function () {
      btn.disabled = true;
      post('/api/users/notify', { user_id: u.user_id }).then(function (r) { box.textContent = ''; notifyView(box, u, r); }).catch(fail).then(function () { btn.disabled = false; });
    } }, 'Показать настройки уведомлений');
    return h('div', null, btn, box);
  }
  function notifyView(box, u, r) {
    box.appendChild(h('p', { class: r.pushers.length ? 'muted' : 'err' }, r.pushers.length ? 'Устройств с подключёнными уведомлениями: ' + r.pushers.length : 'Ни одно устройство не подключило уведомления: на телефон они не придут. Человеку нужно открыть приложение и разрешить уведомления.'));
    r.pushers.forEach(function (p) { box.appendChild(h('div', { class: 'muted small' }, (p.device || p.app) + (p.gateway ? ' · шлюз ' + p.gateway : ''))); });
    r.rules.forEach(function (x) {
      var cb = h('input', { type: 'checkbox', checked: x.notifies });
      cb.addEventListener('change', function () { post('/api/users/notify-rule', { user_id: u.user_id, rule_id: x.id, notifies: cb.checked }).then(function () { toast('Сохранено'); }).catch(function (e) { fail(e); cb.checked = !cb.checked; }); });
      box.appendChild(h('label', { class: 'permrow' }, cb, x.label));
    });
    box.appendChild(h('p', { class: 'muted small mt6' }, 'Сервер различает только категории выше. Что внутри зашифрованных чатов (реакции, прочтение, игры), он не видит: это выбирается в самом приложении, в настройках уведомлений.'));
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
            h('td', { class: 'nw' }, KIND[x.kind] || x.kind), h('td', { class: 'muted' }, who || '—', x.note ? h('div', { class: 'muted' }, x.note) : ''),
            h('td', { class: 'nw' }, x.encrypted ? h('span', { class: 'tag ok' }, 'шифр.') : h('span', { class: 'tag' }, 'без шифр.')),
            h('td', { class: 'act' }, x.kind === 'service' ? '' : menuButton([
              { label: 'Очистить переписку…', onclick: function () {
                confirmDanger('Очистить переписку?', 'Все сообщения комнаты «' + x.label + '» будут стёрты на сервере. Комната, участники, друзья и группы останутся. Это нельзя отменить. Файлы и картинки из зашифрованных чатов этой кнопкой с сервера не удаляются. На телефонах, где чат уже открыт, старые сообщения могут оставаться в памяти приложения до его обновления.', 'очистить',
                  function (c) { return post('/api/rooms/clear', { room_id: x.room_id, confirm: c }).then(function () { toast('Переписка очищена'); setTimeout(load, 1000); }); }, 'Очистить');
              } },
              { label: 'Удалить комнату…', danger: true, onclick: function () { confirmDanger('Удалить комнату?', 'Комната «' + x.label + '» будет удалена с сервера у всех участников. Это нельзя отменить.', expected, function (c) { return post('/api/rooms/delete', { room_id: x.room_id, confirm: c }).then(function () { toast('Удаление запущено'); setTimeout(load, 1500); }); }); } }]))));
        });
        if (!r.rooms.length) tbody.appendChild(h('tr', null, h('td', { colspan: 5, class: 'muted' }, 'Ничего нет')));
      }).catch(fail);
    }
    q.addEventListener('input', function () { clearTimeout(q.t); q.t = setTimeout(load, 300); }); filter.addEventListener('change', load);
    v.appendChild(h('h1', null, 'Комнаты'));
    v.appendChild(h('div', { class: 'row mt12',  }, h('div', { class: 'grow' }, q), filter));
    v.appendChild(bar);
    v.appendChild(h('table', null, h('thead', null, h('tr', null, h('th', null, 'Комната'), h('th', null, 'Тип'), h('th', null, 'Внутри'), h('th', null, 'Шифрование'), h('th', { class: 'act' }, ''))), tbody));
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

  // Смена ключа OpenRouter: ключ вводится скрыто и уходит заявкой; применяет и проверяет его служба на сервере
  function changeKey(reload) {
    var inp = h('input', { type: 'password', autocomplete: 'new-password', placeholder: 'sk-or-…', spellcheck: 'false' });
    var status = h('p', { class: 'muted' }, 'Вставьте новый ключ. Он не показывается на экране и не сохраняется в панели. Прежний ключ остаётся, пока новый не пройдёт проверку.');
    var btn = h('button', { class: 'primary' }, 'Проверить и заменить');
    var stopped = false;
    function poll(id, started) {
      if (stopped) return;
      get('/api/lisa/key-status').then(function (s) {
        var r = s.result;
        if (r && r.id === id) {
          if (r.ok) { status.className = ''; status.textContent = ''; status.appendChild(h('span', { class: 'tag ok' }, 'готово')); status.appendChild(document.createTextNode(' ' + (r.message || 'Ключ заменён, Лиза перезапущена.') + (r.mask ? ' Новый ключ: ' + r.mask + '.' : '')));
            status.appendChild(h('p', { class: 'muted small mt6' }, 'Напоминание для администратора сервера: после замены обновите снимок (bash ~/projects/infra/tools/collect-minipc.sh) и закоммитьте, иначе роль files вернёт прежний ключ из сейфа.')); btn.disabled = false; btn.textContent = 'Закрыть'; btn.onclick = function () { stopped = true; closeModal(); reload(); }; return; }
          status.className = 'err'; status.textContent = 'Не заменено: ' + (r.message || 'ключ не принят') + '. Прежний ключ остался.'; btn.disabled = false; return;
        }
        if (Date.now() - started > 90000) {
          status.className = 'err'; status.textContent = 'Служба замены ключа на сервере не ответила за 90 секунд. Заявка отменена. Проверьте, что она установлена (роль minipc_lisa).';
          post('/api/lisa/key-cancel').catch(function () {}); btn.disabled = false; return;
        }
        setTimeout(function () { poll(id, started); }, 2000);
      }).catch(function (e) { fail(e); btn.disabled = false; });
    }
    btn.addEventListener('click', function () {
      btn.disabled = true; status.className = 'muted'; status.textContent = 'Отправляю и жду проверки у OpenRouter (до 30 секунд)…';
      post('/api/lisa/key', { key: inp.value.trim() }).then(function (r) { inp.value = ''; poll(r.id, Date.now()); }).catch(function (e) { status.className = 'err'; status.textContent = e.message; btn.disabled = false; });
    });
    modal(h('div', null, h('h2', null, 'Новый ключ OpenRouter'), inp, status, h('div', { class: 'row mt14' }, btn, h('button', { onclick: function () { stopped = true; closeModal(); } }, 'Отмена'))));
    inp.focus();
  }

  // Колонка «для чего подходит» справа от модели: метки в столбик, подсказка при наведении
  function tagCol(tags) {
    var c = h('div', { class: 'tagcol' });
    (tags || []).forEach(function (t) { c.appendChild(h('div', { class: 'ptag ' + t.key, title: t.hint }, t.label)); });
    return c;
  }
  var TIERS = { free: ['бесплатная', 'ok'], cheap: ['дёшево', 'ok'], middle: ['средняя цена', ''], expensive: ['дорого', 'bad'] };
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
      top.appendChild(h('p', null, 'Баланс на счёте OpenRouter: ', k.credits == null ? h('span', { class: 'muted' }, 'не виден по этому ключу. Смотрите на openrouter.ai/credits.') : h('b', null, usd(k.credits))));
      top.appendChild(h('p', { class: 'muted' }, 'Проверено ' + ago(k.checked ? (Date.now() / 1000 - k.checked) : null) + '. Сам ключ нигде не показывается.'));
      top.appendChild(h('div', { class: 'row' }, h('button', { onclick: function () { changeKey(reload); } }, 'Сменить ключ…')));
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
      var info = m.error_info ? h('button', { class: 'infobtn', title: 'Что значит эта ошибка', 'aria-label': 'Что значит эта ошибка', onclick: function () {
        var e = m.error_info; modal(h('div', null, h('h2', null, e.title + (e.code ? ' (' + e.code + ')' : '')), h('p', null, h('b', null, 'Что случилось: '), e.what), h('p', null, h('b', null, 'Что делать: '), e.todo), h('p', { class: 'muted small' }, 'Модель: ' + m.id), h('div', { class: 'mt12' }, h('button', { onclick: closeModal }, 'Закрыть'))));
      } }, 'i') : null;
      mc.appendChild(h('div', { class: 'row modelrow' + (i % 2 ? ' alt' : '') },
        h('div', { class: 'grow' }, h('b', null, (i === 0 ? 'Главная: ' : 'Запасная ' + i + ': ') + m.id), h('div', { class: 'muted' }, price + (m.up === false ? ', причина: ' + (m.error || 'недоступна') : ''))),
        m.pending ? h('span', { class: 'tag' }, 'ждёт применения Лизой') : null,
        active ? h('span', { class: 'tag ok' }, 'сейчас отвечает') : null,
        m.up === false ? h('span', { class: 'tag bad' }, 'недоступна') : null, info, up, rm, tagCol(m.tags)));
    });
    mc.appendChild(h('h3', null, 'Добавить запасную из каталога OpenRouter'));
    var kind = h('select', null, h('option', { value: '' }, 'Все'), h('option', { value: 'free' }, 'Только бесплатные'), h('option', { value: 'paid' }, 'Только платные'));
    var sortSel = h('select', null, h('option', { value: 'price' }, 'Сначала дешёвые'), h('option', { value: 'name' }, 'По названию'));
    var vis = h('input', { type: 'checkbox' });
    var q = h('input', { placeholder: 'Поиск по названию, например haiku или deepseek' });
    var res = h('div', { class: 'mt6' }), more = h('button', { class: 'hidden' }, 'Показать ещё');
    var offset = 0, timer = null, shown = null;
    function fmtPrice(n) { return n === 0 ? '0' : (n < 0.01 ? n.toFixed(4) : n.toFixed(2)); }
    function load(append) {
      if (!append) { offset = 0; res.textContent = ''; }
      get('/api/lisa/catalog?q=' + encodeURIComponent(q.value) + '&kind=' + kind.value + '&sort=' + sortSel.value + (vis.checked ? '&vision=1' : '') + '&offset=' + offset + '&limit=20').then(function (c) {
        if (!c.ready) { res.appendChild(h('p', { class: 'muted' }, 'Каталог ещё не загружен Лизой (появляется в течение минуты после её запуска).')); return; }
        if (!append && c.recommend && c.recommend.length) {
          var rc = h('div', { class: 'reco' }, h('b', null, 'Подсказки по выбору'), h('p', { class: 'muted small' }, 'Каталог не оценивает качество, поэтому подсказки по цене и возможностям, а не «лучшая модель».'));
          c.recommend.forEach(function (r) {
            rc.appendChild(h('div', { class: 'row mt6' }, h('div', { class: 'grow' }, h('div', null, h('span', { class: 'muted' }, r.title + ': '), h('b', null, r.id)),
              h('div', { class: 'muted small' }, 'вход $' + fmtPrice(r.price_in) + ' / выход $' + fmtPrice(r.price_out) + ' · ' + r.why)),
              h('button', { disabled: ids.indexOf(r.id) >= 0 || ids.length >= 6, onclick: function () { saveModels(ids.concat([r.id])); } }, ids.indexOf(r.id) >= 0 ? 'Уже в списке' : 'Добавить')));
          });
          res.appendChild(rc);
        }
        if (!append) res.appendChild(h('p', { class: 'muted small' }, 'Найдено: ' + c.matched + ' из ' + c.total + ' (бесплатных: ' + c.free_total + '). Цены в долларах за миллион токенов.'));
        c.models.forEach(function (m, idx) {
          var inList = ids.indexOf(m.id) >= 0;
          var tr = TIERS[m.tier];
          res.appendChild(h('div', { class: 'row modelrow' + ((offset + idx) % 2 ? ' alt' : '') }, h('div', { class: 'grow' }, h('b', null, m.id), tr ? h('span', { class: 'tag ' + tr[1] }, tr[0]) : null,
            h('div', { class: 'muted small' }, (m.name !== m.id ? m.name + ' · ' : '') + (m.price_in == null ? 'цена неизвестна' : 'вход $' + fmtPrice(m.price_in) + ' / выход $' + fmtPrice(m.price_out)) + (m.context ? ' · контекст ' + num(m.context) : ''))),
            h('button', { disabled: inList || ids.length >= 6, onclick: function () { saveModels(ids.concat([m.id])); } }, inList ? 'Уже в списке' : 'Добавить в конец'), tagCol(m.tags)));
        });
        offset += c.models.length; more.classList.toggle('hidden', offset >= c.matched);
      }).catch(fail);
    }
    [kind, sortSel, vis].forEach(function (el) { el.addEventListener('change', function () { load(false); }); });
    q.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(function () { load(false); }, 300); });
    more.addEventListener('click', function () { load(true); });
    var openBtn = h('button', { onclick: function () { if (shown) { shown.classList.toggle('hidden'); } else { shown = h('div', null, h('div', { class: 'row' }, h('div', { class: 'grow' }, q), kind, sortSel), h('label', { class: 'permrow mt6' }, vis, 'только модели, которые понимают картинки'), res, more); mc.appendChild(shown); load(false); } } }, 'Показать каталог моделей');
    mc.appendChild(openBtn);
    box.appendChild(mc);

    // Поисковые движки SearXNG: список берёт сама Лиза у своего SearXNG и кладёт файлом
    var ec = h('div', { class: 'card mt12' }, h('h2', null, 'Поисковые движки'));
    var picked = (o.settings.search_engines || []).slice();
    if (!o.engines) {
      ec.appendChild(h('p', { class: 'muted' }, 'Список движков появится, когда Лиза версии 3.1 прочитает его у SearXNG. Пока можно перечислить названия через запятую (пусто = как настроено в SearXNG).'));
      var txt = h('input', { value: picked.join(', '), placeholder: 'например: duckduckgo, wikipedia' });
      ec.appendChild(txt);
      ec.appendChild(h('div', { class: 'mt14' }, h('button', { onclick: function () { post('/api/lisa/global', { search_engines: txt.value.split(',').map(function (x) { return x.trim(); }).filter(Boolean) }).then(function () { toast('Сохранено'); }).catch(fail); } }, 'Сохранить')));
    } else {
      ec.appendChild(h('p', { class: 'muted' }, 'Это движки, включённые в вашем SearXNG: именно из них Лиза собирает результаты. Не отмечено ни одного = все включённые. Чтобы добавить другие (например, Google, Bing, Brave), их надо включить в настройках самого SearXNG: это делается ролью Ansible.'));
      o.engines.forEach(function (e) {
        var on = picked.indexOf(e.name) >= 0;
        var cb = h('input', { type: 'checkbox', checked: on, disabled: !e.enabled });
        cb.addEventListener('change', function () { var i = picked.indexOf(e.name); if (cb.checked && i < 0) picked.push(e.name); if (!cb.checked && i >= 0) picked.splice(i, 1); });
        ec.appendChild(h('label', { class: 'permrow' }, cb, e.name + (e.enabled ? '' : ' (выключен в SearXNG)')));
      });
      ec.appendChild(h('div', { class: 'mt14' }, h('button', { onclick: function () { post('/api/lisa/global', { search_engines: picked }).then(function () { toast('Сохранено'); }).catch(fail); } }, 'Сохранить выбор')));
    }
    box.appendChild(ec);

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
    function saveGlobal(patch) { return post('/api/lisa/global', patch).then(function () { toast('Сохранено'); }).catch(function (e) { fail(e); load(); }); }
    function saveUser(id, patch) { return post('/api/lisa/user', Object.assign({ user_id: id }, patch)).then(function () { toast('Сохранено'); }).catch(function (e) { fail(e); load(); }); }
    function check(label, on, fn) { var cb = h('input', { type: 'checkbox', checked: on }); cb.addEventListener('change', function () { fn(cb.checked); }); return h('label', { class: 'permrow' }, cb, label); }
    function load() {
      get('/api/lisa').then(function (d) {
        root.textContent = '';
        if (!d.enabled) { root.appendChild(h('p', { class: 'muted' }, 'Файл настроек Лизы не подключён (переменная DVADMIN_LISA_CONFIG).')); return; }
        var PANES = [['state', 'Состояние и модели'], ['access', 'Доступ и люди'], ['settings', 'Настройки'], ['guide', 'Справочник'], ['reqs', 'Запросы']];
        var pane = {}, tabs = h('div', { class: 'subtabs' });
        PANES.forEach(function (x) { pane[x[0]] = h('div', { class: x[0] === 'state' ? '' : 'hidden' }); });
        function show(name) { try { sessionStorage.setItem('lisaPane', name); } catch (e) { /* без памяти */ } PANES.forEach(function (x) { pane[x[0]].classList.toggle('hidden', x[0] !== name); tabs.querySelector('[data-p="' + x[0] + '"]').classList.toggle('on', x[0] === name); }); }
        PANES.forEach(function (x) { tabs.appendChild(h('button', { 'data-p': x[0], onclick: function () { show(x[0]); } }, x[1])); });
        root.appendChild(tabs); PANES.forEach(function (x) { root.appendChild(pane[x[0]]); });
        var start = 'state'; try { start = sessionStorage.getItem('lisaPane') || 'state'; } catch (e) { /* без памяти */ } if (!pane[start]) start = 'state'; show(start);
        get('/api/lisa/overview').then(function (o) { lisaOverview(pane.state, o, load); lisaGuide(pane.guide); lisaRequests(pane.reqs, o); }).catch(fail);
        var prompt = h('textarea', { rows: 8 }); prompt.value = d.system_prompt;
        var S = d.settings || {};
        var sset = {
          log_questions_days: h('input', { type: 'number', value: S.log_questions_days }), model_timeout: h('input', { type: 'number', value: S.model_timeout }),
          read_pages: h('input', { type: 'number', value: S.read_pages }), key_warn_usd: h('input', { type: 'number', step: '0.5', value: S.key_warn_usd }),
          safesearch: h('select', null, h('option', { value: '2' }, 'строгий (рекомендуется)'), h('option', { value: '1' }, 'умеренный')),
          news_range: h('select', null, h('option', { value: 'day' }, 'за сутки'), h('option', { value: 'week' }, 'за неделю'), h('option', { value: 'month' }, 'за месяц')) };
        sset.safesearch.value = String(S.safesearch || 2); sset.news_range.value = S.news_range || 'week';
        var city = h('input', { value: d.default_city }), search = h('input', { value: d.search_url });
        var lim = {}; ['per_user_per_day', 'global_per_day', 'max_output_tokens', 'max_history_messages'].forEach(function (k) { lim[k] = h('input', { type: 'number', value: d.limits[k] }); });
        // Кому доступна Лиза: общий флажок и, если он снят, список людей с флажками прямо здесь
        var ac = h('div', { class: 'card' }, h('h2', null, 'Кому доступна Лиза'));
        ac.appendChild(check('Лиза доступна всем', d.allow_all, function (on) { saveGlobal({ allow_all: on }).then(load); }));
        ac.appendChild(h('p', { class: 'muted small' }, d.allow_all ? 'Сейчас Лизу видят все, у кого она не отключена лично. Снимите флажок, чтобы выбрать людей по списку.' : 'Лиза доступна только администраторам и людям, отмеченным ниже. Остальные Лизу не увидят.'));
        if (!d.allow_all) {
          var list = h('div'), find = h('input', { placeholder: 'Найти человека' }), cnt = h('span', { class: 'muted' });
          var rows = d.people.filter(function (p) { return !p.admin; });
          var allowed = {}; rows.forEach(function (p) { allowed[p.user_id] = p.allowed; });
          function recount() { cnt.textContent = 'Доступна ' + rows.filter(function (p) { return allowed[p.user_id]; }).length + ' из ' + rows.length; }
          function draw() {
            list.textContent = ''; var f = find.value.trim().toLowerCase();
            rows.filter(function (p) { return !f || (p.displayname || p.user_id).toLowerCase().indexOf(f) >= 0; }).forEach(function (p) {
              var cb = h('input', { type: 'checkbox', checked: allowed[p.user_id], disabled: !p.dv_id });
              cb.addEventListener('change', function () { allowed[p.user_id] = cb.checked; recount(); saveUser(p.user_id, { allowed: cb.checked }); });
              list.appendChild(h('label', { class: 'permrow listrow' }, cb, h('span', { class: 'grow' }, p.displayname || p.user_id), p.dv_id ? h('span', { class: 'tag' }, 'ID ' + p.dv_id) : h('span', { class: 'tag bad' }, 'ещё не входил: сначала вход по ссылке')));
            });
            if (!rows.length) list.appendChild(h('p', { class: 'muted' }, 'Пока нет людей, кроме администраторов.'));
          }
          function bulk(on) { post('/api/lisa/allow-bulk', { user_ids: rows.map(function (p) { return p.user_id; }), allowed: on }).then(function (r) { toast('Сохранено' + (r.skipped.length ? ' (без ID пропущено: ' + r.skipped.length + ')' : '')); load(); }).catch(fail); }
          find.addEventListener('input', draw);
          ac.appendChild(h('div', { class: 'row mt6' }, h('div', { class: 'grow' }, find), cnt, h('button', { onclick: function () { bulk(true); } }, 'Отметить всех'), h('button', { onclick: function () { bulk(false); } }, 'Снять со всех')));
          ac.appendChild(list); recount(); draw();
        }
        pane.access.appendChild(ac);
        var featBoxes = d.features.map(function (f) { return check(f[1] + ' (по умолчанию для всех)', d.features_defaults[f[0]], function (on) { var o = {}; o[f[0]] = on; saveGlobal({ features_defaults: o }); }); });
        var gl = h('div', { class: 'card mt12' }, h('h2', null, 'Общие настройки'),
          check('Лиза использует поиск и погоду', d.tools_enabled, function (on) { saveGlobal({ tools_enabled: on }); }));
        featBoxes.forEach(function (b) { gl.appendChild(b); });
        gl.appendChild(h('h3', null, 'Инструкция Лизы')); gl.appendChild(prompt);
        gl.appendChild(h('h3', null, 'Город по умолчанию')); gl.appendChild(city);
        gl.appendChild(h('h3', null, 'Адрес поиска (SearXNG)')); gl.appendChild(search);
        gl.appendChild(h('h3', null, 'Интернет-поиск: фильтр взрослого содержимого')); gl.appendChild(sset.safesearch);
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
            limits: {
            per_user_per_day: Number(lim.per_user_per_day.value), global_per_day: Number(lim.global_per_day.value),
            max_output_tokens: Number(lim.max_output_tokens.value), max_history_messages: Number(lim.max_history_messages.value) } });
        } }, 'Сохранить общие настройки')));
        pane.settings.appendChild(gl);
        var ppl = h('details', { class: 'mt16', open: 'open' }, h('summary', null, 'Подробно по каждому: лимит, возможности и игры (' + d.people.length + ')')); pane.access.appendChild(ppl);
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

  // ---------- Игры ----------
  // Права на игры хранятся в настройках Лизы (их читает приложение): общие и по каждому человеку
  function viewGames(v) {
    v.appendChild(h('h1', null, 'Игры'));
    var root = h('div'); v.appendChild(root);
    function load() {
      get('/api/lisa').then(function (d) {
        root.textContent = '';
        if (!d.enabled) { root.appendChild(h('p', { class: 'muted' }, 'Файл настроек не подключён (DVADMIN_LISA_CONFIG): права на игры хранятся в нём.')); return; }
        var off = d.games_off_all.slice();
        var gc = h('div', { class: 'card mt12' }, h('h2', null, 'Какие игры включены для всех'), h('p', { class: 'muted small' }, 'Снятая игра пропадает у всех людей. Права отдельного человека задаются в таблице ниже.'));
        d.games.forEach(function (g) {
          var cb = h('input', { type: 'checkbox', checked: off.indexOf(g[0]) < 0 });
          cb.addEventListener('change', function () { off = off.filter(function (x) { return x !== g[0]; }); if (!cb.checked) off.push(g[0]); post('/api/lisa/global', { games_off_all: off }).then(function () { toast('Сохранено'); load(); }).catch(function (e) { fail(e); load(); }); });
          gc.appendChild(h('label', { class: 'permrow' }, cb, g[1]));
        });
        root.appendChild(gc);
        var mc = h('div', { class: 'card mt12' }, h('h2', null, 'Игры по людям'), h('p', { class: 'muted small' }, 'Флажок = игра доступна человеку. Серые клетки отключены для всех выше. Изменения применяются сразу.'));
        var tbl = h('table', { class: 'matrix' }), head = h('tr', null, h('th', null, 'Человек'));
        d.games.forEach(function (g) { head.appendChild(h('th', { class: 'c' }, g[1])); });
        head.appendChild(h('th', null, ''));
        tbl.appendChild(h('thead', null, head));
        var tb = h('tbody');
        d.people.forEach(function (p) {
          var offp = p.games_off.slice(), tr = h('tr', null, h('td', null, p.displayname || p.user_id)), cbs = [];
          function save() { post('/api/lisa/user', { user_id: p.user_id, games_off: offp }).then(function () { toast('Сохранено'); }).catch(function (e) { fail(e); load(); }); }
          d.games.forEach(function (g) {
            var glob = off.indexOf(g[0]) >= 0;
            var cb = h('input', { type: 'checkbox', checked: !glob && offp.indexOf(g[0]) < 0, disabled: glob }); cbs.push([g[0], cb]);
            cb.addEventListener('change', function () { offp = offp.filter(function (x) { return x !== g[0]; }); if (!cb.checked) offp.push(g[0]); save(); });
            tr.appendChild(h('td', { class: 'c' + (glob ? ' dim' : '') }, cb));
          });
          tr.appendChild(h('td', { class: 'act' }, menuButton([
            { label: 'Включить все игры', onclick: function () { offp = []; cbs.forEach(function (x) { if (!x[1].disabled) x[1].checked = true; }); save(); } },
            { label: 'Выключить все игры', onclick: function () { offp = d.games.map(function (g) { return g[0]; }); cbs.forEach(function (x) { x[1].checked = false; }); save(); } }])));
          tb.appendChild(tr);
        });
        tbl.appendChild(tb); mc.appendChild(h('div', { class: 'scroll' }, tbl)); root.appendChild(mc);
        var sc = h('div', { class: 'card mt12' }, h('h2', null, 'Статистика партий')), sb = h('div'); sc.appendChild(sb); root.appendChild(sc);
        gamesStatsView(sb).catch(fail);
      }).catch(fail);
    }
    load();
  }

  // ---------- Уведомления ----------
  function viewNotify(v) {
    v.appendChild(h('h1', null, 'Уведомления'));
    v.appendChild(h('div', { class: 'card mt12' }, h('h2', null, 'Как это устроено'),
      h('p', { class: 'muted' }, 'Телефон получает уведомление, когда сервер решает, что событие «громкое», и отправляет сигнал через шлюз уведомлений. Здесь видно, у кого уведомления подключены, и можно включать и выключать категории, которые различает сервер: личные чаты, группы, приглашения, @room, вход и выход участников. Что внутри зашифрованных чатов (реакции, прочтение, игры), сервер видеть не может: это выбирает сам человек в настройках приложения.')));
    var box = h('div', { class: 'card mt12' }, h('h2', null, 'Люди и устройства'));
    var out = h('div'), btn = h('button', { class: 'primary' }, 'Проверить всех');
    box.appendChild(h('p', { class: 'muted small' }, 'Каждому на несколько секунд делается временный вход, как при очистке комнат. Переписка не читается.'));
    box.appendChild(btn); box.appendChild(out); v.appendChild(box);
    var ruleSel = null;
    btn.addEventListener('click', function () {
      btn.disabled = true; btn.textContent = 'Проверяю…';
      post('/api/notify/overview').then(function (r) {
        out.textContent = '';
        var tb = h('tbody');
        r.people.forEach(function (p) {
          var on = p.rules ? p.rules.filter(function (x) { return x.notifies; }).length : 0;
          tb.appendChild(h('tr', { class: 'click', onclick: function () {
            var inner = h('div'); modal(h('div', null, h('h2', null, 'Уведомления: ' + p.label), inner, h('div', { class: 'row mt14' }, h('button', { onclick: closeModal }, 'Закрыть'))));
            post('/api/users/notify', { user_id: p.user_id }).then(function (x) { notifyView(inner, { user_id: p.user_id }, x); }).catch(fail);
          } },
            h('td', null, p.label),
            h('td', null, p.pushers == null ? h('span', { class: 'tag bad' }, 'не удалось') : (p.pushers.length ? h('span', { class: 'tag ok' }, 'подключено: ' + p.pushers.length) : h('span', { class: 'tag bad' }, 'не подключено'))),
            h('td', { class: 'muted' }, p.rules ? 'включено категорий: ' + on + ' из ' + p.rules.length : '—')));
        });
        if (!r.people.length) tb.appendChild(h('tr', null, h('td', { colspan: 3, class: 'muted' }, 'Людей пока нет.')));
        out.appendChild(h('table', null, h('thead', null, h('tr', null, h('th', null, 'Человек'), h('th', null, 'Устройства'), h('th', null, 'Категории'))), tb));
        out.appendChild(h('p', { class: 'muted small mt6' }, 'Нажмите на строку, чтобы открыть настройки человека.'));
        // Одна категория всем сразу
        ruleSel = h('select', null); r.rules.forEach(function (x) { ruleSel.appendChild(h('option', { value: x.id }, x.label)); });
        var mode = h('select', null, h('option', { value: '1' }, 'уведомлять'), h('option', { value: '0' }, 'не уведомлять'));
        out.appendChild(h('h3', null, 'Одна категория всем сразу'));
        out.appendChild(h('div', { class: 'row' }, h('div', { class: 'grow' }, ruleSel), mode, h('button', { class: 'danger', onclick: function () {
          confirmDanger('Изменить уведомления у всех?', 'Выбранная категория будет изменена у всех активных людей. Администратор не затрагивается. Позже каждый человек сможет поменять её сам в приложении.', 'всем',
            function (c) { return post('/api/notify/apply', { rule_id: ruleSel.value, notifies: mode.value === '1', confirm: c }).then(function (x) { toast('Изменено у людей: ' + x.changed + (x.failed ? ', не удалось: ' + x.failed : '')); }); }, 'Применить');
        } }, 'Применить всем…')));
      }).catch(fail).then(function () { btn.disabled = false; btn.textContent = 'Проверить заново'; });
    });
  }

  // ---------- Настройка ----------
  function viewSetup(v) {
    v.appendChild(h('h1', null, 'Настройка'));
    var checks = h('div', { class: 'card mt12' }, h('h2', null, 'Проверка сервера'));
    v.appendChild(checks);
    get('/api/setup/check').then(function (r) { r.checks.forEach(function (c) { checks.appendChild(h('p', null, h('span', { class: 'tag ' + (c.ok ? 'ok' : 'bad') }, c.ok ? 'ок' : 'проблема'), c.text)); }); }).catch(fail);

    var hs = h('input', { placeholder: 'chat.example.org' }), push = h('input', { placeholder: 'https://push.example.org (необязательно)', autocomplete: 'off' }), upd = h('input', { placeholder: 'https://updates.example.org/путь (необязательно)', autocomplete: 'off' });
    var out = h('pre', { class: 'hidden' }), info = h('p', { class: 'muted small' }), others = h('p', { class: 'muted small' });
    var revealBtn = h('button', { class: 'hidden' }, 'Показать адреса целиком');
    function fill(r) {
      hs.value = r.fields.homeserver; push.value = r.fields.pushGateway; upd.value = r.fields.updateUrl;
      info.textContent = r.exists ? 'Файл найден: ' + r.path + '. Значения подгружены из него.' : 'Файла ещё нет (' + r.path + '). Заполните поля и сохраните: файл будет создан.';
      others.textContent = r.others.length ? 'Другие строки файла (' + r.others.join(', ') + ') скрыты и при сохранении остаются как есть.' : '';
      revealBtn.classList.toggle('hidden', !r.exists || r.revealed);
    }
    function loadEnv(reveal) { return get('/api/setup/env' + (reveal ? '?reveal=1' : '')).then(fill).catch(function () {}); }
    revealBtn.addEventListener('click', function () { loadEnv(true).then(function () { toast('Адреса показаны полностью (запись в журнале)'); }); });
    loadEnv(false);
    function vals(save) { return { homeserver: hs.value, pushGateway: push.value, updateUrl: upd.value, save: save }; }
    v.appendChild(h('div', { class: 'card mt16' }, h('h2', null, 'Файл настроек сборки (dvchat.env)'),
      h('p', { class: 'muted' }, 'Панель показывает этот файл и меняет его: он единый для сборки приложения. Адреса с секретной частью скрыты точками; если их не трогать, при сохранении остаются прежними. Новый человек, развернувший свой DVChat, начинает с пустых полей.'),
      info, others,
      h('h3', null, 'Адрес вашего сервера Matrix'), hs, h('p', { class: 'muted small' }, 'Адрес, по которому приложение подключается к серверу. Попадает в сборку приложения (DVCHAT_HOMESERVER).'),
      h('h3', null, 'Шлюз уведомлений'), push, h('p', { class: 'muted small' }, 'Сюда сервер отправляет сигнал «пришло сообщение», а шлюз будит приложение на телефоне. Адрес вида 172.x.x.x, 192.168.x.x или имя контейнера, это внутренний адрес: он работает только внутри вашей сети или сети Docker на мини-ПК и снаружи недоступен. Если адрес изменится (например, у провайдера или после переустановки), укажите новый. Если поле пустое, push-уведомления не настроены (DVCHAT_PUSH_GATEWAY).'),
      h('h3', null, 'Канал обновлений'), upd, h('p', { class: 'muted small' }, 'Адрес, по которому приложение узнаёт о новых версиях. Оставьте пустым, если обновления вы раздаёте иначе (DVCHAT_UPDATE_URL).'),
      h('div', { class: 'row mt14' }, revealBtn,
        h('button', { onclick: function () { post('/api/setup/env', vals(false)).then(function (r) { out.textContent = r.text; out.classList.remove('hidden'); }).catch(fail); } }, 'Показать файл'),
        h('button', { class: 'primary', onclick: function () { post('/api/setup/env', vals(true)).then(function (r) { out.textContent = r.text; out.classList.remove('hidden'); toast('Сохранено: ' + r.path); loadEnv(false); }).catch(fail); } }, 'Сохранить файл')), out));
  }

  // ---------- Каркас ----------
  var views = { overview: viewOverview, people: viewPeople, groups: viewGroups, rooms: viewRooms, lisa: viewLisa, games: viewGames, notify: viewNotify, setup: viewSetup };
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
