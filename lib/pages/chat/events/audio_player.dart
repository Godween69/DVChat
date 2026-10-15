// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Проигрыватель голосовых сообщений и аудиофайлов внутри чата.

import 'dart:async';
import 'dart:io';

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/config/themes.dart';
import 'package:dvchat/utils/dv_voice_chain.dart';
import 'package:dvchat/utils/error_reporter.dart';
import 'package:dvchat/utils/file_description.dart';
import 'package:dvchat/utils/localized_exception_extension.dart';
import 'package:dvchat/utils/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

import '../../../utils/matrix_sdk_extensions/event_extension.dart';
import '../../../widgets/dvchat_app.dart';
import '../../../widgets/matrix.dart';

class AudioPlayerWidget extends StatefulWidget {
  final Color color;
  final Color linkColor;
  final double fontSize;
  final Event event;

  /// Лента чата: по ней находим следующее голосовое для автовоспроизведения
  final Timeline? timeline;

  static const int wavesCount = 40;

  const AudioPlayerWidget(
    this.event, {
    required this.color,
    required this.linkColor,
    required this.fontSize,
    this.timeline,
    super.key,
  });

  /// Есть подпись под голосовым: тогда метка времени получает свою строку
  bool get hasCaption => event.fileDescription != null;

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

enum AudioPlayerStatus { notDownloaded, downloading, downloaded }

class AudioPlayerState extends State<AudioPlayerWidget>
    with SingleTickerProviderStateMixin {
  static const double buttonSize = 44;

  AudioPlayerStatus status = AudioPlayerStatus.notDownloaded;
  double? _downloadProgress;

  late final MatrixState matrix;
  List<int>? _waveform;
  String? _durationString;

  // DVChat: плавная шкала. Положение читается каждый кадр (just_audio сам досчитывает его
  // между обновлениями), поэтому закраска идёт без рывков и без перестройки виджетов.
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final ValueNotifier<int> _seconds = ValueNotifier(0);
  final ValueNotifier<double?> _drag = ValueNotifier(null);

  AudioPlayer? get _player =>
      matrix.voiceMessageEventId.value == widget.event.eventId
      ? matrix.audioPlayer
      : null;

  void _publish(AudioPlayer p) {
    final d = p.duration?.inMilliseconds ?? 0;
    final pos = p.position.inMilliseconds;
    _progress.value = d <= 0 ? 0.0 : (pos / d).clamp(0.0, 1.0);
    final s = pos ~/ 1000;
    if (_seconds.value != s) _seconds.value = s;
  }

  void _onTick(Duration _) {
    final p = _player;
    if (p == null) {
      _ticker.stop();
      return;
    }
    _publish(p);
    if (!p.playing || p.processingState == ProcessingState.completed) {
      _ticker.stop();
    }
  }

  void _kick(AudioPlayer p) {
    _publish(p);
    if (p.playing &&
        p.processingState != ProcessingState.completed &&
        !_ticker.isActive) {
      _ticker.start();
    }
  }

  Future<void> _seekTo(AudioPlayer? p, double fraction) async {
    if (p == null) {
      await _onButtonTap();
      return;
    }
    final d = p.duration?.inMilliseconds ?? 0;
    if (d <= 0) return;
    _progress.value = fraction;
    await p.seek(Duration(milliseconds: (fraction * d).round()));
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    _seconds.dispose();
    _drag.dispose();
    super.dispose();
    final audioPlayer = matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (audioPlayer != null) {
      if (audioPlayer.playing && !audioPlayer.isAtEndPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(matrix.context).showMaterialBanner(
            MaterialBanner(
              padding: EdgeInsets.zero,
              leading: StreamBuilder(
                stream: audioPlayer.playerStateStream.asBroadcastStream(),
                builder: (context, _) => IconButton(
                  onPressed: () {
                    if (audioPlayer.isAtEndPosition) {
                      audioPlayer.seek(Duration.zero);
                    } else if (audioPlayer.playing) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play();
                    }
                  },
                  icon: audioPlayer.playing && !audioPlayer.isAtEndPosition
                      ? const Icon(Icons.pause_outlined)
                      : const Icon(Icons.play_arrow_outlined),
                ),
              ),
              content: StreamBuilder(
                stream: audioPlayer.positionStream.asBroadcastStream(),
                builder: (context, _) => GestureDetector(
                  onTap: () => DvChatApp.router.go(
                    '/rooms/${widget.event.room.id}?event=${widget.event.eventId}',
                  ),
                  child: Text(
                    '🎙️ ${audioPlayer.position.minuteSecondString} / ${audioPlayer.duration?.minuteSecondString} - ${widget.event.senderFromMemoryOrFallback.calcDisplayname()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    audioPlayer.pause();
                    audioPlayer.dispose();
                    matrix.voiceMessageEventId.value = matrix.audioPlayer =
                        null;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(
                        matrix.context,
                      ).clearMaterialBanners();
                    });
                  },
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
          );
        });
        return;
      }
      audioPlayer.pause();
      audioPlayer.dispose();
      matrix.voiceMessageEventId.value = matrix.audioPlayer = null;
    }
  }

  Future<void> _onButtonTap() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
    });
    final currentPlayer =
        matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (currentPlayer != null && !currentPlayer.isAtEndPosition) {
      if (currentPlayer.playing) {
        currentPlayer.pause();
      } else {
        currentPlayer.play();
      }
      return;
    }

    matrix.voiceMessageEventId.value = widget.event.eventId;
    matrix.audioPlayer
      ?..stop()
      ..dispose();
    File? file;
    MatrixFile? matrixFile;

    setState(() => status = AudioPlayerStatus.downloading);
    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      matrixFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              }
            : null,
      );

      final attachmentUrl = widget.event.attachmentOrThumbnailMxcUrl();

      if (!kIsWeb && attachmentUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(attachmentUrl.pathSegments.last);
        file = File('${tempDir.path}/${fileName}_${matrixFile.name}');

        await file.writeAsBytes(matrixFile.bytes);
      }

      setState(() {
        status = AudioPlayerStatus.downloaded;
      });
    } catch (e, s) {
      Logs().v('Could not download audio file', e, s);
      if (!mounted) rethrow;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      rethrow;
    }
    if (!context.mounted) return;
    if (matrix.voiceMessageEventId.value != widget.event.eventId) return;

    final audioPlayer = matrix.audioPlayer = AudioPlayer();

    if (file != null) {
      audioPlayer.setFilePath(file.path);
    } else {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(matrixFile.bytes, mimeType: matrixFile.mimeType),
        ),
      );
    }
    if (!mounted) return;

    // DVChat: скорость воспроизведения запоминается между сообщениями
    await audioPlayer.setSpeed(
      AppSettings.voiceMessageSpeedPercent.value / 100,
    );
    if (!mounted) return;

    // DVChat: после этого сообщения само включится следующее голосовое
    final chainTimeline = widget.timeline;
    if (chainTimeline != null) {
      DvVoiceChain.attach(matrix, audioPlayer, widget.event, chainTimeline);
    }

    audioPlayer.play().onError(
      ErrorReporter(context, 'Unable to play audio message').onErrorCallback,
    );
  }

  Future<void> _toggleSpeed() async {
    final audioPlayer = matrix.audioPlayer;
    if (audioPlayer == null) return;
    switch (audioPlayer.speed) {
      case 1.0:
        await audioPlayer.setSpeed(1.25);
        break;
      case 1.25:
        await audioPlayer.setSpeed(1.5);
        break;
      case 1.5:
        await audioPlayer.setSpeed(2.0);
        break;
      case 2.0:
        await audioPlayer.setSpeed(0.5);
        break;
      case 0.5:
      default:
        await audioPlayer.setSpeed(1.0);
        break;
    }
    // DVChat: выбранную скорость сохраняем для всех следующих сообщений
    await AppSettings.voiceMessageSpeedPercent.setItem(
      (audioPlayer.speed * 100).round(),
    );
    setState(() {});
  }

  List<int>? _getWaveform() {
    final eventWaveForm = widget.event.content
        .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
        ?.tryGetList<int>('waveform');
    if (eventWaveForm == null || eventWaveForm.isEmpty) {
      return null;
    }
    // Newer versions of this MSC define 256 as the maximum instead of 1024.
    // Hard to determine which version we should follow. At the time of writing
    // this, Element X still sends 1024 while Mautrix WhatsApp uses 256.
    // https://github.com/matrix-org/matrix-spec-proposals/blob/travis/msc/audio-waveform/proposals/3246-audio-waveform.md#unstable-prefix
    if (!eventWaveForm.any((value) => value > 256)) {
      _maxWaveForm = 256;
    }

    while (eventWaveForm.length < AudioPlayerWidget.wavesCount) {
      for (var i = 0; i < eventWaveForm.length; i = i + 2) {
        eventWaveForm.insert(i, eventWaveForm[i]);
      }
    }
    var i = 0;
    final step = (eventWaveForm.length / AudioPlayerWidget.wavesCount).round();
    while (eventWaveForm.length > AudioPlayerWidget.wavesCount) {
      eventWaveForm.removeAt(i);
      i = (i + step) % AudioPlayerWidget.wavesCount;
    }
    return eventWaveForm
        .map((i) => i > _maxWaveForm ? _maxWaveForm : i)
        .toList();
  }

  int _maxWaveForm = 1024;

  @override
  void initState() {
    super.initState();
    matrix = Matrix.of(context);
    _waveform = _getWaveform();

    if (matrix.voiceMessageEventId.value == widget.event.eventId &&
        matrix.audioPlayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
      });
    }

    final durationInt = widget.event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('duration');
    if (durationInt != null) {
      final duration = Duration(milliseconds: durationInt);
      _durationString = duration.minuteSecondString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final waveform = _waveform;
    // Высоты палочек 0..1; без готовой формы звука рисуем ровную шкалу
    final bars = <double>[
      for (var i = 0; i < AudioPlayerWidget.wavesCount; i++)
        waveform == null ? 0.3 : (waveform[i] / _maxWaveForm).clamp(0.12, 1.0),
    ];

    return ValueListenableBuilder(
      valueListenable: matrix.voiceMessageEventId,
      builder: (context, eventId, _) {
        final audioPlayer = eventId != widget.event.eventId
            ? null
            : matrix.audioPlayer;
        final fileDescription = widget.event.fileDescription;

        return StreamBuilder<PlayerState>(
          stream: audioPlayer?.playerStateStream,
          builder: (context, _) {
            if (audioPlayer != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _kick(audioPlayer);
              });
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: DvThemes.columnWidth,
                    ),
                    child: Row(
                      mainAxisSize: .min,
                      children: <Widget>[
                        SizedBox(
                          width: buttonSize,
                          height: buttonSize,
                          child: status == AudioPlayerStatus.downloading
                              ? CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: widget.color,
                                  value: _downloadProgress,
                                )
                              : InkWell(
                                  borderRadius: BorderRadius.circular(64),
                                  onLongPress: () =>
                                      widget.event.saveFile(context),
                                  onTap: _onButtonTap,
                                  child: Material(
                                    color: widget.color.withAlpha(64),
                                    borderRadius: BorderRadius.circular(64),
                                    child: Icon(
                                      audioPlayer?.playing == true &&
                                              audioPlayer?.isAtEndPosition ==
                                                  false
                                          ? Icons.pause_outlined
                                          : Icons.play_arrow_outlined,
                                      color: widget.color,
                                      size: 28,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.maxWidth;
                                  double fraction(double dx) =>
                                      (dx / width).clamp(0.0, 1.0);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (d) => _seekTo(
                                      audioPlayer,
                                      fraction(d.localPosition.dx),
                                    ),
                                    onHorizontalDragStart: (d) => _drag.value =
                                        fraction(d.localPosition.dx),
                                    onHorizontalDragUpdate: (d) => _drag.value =
                                        fraction(d.localPosition.dx),
                                    onHorizontalDragCancel: () =>
                                        _drag.value = null,
                                    onHorizontalDragEnd: (_) {
                                      final f = _drag.value;
                                      _drag.value = null;
                                      if (f != null) _seekTo(audioPlayer, f);
                                    },
                                    child: SizedBox(
                                      width: width,
                                      height: 32,
                                      child: CustomPaint(
                                        painter: _WavePainter(
                                          bars: bars,
                                          progress: _progress,
                                          drag: _drag,
                                          color: widget.color,
                                          zero: audioPlayer == null,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // DVChat: время под шкалой, у левого края
                              ValueListenableBuilder<int>(
                                valueListenable: _seconds,
                                builder: (context, seconds, _) => Text(
                                  audioPlayer == null
                                      ? _durationString ?? '00:00'
                                      : _clock(seconds),
                                  style: TextStyle(
                                    color: widget.color,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: AnimatedCrossFade(
                            firstChild: Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Icon(
                                Icons.mic_none_outlined,
                                color: widget.color,
                              ),
                            ),
                            secondChild: Material(
                              color: widget.color.withAlpha(64),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius,
                                ),
                                onTap: _toggleSpeed,
                                child: SizedBox(
                                  width: 44,
                                  height: 28,
                                  child: Center(
                                    child: Text(
                                      '${audioPlayer?.speed}x',
                                      style: TextStyle(
                                        color: widget.color,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            crossFadeState: audioPlayer == null
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            duration: DvThemes.animationDuration,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fileDescription != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Linkify(
                        text: fileDescription,
                        textScaleFactor: MediaQuery.textScalerOf(
                          context,
                        ).scale(1),
                        style: TextStyle(
                          color: widget.color,
                          fontSize: widget.fontSize,
                        ),
                        options: const LinkifyOptions(humanize: false),
                        linkStyle: TextStyle(
                          color: widget.linkColor,
                          fontSize: widget.fontSize,
                          decoration: TextDecoration.underline,
                          decorationColor: widget.linkColor,
                        ),
                        onOpen: (url) =>
                            UrlLauncher(context, url.url).launchUrl(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Шкала голосового: толстые скруглённые палочки, как при записи. Их число зависит от
/// ширины; пройденная часть закрашивается плавно, без скачков по одной палочке.
class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.bars,
    required this.progress,
    required this.drag,
    required this.color,
    required this.zero,
  }) : super(repaint: Listenable.merge([progress, drag]));

  final List<double> bars;
  final ValueListenable<double> progress;
  final ValueListenable<double?> drag;
  final Color color;
  final bool zero;

  static const double _barWidth = 5;
  static const double _minStep = 9;

  /// Высота палочки i из n: самое громкое из исходных значений, попавших в неё
  double _peak(int i, int n) {
    final src = bars.length;
    final from = i * src ~/ n;
    var to = (i + 1) * src ~/ n;
    if (to <= from) to = from + 1;
    var peak = 0.0;
    for (var k = from; k < to && k < src; k++) {
      if (bars[k] > peak) peak = bars[k];
    }
    return peak;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = size.width ~/ _minStep;
    if (n < 1) return;
    final step = size.width / n;
    final p = zero ? 0.0 : (drag.value ?? progress.value);
    final idle = Paint()..color = color.withAlpha(100);
    final done = Paint()..color = color;

    void draw(Paint paint) {
      for (var i = 0; i < n; i++) {
        final h = (size.height * _peak(i, n)).clamp(5.0, size.height);
        final x = i * step + (step - _barWidth) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, (size.height - h) / 2, _barWidth, h),
            const Radius.circular(_barWidth / 2),
          ),
          paint,
        );
      }
    }

    draw(idle);
    if (p > 0) {
      canvas
        ..save()
        ..clipRect(Rect.fromLTWH(0, 0, size.width * p, size.height));
      draw(done);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color || old.zero != zero || !listEquals(old.bars, bars);
}

extension on AudioPlayer {
  bool get isAtEndPosition {
    final duration = this.duration;
    if (duration == null) return true;
    return position >= duration;
  }
}

extension on Duration {
  String get minuteSecondString =>
      '${inMinutes.toString().padLeft(2, '0')}:${(inSeconds % 60).toString().padLeft(2, '0')}';
}
