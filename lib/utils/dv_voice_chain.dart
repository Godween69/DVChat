// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подряд идущие голосовые сообщения (свои и чужие) проигрываются одно за другим.
// Цепочка рвётся на первом сообщении, которое не голосовое, и когда голосовые кончились.
// Пауза, закрытие плашки и запуск другого сообщения цепочку не продолжают.

import 'dart:async';
import 'dart:io';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

abstract class DvVoiceChain {
  static StreamSubscription<PlayerState>? _sub;

  static bool isVoice(Event e) =>
      !e.redacted &&
      e.messageType == MessageTypes.Audio &&
      e.content.containsKey('org.matrix.msc3245.voice');

  /// Запоминает, какое сообщение играет; когда оно доиграет, включится следующее голосовое
  static void attach(
    MatrixState matrix,
    AudioPlayer player,
    Event event,
    Timeline timeline,
  ) {
    unawaited(_sub?.cancel());
    _sub = null;
    if (!isVoice(event)) return;
    _sub = player.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) return;
      unawaited(_sub?.cancel());
      _sub = null;
      // Пока играло, человек мог включить что-то другое
      if (!identical(matrix.audioPlayer, player)) return;
      final next = _nextVoice(timeline, event);
      if (next != null) unawaited(_play(matrix, next, timeline, player));
    });
  }

  static Event? _nextVoice(Timeline timeline, Event current) {
    final events = timeline.events.filterByVisibleInGui();
    final i = events.indexWhere((e) => e.eventId == current.eventId);
    if (i <= 0) return null;
    final next = events[i - 1];
    return isVoice(next) && next.status.isSent ? next : null;
  }

  static Future<void> _play(
    MatrixState matrix,
    Event event,
    Timeline timeline,
    AudioPlayer finished,
  ) async {
    try {
      final file = await event.downloadAndDecryptAttachment();
      File? local;
      final url = event.attachmentOrThumbnailMxcUrl();
      if (!kIsWeb && url != null) {
        final dir = await getTemporaryDirectory();
        local = File(
          '${dir.path}/${Uri.encodeComponent(url.pathSegments.last)}_${file.name}',
        );
        await local.writeAsBytes(file.bytes);
      }
      // Пока качалось, человек мог запустить другое сообщение: тогда не мешаем
      if (!identical(matrix.audioPlayer, finished)) return;
      final player = AudioPlayer();
      if (local != null) {
        await player.setFilePath(local.path);
      } else {
        await player.setAudioSource(
          AudioSource.uri(
            Uri.dataFromBytes(file.bytes, mimeType: file.mimeType),
          ),
        );
      }
      await player.setSpeed(AppSettings.voiceMessageSpeedPercent.value / 100);
      if (!identical(matrix.audioPlayer, finished)) {
        await player.dispose();
        return;
      }
      matrix.audioPlayer = player;
      matrix.voiceMessageEventId.value = event.eventId;
      unawaited(finished.dispose());
      attach(matrix, player, event, timeline);
      unawaited(player.play().catchError((Object _) {}));
    } catch (e, s) {
      Logs().v('DVChat: не удалось продолжить цепочку голосовых', e, s);
    }
  }
}
