// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: звук в играх. Короткие тона генерируются прямо в приложении (в проект никакие
// звуковые файлы не добавляются) и проигрываются через just_audio. Звук нужен только в играх:
// значок динамика в шапке игры включает и выключает его, долгое нажатие открывает громкость.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dvchat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

enum DvSound { place, enemy, win, lose, hit, miss, sunk }

class DvGameSound {
  static const int _rate = 22050;
  static final Map<DvSound, Future<AudioPlayer>> _players = {};

  static bool get enabled => AppSettings.gameSound.value;

  static double get volume => AppSettings.gameVolume.value.clamp(0.0, 1.0);

  static Future<AudioPlayer> _player(DvSound s) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dvgame_${s.name}.wav');
    await file.writeAsBytes(_wav(_samples(s)));
    final p = AudioPlayer();
    await p.setFilePath(file.path);
    return p;
  }

  static Future<void> play(DvSound s) async {
    if (kIsWeb || !enabled || volume <= 0) return;
    try {
      final p = await (_players[s] ??= _player(s));
      await p.setVolume(volume);
      await p.seek(Duration.zero);
      unawaited(p.play());
    } catch (_) {
      // Звук необязателен: при любой ошибке игра идёт молча
      _players.remove(s);
    }
  }

  // ---------- синтез ----------

  static List<double> _tone(double hz, double ms, {double decay = 6}) {
    final n = (_rate * ms / 1000).round();
    return [
      for (var i = 0; i < n; i++)
        sin(2 * pi * hz * i / _rate) *
            exp(-decay * i / n) *
            min(1.0, i / (_rate * 0.004)),
    ];
  }

  static List<double> _noise(double ms, {double decay = 8, double soft = 0.2}) {
    final rnd = Random(7);
    final n = (_rate * ms / 1000).round();
    var y = 0.0;
    return [
      for (var i = 0; i < n; i++)
        (y += ((rnd.nextDouble() * 2 - 1) - y) * soft) * exp(-decay * i / n),
    ];
  }

  static List<double> _mix(List<double> a, List<double> b) {
    final n = max(a.length, b.length);
    return [
      for (var i = 0; i < n; i++)
        (i < a.length ? a[i] : 0.0) + (i < b.length ? b[i] : 0.0),
    ];
  }

  static List<double> _scale(List<double> a, double k) => [
    for (final v in a) v * k,
  ];

  static List<double> _seq(List<List<double>> parts) => [
    for (final p in parts) ...p,
  ];

  static List<double> _samples(DvSound s) {
    switch (s) {
      case DvSound.place:
        return _mix(_tone(660, 90, decay: 7), _scale(_tone(1320, 90), 0.25));
      case DvSound.enemy:
        return _mix(_tone(440, 90, decay: 7), _scale(_tone(880, 90), 0.2));
      case DvSound.win:
        return _seq([
          _tone(523.25, 120, decay: 4),
          _tone(659.25, 120, decay: 4),
          _tone(783.99, 120, decay: 4),
          _tone(1046.5, 320, decay: 3),
        ]);
      case DvSound.lose:
        return _seq([
          _tone(392, 170, decay: 3),
          _tone(329.63, 170, decay: 3),
          _tone(261.63, 340, decay: 3),
        ]);
      case DvSound.hit:
        return _mix(_scale(_noise(130), 0.9), _scale(_tone(110, 170), 0.8));
      case DvSound.miss:
        return _scale(_noise(170, decay: 9, soft: 0.08), 0.6);
      case DvSound.sunk:
        return _seq([
          _mix(_scale(_noise(130), 0.9), _scale(_tone(110, 170), 0.8)),
          _tone(164.81, 320, decay: 4),
        ]);
    }
  }

  static Uint8List _wav(List<double> samples) {
    final n = samples.length;
    final bd = ByteData(44 + n * 2);
    void str(int o, String t) {
      for (var i = 0; i < t.length; i++) {
        bd.setUint8(o + i, t.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    bd.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, _rate, Endian.little);
    bd.setUint32(28, _rate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    str(36, 'data');
    bd.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      bd.setInt16(
        44 + i * 2,
        (samples[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little,
      );
    }
    return bd.buffer.asUint8List();
  }
}

/// Значок динамика для шапки игры: нажатие включает и выключает звук,
/// долгое нажатие открывает ползунок громкости.
class DvSoundButton extends StatefulWidget {
  const DvSoundButton({super.key});

  @override
  State<DvSoundButton> createState() => _DvSoundButtonState();
}

class _DvSoundButtonState extends State<DvSoundButton> {
  Future<void> _toggle() async {
    await AppSettings.gameSound.setItem(!DvGameSound.enabled);
    if (!mounted) return;
    setState(() {});
    unawaited(DvGameSound.play(DvSound.place));
  }

  Future<void> _volume() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => const _VolumeSheet(),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = DvGameSound.enabled && DvGameSound.volume > 0;
    final icon = !on
        ? Icons.volume_off
        : (DvGameSound.volume < 0.34 ? Icons.volume_down : Icons.volume_up);
    return Semantics(
      label: 'Звук',
      button: true,
      child: InkResponse(
        onTap: _toggle,
        onLongPress: _volume,
        radius: 24,
        child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon)),
      ),
    );
  }
}

class _VolumeSheet extends StatefulWidget {
  const _VolumeSheet();

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  late double _value = DvGameSound.volume;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Громкость игр',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  value: _value,
                  onChanged: (v) => setState(() => _value = v),
                  onChangeEnd: (v) async {
                    await AppSettings.gameVolume.setItem(v);
                    if (v > 0 && !DvGameSound.enabled) {
                      await AppSettings.gameSound.setItem(true);
                    }
                    unawaited(DvGameSound.play(DvSound.place));
                  },
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
        ],
      ),
    ),
  );
}
