// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: чат с Лизой: ответ потоком, голосовой ввод, история на телефоне.

import 'dart:async';

import 'package:dvchat/pages/liza/liza_client.dart';
import 'package:dvchat/pages/liza/liza_history.dart';
import 'package:dvchat/pages/liza/liza_markdown.dart';
import 'package:dvchat/pages/liza/liza_store.dart';
import 'package:dvchat/widgets/dv_live_wave.dart';
import 'package:flutter/rendering.dart' show RenderBox, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show Client;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class LizaChat extends StatefulWidget {
  final Client client;
  final LizaStatus status;
  const LizaChat({super.key, required this.client, required this.status});

  @override
  State<LizaChat> createState() => _LizaChatState();
}

class _LizaChatState extends State<LizaChat> {
  static const String _greeting =
      'Привет, я Лиза. Спрашивай меня, что хочешь: отвечу на вопрос, '
      'помогу с текстом, переведу или подскажу идею.';

  static const List<String> _examples = [
    'Что приготовить на ужин из курицы и риса?',
    'Объясни простыми словами, как работает интернет',
    'Помоги написать поздравление с днём рождения',
    'Переведи на английский: «Как пройти к вокзалу?»',
  ];

  late final LizaClient _api = LizaClient(widget.client);
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final SpeechToText _speech = SpeechToText();

  final List<LizaMessage> _messages = [];
  List<LizaConversation> _chats = [];
  LizaConversation _current = LizaConversation.fresh();
  bool _busy = false;
  String _partial = '';
  String? _error;
  int _used = 0;
  int? _limit;
  bool _speechReady = false;
  bool _listening = false;
  // Пользователь хочет диктовать (пока не нажал стоп или отправку): сеансы продлеваются сами
  bool _wantListen = false;
  bool _restarting = false;
  DateTime _dictStart = DateTime.now();
  String? _localeId;
  String _beforeSpeech = '';
  String _lastWords = '';
  final List<double> _levels = [];
  Timer? _waveTimer;
  double _level = 0;
  double _smooth = 0;
  String _prevFinal = '';
  bool _discardSpeech = false;
  int? _tokens;
  final GlobalKey _qKey = GlobalKey();
  final GlobalKey _listKey = GlobalKey();
  final ValueNotifier<bool> _showUp = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showDown = ValueNotifier<bool>(false);

  String get _userId => widget.client.userID ?? '';

  @override
  void initState() {
    super.initState();
    _used = widget.status.used;
    _limit = widget.status.admin ? null : widget.status.limit;
    _tokens = widget.status.tokens;
    _scroll.addListener(_updateButtons);
    _load();
  }

  @override
  void dispose() {
    _wantListen = false;
    _speech.cancel();
    _waveTimer?.cancel();
    _showUp.dispose();
    _showDown.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await LizaStore.loadAll(_userId);
    if (!mounted) return;
    setState(() {
      _chats = saved;
      if (saved.isNotEmpty) {
        _current = saved.first;
        _messages
          ..clear()
          ..addAll(_current.messages);
      }
    });
    _scrollToEnd(force: true);
  }

  /// Записывает текущий разговор в историю на телефоне
  Future<void> _save() async {
    if (_messages.isEmpty) return;
    final tail = _messages.length > LizaStore.maxMessages
        ? _messages.sublist(_messages.length - LizaStore.maxMessages)
        : List.of(_messages);
    _current
      ..messages = tail
      ..updated = DateTime.now().millisecondsSinceEpoch;
    if (_current.title.isEmpty) _current.title = LizaStore.titleOf(tail);
    if (!_chats.any((c) => c.id == _current.id)) _chats.insert(0, _current);
    await LizaStore.saveAll(_userId, _chats);
  }

  void _resetView(LizaConversation chat) {
    _current = chat;
    _messages
      ..clear()
      ..addAll(chat.messages);
    _partial = '';
    _error = null;
  }

  /// «+»: новый разговор, прошлый остаётся в истории
  void _newChat() {
    if (_busy || _messages.isEmpty) return;
    setState(() => _resetView(LizaConversation.fresh()));
    _updateButtons();
  }

  Future<void> _deleteChat(String id) async {
    _chats.removeWhere((c) => c.id == id);
    await LizaStore.saveAll(_userId, _chats);
    if (id == _current.id && mounted) {
      setState(() => _resetView(LizaConversation.fresh()));
    }
  }

  Future<void> _clearHistory() async {
    _chats.clear();
    await LizaStore.clear(_userId);
    if (mounted) setState(() => _resetView(LizaConversation.fresh()));
  }

  Future<void> _openHistory() async {
    if (_busy) return;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => LizaHistoryPage(
          chats: _chats,
          currentId: _current.id,
          onDelete: _deleteChat,
          onClear: _clearHistory,
        ),
      ),
    );
    if (id == null || !mounted) return;
    final chat = _chats.where((c) => c.id == id).firstOrNull;
    if (chat == null) return;
    setState(() => _resetView(chat));
    _scrollToEnd(force: true);
  }

  void _openInfo() =>
      showLizaInfo(context, used: _used, limit: _limit, tokens: _tokens);

  String _usageLine() {
    final first = _limit == null
        ? 'Сегодня запросов: $_used'
        : 'Сегодня: $_used из $_limit запросов';
    final t = _tokens;
    return t == null ? first : '$first · ${lizaSpaced(t)} токенов';
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToEnd({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (force || pos.maxScrollExtent - pos.pixels < 240) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  /// Верх вопроса относительно списка (null, если вопрос сейчас не нарисован)
  double? _questionTop() {
    final q = _qKey.currentContext?.findRenderObject();
    final l = _listKey.currentContext?.findRenderObject();
    if (q is RenderBox && l is RenderBox && q.attached && l.attached) {
      return q.localToGlobal(Offset.zero, ancestor: l).dy;
    }
    return null;
  }

  /// Вопрос ставим к верхнему краю, ответ растёт под ним, как в ChatGPT
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.userScrollDirection != ScrollDirection.idle) return;
      final top = _questionTop();
      var target = pos.maxScrollExtent;
      if (top != null) {
        if (top <= 8) {
          _updateButtons();
          return;
        }
        target = (pos.pixels + top - 8)
            .clamp(0.0, pos.maxScrollExtent)
            .toDouble();
      }
      _scroll.jumpTo(target);
      _updateButtons();
    });
  }

  void _updateButtons() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _showDown.value = pos.maxScrollExtent - pos.pixels > 160;
    var up = false;
    if (_messages.any((m) => m.isUser)) {
      final top = _questionTop();
      up = top == null ? pos.pixels > 0 : top < -20;
    }
    _showUp.value = up;
  }

  Future<void> _toQuestion() async {
    for (var i = 0; i < 40; i++) {
      final ctx = _qKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      _scroll.jumpTo(
        (pos.pixels - pos.viewportDimension * 0.8)
            .clamp(0.0, pos.maxScrollExtent)
            .toDouble(),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _toEnd() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ---------- отправка ----------

  Future<void> _send() => _sendText(_input.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    // Диктовку обрываем и запоздалые слова от неё отбрасываем, поле очищаем
    _discardSpeech = true;
    _wantListen = false;
    _beforeSpeech = '';
    _lastWords = '';
    try {
      await _speech.cancel();
    } catch (_) {}
    _listening = false;
    _input.clear();
    setState(() => _messages.add(LizaMessage(text: text, isUser: true)));
    await _save();
    await _ask();
  }

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _partial = '';
      _error = null;
    });
    _follow();
    final buffer = StringBuffer();
    String? error;
    var done = false;
    await for (final chunk in _api.chat(List.of(_messages))) {
      if (!mounted) return;
      if (chunk.delta != null) {
        buffer.write(chunk.delta);
        setState(() => _partial = buffer.toString());
        _follow();
      } else if (chunk.done) {
        done = true;
        final used = chunk.used;
        if (used != null) _used = used;
        final tok = chunk.tokens;
        if (tok != null) _tokens = tok;
        if (!widget.status.admin) _limit = chunk.limit ?? _limit;
      } else if (chunk.error != null) {
        error = chunk.error;
      }
    }
    if (!mounted) return;
    final text = buffer.toString().trim();
    setState(() {
      if (text.isNotEmpty) {
        _messages.add(LizaMessage(text: text, isUser: false));
      }
      _partial = '';
      _busy = false;
      if (done) {
        _error = null;
      } else if (error != null) {
        _error = error;
      } else if (text.isEmpty) {
        _error = 'Сеть сейчас перегружена. Попробуйте позже.';
      }
    });
    _updateButtons();
    if (text.isNotEmpty) await _save();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Скопировано');
  }

  // ---------- голос ----------

  Future<bool> _ensureSpeech() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
    } catch (_) {
      _speechReady = false;
    }
    return _speechReady;
  }

  void _onSpeechStatus(String status) {
    if (status != 'done' && status != 'notListening') return;
    if (!mounted) return;
    if (_wantListen && !_discardSpeech) {
      _restartSoon();
    } else if (_listening) {
      setState(() => _listening = false);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    final benign =
        error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout' ||
        error.errorMsg == 'error_client';
    if (_wantListen && !_discardSpeech && benign) {
      _restartSoon();
      return;
    }
    _wantListen = false;
    setState(() => _listening = false);
    if (benign) return;
    _toast('Не получилось распознать речь. Можно продиктовать с клавиатуры.');
  }

  /// Распознаватель Android сам заканчивает сеанс на паузе или через минуту-другую.
  /// Пока человек не нажал стоп, запускаем следующий сеанс: текст в поле копится.
  void _restartSoon() {
    if (_restarting) return;
    _restarting = true;
    Future<void>.delayed(const Duration(milliseconds: 250), () async {
      _restarting = false;
      if (!_wantListen || !mounted || _discardSpeech) return;
      if (DateTime.now().difference(_dictStart) > const Duration(minutes: 10)) {
        await _stopDictation();
        _toast('Диктовка остановлена: длиннее 10 минут за раз нельзя.');
        return;
      }
      await _listenOnce();
    });
  }

  Future<void> _stopDictation() async {
    _wantListen = false;
    try {
      await _speech.stop();
    } catch (_) {}
    if (mounted) setState(() => _listening = false);
  }

  Future<void> _toggleListening() async {
    if (_listening || _wantListen) {
      await _stopDictation();
      return;
    }
    if (!await _ensureSpeech()) {
      _toast(
        'Голосовой ввод тут недоступен. Нажмите на строку ввода и '
        'продиктуйте значком микрофона на клавиатуре.',
      );
      return;
    }
    try {
      final locales = await _speech.locales();
      _localeId = locales
          .where((l) => l.localeId.toLowerCase().startsWith('ru'))
          .firstOrNull
          ?.localeId;
    } catch (_) {}
    _levels.clear();
    _discardSpeech = false;
    _level = 0;
    _smooth = 0;
    if (!mounted) return;
    _wantListen = true;
    _dictStart = DateTime.now();
    setState(() => _listening = true);
    _startWave();
    await _listenOnce();
  }

  /// Один сеанс распознавания: что уже стоит в поле, остаётся, новые слова дописываются
  Future<void> _listenOnce() async {
    _beforeSpeech = _input.text.trim().isEmpty
        ? ''
        : '${_input.text.trimRight()} ';
    _lastWords = '';
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        onSoundLevelChange: _onSoundLevel,
        localeId: _localeId,
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 10),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      await _stopDictation();
    }
  }

  /// Громкость 1..100 раз в 100 мс, как в записи голосовых сообщений: DvLiveWave
  /// сама плавно выдвигает новую палочку справа и перерисовывается каждый кадр.
  void _startWave() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!_listening || !mounted) {
        t.cancel();
        return;
      }
      _smooth += (_level - _smooth) * 0.5;
      _levels.add(1 + _smooth * 99);
    });
  }

  void _onSoundLevel(double level) {
    _level = ((level + 2) / 12).clamp(0.0, 1.0).toDouble();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (_discardSpeech) return;
    // Переводы строк и лишние пробелы из распознанного убираем: поле не должно расти
    final words = result.recognizedWords.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Распознаватель иногда присылает заново результат прошлой диктовки: пропускаем
    if (_lastWords.isEmpty &&
        words.isNotEmpty &&
        words.toLowerCase() == _prevFinal.toLowerCase()) {
      return;
    }
    // На паузе распознаватель начинает новую фразу, и слова обнуляются.
    // Тогда прошлую фразу оставляем в поле, а новую дописываем после неё.
    if (_lastWords.isNotEmpty &&
        words.isNotEmpty &&
        !_sameUtterance(_lastWords, words)) {
      _beforeSpeech = '$_beforeSpeech$_lastWords ';
    }
    // Страховка: если новое слово обрезало бы то, что уже стоит в поле, не затираем,
    // а оставляем прошлое и дописываем новое после него
    if (_lastWords.isNotEmpty &&
        words.isNotEmpty &&
        _beforeSpeech.length + words.length + 12 <
            _input.text.trimRight().length) {
      if (!_beforeSpeech.endsWith(_lastWords)) {
        _beforeSpeech = '$_beforeSpeech$_lastWords ';
      }
    }
    _lastWords = words;
    final text = '$_beforeSpeech$words';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (result.finalResult) {
      if (words.isNotEmpty) {
        _beforeSpeech = '$_beforeSpeech$words ';
        _prevFinal = words;
      }
      _lastWords = '';
      if (!_wantListen && mounted) setState(() => _listening = false);
    }
  }

  /// Слова без знаков препинания и регистра: Android то ставит запятые, то нет
  String _norm(String t) =>
      t.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]+'), ' ').trim();

  /// Новые слова продолжают (или слегка уточняют) прошлые, а не начинают другую фразу.
  /// Совпадение только по первому слову больше не считается: из-за него терялся текст.
  bool _sameUtterance(String prev, String next) {
    final a = _norm(prev).split(' ');
    final b = _norm(next).split(' ');
    if (a.isEmpty || b.isEmpty || a.first.isEmpty || b.first.isEmpty)
      return true;
    var common = 0;
    while (common < a.length && common < b.length && a[common] == b[common]) {
      common++;
    }
    if (common == a.length) return true; // новое продолжает старое целиком
    // небольшое уточнение уже сказанного: совпала почти вся короткая из двух фраз
    final shorter = a.length < b.length ? a.length : b.length;
    return common >= 2 && common >= shorter * 0.7;
  }

  // ---------- внешний вид ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'История',
          icon: const Icon(Icons.history),
          onPressed: _busy ? null : _openHistory,
        ),
        centerTitle: true,
        title: const Text('Лиза'),
        actions: [
          IconButton(
            tooltip: 'О Лизе',
            icon: const Icon(Icons.info_outline),
            onPressed: _openInfo,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _plusButton(Theme.of(context)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList(context)),
          if (_error != null) _buildError(context),
          _buildInput(context),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final lastUser = _messages.lastIndexWhere((m) => m.isUser);
    return Stack(
      children: [
        ListView.builder(
          key: _listKey,
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          itemCount: 1 + _messages.length + (_busy ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == 0) return _welcome(context);
            final index = i - 1;
            if (index < _messages.length) {
              final m = _messages[index];
              if (m.isUser) {
                final bubble = _userBubble(context, m.text);
                return index == lastUser
                    ? KeyedSubtree(key: _qKey, child: bubble)
                    : bubble;
              }
              return _lisaBubble(context, m.text);
            }
            return _lisaBubble(context, _partial, typing: true);
          },
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _jumpButton(
                _showUp,
                Icons.keyboard_arrow_up,
                'К моему вопросу',
                _toQuestion,
              ),
              _jumpButton(_showDown, Icons.keyboard_arrow_down, 'Вниз', _toEnd),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jumpButton(
    ValueNotifier<bool> visible,
    IconData icon,
    String tip,
    VoidCallback onTap,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, show, _) => show
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IconButton.filledTonal(
                tooltip: tip,
                icon: Icon(icon),
                onPressed: onTap,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _welcome(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lisaBubble(context, _greeting, copyable: false),
        if (_messages.isEmpty && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _examples)
                  ActionChip(label: Text(e), onPressed: () => _sendText(e)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _userBubble(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _lisaBubble(
    BuildContext context,
    String text, {
    bool typing = false,
    bool copyable = true,
  }) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isEmpty && typing)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              LizaMarkdown(
                data: typing ? '$text ▍' : text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            if (!typing && copyable)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Копировать',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(text),
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _error ?? '',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _ask,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_listening)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Говорите… нажмите на микрофон, когда закончите: текст появится в поле',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else if (_limit != null || _tokens != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _usageLine(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _micButton(theme),
                const SizedBox(width: 8),
                Expanded(
                  child: _listening
                      ? Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: DvLiveWave(
                            samples: _levels,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: 'Спросите Лизу…',
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Стрелка отправки всегда на одном месте справа, пока пусто или Лиза думает: серая
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, _) {
                    final canSend = value.text.trim().isNotEmpty && !_busy;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: IconButton.filled(
                        onPressed: canSend ? _send : null,
                        tooltip: 'Отправить',
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// «+»: кружок того же цвета, что микрофон; пока нечего начинать заново, серый
  Widget _plusButton(ThemeData theme) {
    final enabled = !_busy && _messages.isNotEmpty;
    final background = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.12);
    final foreground = enabled
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      label: 'Новый разговор',
      child: GestureDetector(
        onTap: enabled ? _newChat : null,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(Icons.add, size: 24, color: foreground),
        ),
      ),
    );
  }

  Widget _micButton(ThemeData theme) {
    final active = _listening;
    final color = active ? theme.colorScheme.error : theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: active ? 'Остановить запись' : 'Голосовой ввод',
      child: GestureDetector(
        onTap: _busy ? null : _toggleListening,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            active ? Icons.stop : Icons.mic,
            size: 28,
            color: active
                ? theme.colorScheme.onError
                : theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
