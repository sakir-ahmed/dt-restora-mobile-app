import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound effects for the app: the exact same tiny melodies as the web back
/// office (`resources/js/lib/sounds.js`), rendered on the fly into WAV
/// bytes — nothing to bundle or download. Playback is instant because every
/// melody is rendered once and kept in memory.
class SoundFx {
  SoundFx._();

  static const int _rate = 12000;

  /// Notes are (frequency Hz, start s, length s, wave?) and every event has
  /// its own melody so staff can tell them apart without looking.
  static const _defs = <String, List<(double, double, double, String?)>>{
    'notification': [(880, 0, 0.12, null), (1318, 0.12, 0.2, null)],
    'error': [(220, 0, 0.18, 'square'), (165, 0.2, 0.3, 'square')],
    'item_added': [(1200, 0, 0.05, null)],
    'order_created': [(523, 0, 0.1, null), (659, 0.1, 0.1, null), (784, 0.2, 0.24, null)],
    'order_paid': [(1568, 0, 0.08, null), (2093, 0.09, 0.4, null)],
    'order_held': [(440, 0, 0.12, null), (330, 0.14, 0.22, null)],
    'order_cancelled': [(392, 0, 0.14, null), (294, 0.16, 0.14, null), (220, 0.32, 0.3, null)],
    'kds_new': [(988, 0, 0.1, null), (988, 0.18, 0.1, null), (1319, 0.36, 0.26, null)],
    'kds_preparing': [(392, 0, 0.1, 'triangle'), (523, 0.12, 0.2, 'triangle')],
    'kds_ready': [(784, 0, 0.12, null), (988, 0.14, 0.12, null), (1319, 0.28, 0.34, null)],
    'kds_served': [(659, 0, 0.08, 'triangle'), (523, 0.1, 0.22, 'triangle')],
  };

  /// Mirrors the web defaults; the quiet niceties stay off out of the box.
  static const _defaultEvents = <String, bool>{
    'notification': true,
    'error': true,
    'item_added': false,
    'order_created': true,
    'order_paid': true,
    'order_held': true,
    'order_cancelled': true,
    'kds_new': true,
    'kds_preparing': true,
    'kds_ready': true,
    'kds_served': true,
  };

  static bool enabled = true;
  static double volume = 0.7;
  static Map<String, bool> events = {..._defaultEvents};

  static final AudioPlayer _player = AudioPlayer(playerId: 'dt-restora-sfx')
    ..setReleaseMode(ReleaseMode.stop);
  static final Map<String, Uint8List> _cache = {};

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('sound_enabled') ?? true;
    volume = prefs.getDouble('sound_volume') ?? 0.7;
  }

  static Future<void> setEnabled(bool on) async {
    enabled = on;
    (await SharedPreferences.getInstance()).setBool('sound_enabled', on);
  }

  static Future<void> setVolume(double v) async {
    volume = v;
    (await SharedPreferences.getInstance()).setDouble('sound_volume', v);
  }

  static Future<void> play(String event) async {
    if (!enabled || !(events[event] ?? false)) {
      return;
    }
    try {
      final bytes = _cache.putIfAbsent(event, () => _render(event));
      await _player.setVolume(volume);
      await _player.play(BytesSource(bytes));
    } on Exception {
      // Sounds are decoration; never let one break a flow.
    }
  }

  /// Renders a melody into a 16-bit mono WAV, byte-for-byte the same layout
  /// as the web renderer.
  static Uint8List _render(String event) {
    final notes = _defs[event]!;
    var length = 0;
    for (final n in notes) {
      length = max(length, ((n.$2 + n.$3) * _rate).ceil());
    }
    length += (0.04 * _rate).ceil();
    final samples = List<double>.filled(length, 0);

    for (final n in notes) {
      final first = (n.$2 * _rate).floor();
      final count = (n.$3 * _rate).floor();
      for (var i = 0; i < count && first + i < length; i++) {
        final t = i / _rate;
        final phase = 2 * pi * n.$1 * t;
        final attack = min(1.0, i / (0.006 * _rate));
        final decay = exp((-3.5 * t) / n.$3);
        final raw = switch (n.$4) {
          'square' => sin(phase).sign * 0.55,
          'triangle' => (2 / pi) * asin(sin(phase)),
          _ => sin(phase),
        };
        samples[first + i] += raw * attack * decay * 0.55;
      }
    }

    final bytes = ByteData(44 + length * 2);
    void w(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    w(0, 'RIFF');
    bytes.setUint32(4, 36 + length * 2, Endian.little);
    w(8, 'WAVE');
    w(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, _rate, Endian.little);
    bytes.setUint32(28, _rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    w(36, 'data');
    bytes.setUint32(40, length * 2, Endian.little);
    for (var i = 0; i < length; i++) {
      bytes.setInt16(44 + i * 2, (samples[i].clamp(-1, 1) * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
