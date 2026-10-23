import 'package:audioplayers/audioplayers.dart';

/// Round-robin sample player for the Zombies vs Chickens SFX pack, plus a
/// looping synthwave background track.
class GameAudio {
  GameAudio();

  final Map<String, List<AudioPlayer>> _pools = {};
  final Map<String, int> _cursor = {};
  AudioPlayer? _music;
  bool enabled = true;
  bool _ready = false;
  bool _musicStarted = false;

  static const Map<String, String> _files = {
    'shoot': 'audio/sfx/sfx_laser_necro.wav',
    'hit': 'audio/sfx/sfx_chicken_cluck_hit.wav',
    'explosion': 'audio/sfx/sfx_explosion_small.wav',
    'squawk': 'audio/sfx/sfx_chicken_squawk_death.wav',
    'splat': 'audio/sfx/sfx_egg_drop.wav',
    'powerup': 'audio/sfx/sfx_powerup_mutagen.wav',
    'pickup': 'audio/sfx/sfx_pickup_drumstick.wav',
    'boss': 'audio/sfx/sfx_boss_roar.wav',
    'bossDeath': 'audio/sfx/sfx_explosion_boss.wav',
    'click': 'audio/sfx/sfx_ui_click.wav',
    'wave': 'audio/sfx/sfx_ui_click.wav',
    'gameover': 'audio/sfx/sfx_explosion_boss.wav',
  };

  static const Map<String, double> _volumes = {
    'shoot': 0.26,
    'hit': 0.32,
    'explosion': 0.5,
    'squawk': 0.4,
    'splat': 0.45,
    'powerup': 0.6,
    'pickup': 0.6,
    'boss': 0.75,
    'bossDeath': 0.7,
    'click': 0.4,
    'wave': 0.45,
    'gameover': 0.75,
  };

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    for (final entry in _files.entries) {
      final players = <AudioPlayer>[];
      for (var i = 0; i < 2; i++) {
        final p = AudioPlayer();
        try {
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setSource(AssetSource(entry.value));
          await p.setVolume(_volumes[entry.key] ?? 0.5);
        } catch (_) {
          // Audio must never break the game.
        }
        players.add(p);
      }
      _pools[entry.key] = players;
      _cursor[entry.key] = 0;
    }
  }

  Future<void> startMusic() async {
    if (_musicStarted) return;
    _musicStarted = true;
    try {
      final m = AudioPlayer();
      await m.setReleaseMode(ReleaseMode.loop);
      await m.setVolume(0.20);
      await m.play(AssetSource('audio/music/bgm_galactic_undead_loop.wav'));
      _music = m;
    } catch (_) {}
  }

  /// Minimum gap between two plays of the same sound. Every play has to
  /// re-load the sample on the platform side, so spraying 6 shots a second is
  /// what used to drag the whole game down.
  static const Map<String, int> _minGapMs = {
    'shoot': 150,
    'squawk': 110,
    'explosion': 110,
    'splat': 130,
    'hit': 80,
  };

  final Map<String, int> _lastPlayMs = {};

  void play(String name, {double gain = 1.0}) {
    if (!enabled) return;
    final gap = _minGapMs[name] ?? 0;
    if (gap > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastPlayMs[name] ?? 0;
      if (now - last < gap) return;
      _lastPlayMs[name] = now;
    }
    final pool = _pools[name];
    if (pool == null || pool.isEmpty) return;
    final i = (_cursor[name] ?? 0) % pool.length;
    _cursor[name] = i + 1;
    try {
      final v = ((_volumes[name] ?? 0.5) * gain).clamp(0.0, 1.0);
      final player = pool[i];
      player.setVolume(v);
      // Replay the sample that setSource() already loaded. Calling
      // play(AssetSource) re-decodes the file on the platform thread every
      // single time, which is what dragged the frame rate down to ~10 fps.
      player
          .stop()
          .then((_) => player.resume())
          .catchError((Object _) {
            player.play(AssetSource(_files[name]!), volume: v);
          });
    } catch (_) {}
  }

  void setMusicPaused(bool paused) {
    try {
      if (paused) {
        _music?.pause();
      } else {
        _music?.resume();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final pool in _pools.values) {
      for (final p in pool) {
        try {
          await p.dispose();
        } catch (_) {}
      }
    }
    _pools.clear();
    try {
      await _music?.dispose();
    } catch (_) {}
  }
}
