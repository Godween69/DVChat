// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: чат с Лизой: ответ потоком, голосовой ввод, история на телефоне.

import 'package:dvchat/pages/liza/liza_client.dart';
import 'package:dvchat/pages/liza/liza_markdown.dart';
import 'package:dvchat/pages/liza/liza_store.dart';
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
  bool _busy = false;
  String _partial = '';
  String? _error;
  int _used = 0;
  int? _limit;
  bool _speechReady = false;
  bool _listening = false;
  String _beforeSpeech = '';
  String _lastWords = '';

  String get _userId => widget.client.userID ?? '';

  @override
  void initState() {
    super.initState();
    _used = widget.status.used;
    _limit = widget.status.admin ? null : widget.status.limit;
    _load();
  }

  @override
  void dispose() {
    _speech.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await LizaStore.load(_userId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(saved);
    });
    _scrollToEnd(force: true);
  }

  Future<void> _save() => LizaStore.save(_userId, _messages);

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

  // ---------- отправка ----------

  Future<void> _send() => _sendText(_input.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    if (_listening) {
      await _speech.stop();
      _listening = false;
    }
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
    _scrollToEnd(force: true);
    final buffer = StringBuffer();
    String? error;
    var done = false;
    await for (final chunk in _api.chat(List.of(_messages))) {
      if (!mounted) return;
      if (chunk.delta != null) {
        buffer.write(chunk.delta);
        setState(() => _partial = buffer.toString());
        _scrollToEnd();
      } else if (chunk.done) {
        done = true;
        final used = chunk.used;
        if (used != null) _used = used;
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
    _scrollToEnd(force: true);
    if (text.isNotEmpty) await _save();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('Скопировано');
  }

  Future<void> _confirmNew() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый разговор?'),
        content: const Text(
          'Переписка с Лизой на этом телефоне будет удалена.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Начать заново'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _messages.clear();
      _partial = '';
      _error = null;
    });
    await LizaStore.clear(_userId);
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
    if ((status == 'done' || status == 'notListening') &&
        mounted &&
        _listening) {
      setState(() => _listening = false);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (mounted) setState(() => _listening = false);
    if (error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout') {
      return;
    }
    _toast('Не получилось распознать речь. Можно продиктовать с клавиатуры.');
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!await _ensureSpeech()) {
      _toast(
        'Голосовой ввод тут недоступен. Нажмите на строку ввода и '
        'продиктуйте значком микрофона на клавиатуре.',
      );
      return;
    }
    String? localeId;
    try {
      final locales = await _speech.locales();
      localeId = locales
          .where((l) => l.localeId.toLowerCase().startsWith('ru'))
          .firstOrNull
          ?.localeId;
    } catch (_) {}
    _beforeSpeech = _input.text.trim().isEmpty
        ? ''
        : '${_input.text.trimRight()} ';
    _lastWords = '';
    if (!mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: _onSpeechResult,
      localeId: localeId,
      listenFor: const Duration(seconds: 90),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    // Переводы строк и лишние пробелы из распознанного убираем: поле не должно расти
    final words = result.recognizedWords.replaceAll(RegExp(r'\s+'), ' ').trim();
    // На паузе распознаватель начинает новую фразу, и слова обнуляются.
    // Тогда прошлую фразу оставляем в поле, а новую дописываем после неё.
    if (_lastWords.isNotEmpty &&
        words.isNotEmpty &&
        !_sameUtterance(_lastWords, words)) {
      _beforeSpeech = '$_beforeSpeech$_lastWords ';
    }
    _lastWords = words;
    final text = '$_beforeSpeech$words';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (result.finalResult) {
      if (words.isNotEmpty) _beforeSpeech = '$_beforeSpeech$words ';
      _lastWords = '';
      if (mounted) setState(() => _listening = false);
    }
  }

  /// Новые слова продолжают (или уточняют) прошлые, а не начинают другую фразу
  bool _sameUtterance(String prev, String next) {
    final a = prev.toLowerCase();
    final b = next.toLowerCase();
    if (b.startsWith(a) || a.startsWith(b)) return true;
    return a.split(' ').first == b.split(' ').first;
  }

  // ---------- внешний вид ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Лиза'),
        actions: [
          IconButton(
            tooltip: 'Новый разговор',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _busy ? null : _confirmNew,
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
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: 1 + _messages.length + (_busy ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) return _welcome(context);
        final index = i - 1;
        if (index < _messages.length) {
          final m = _messages[index];
          return m.isUser
              ? _userBubble(context, m.text)
              : _lisaBubble(context, m.text);
        }
        return _lisaBubble(context, _partial, typing: true);
      },
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
                  'Говорите… нажмите на микрофон, когда закончите',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else if (_limit != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Сегодня: $_used из $_limit запросов',
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
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Спросите Лизу…',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
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
