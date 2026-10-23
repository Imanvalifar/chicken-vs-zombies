import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../game/audio.dart';
import 'entities.dart';
import 'game_assets.dart';

enum GamePhase { menu, playing, paused, gameOver }

/// Flame implementation of Chicken vs Zombies: a component tree driven by
/// [FlameGame]'s loop, with sprites, sprite animations and a component HUD.
class ChickenFightGame extends FlameGame {
  ChickenFightGame(this.audio);

  final GameAudio audio;
  final GameAssets art = GameAssets();

  final ValueNotifier<GamePhase> phase = ValueNotifier(GamePhase.menu);
  final ValueNotifier<bool> assetsReady = ValueNotifier<bool>(false);
  final ValueNotifier<int> bombs = ValueNotifier<int>(0);
  final math.Random rng = math.Random();

  double elapsed = 0;
  double waveClock = 0;
  double diveClock = 2;
  double eggGate = 0;
  double shake = 0;
  double flash = 0;
  double bannerT = 0;
  double bannerDur = 2;
  String banner = '';
  String subBanner = '';

  int score = 0;
  int best = 0;
  int lives = 3;
  int wave = 1;
  int killsSinceGift = 0;
  int giftThreshold = 9;

  late PlayerShip player;
  late HudComponent hud;
  late BackgroundComponent background;
  MotherHen? boss;

  bool touchMode = false;
  EdgeInsets safe = EdgeInsets.zero;

  double get scale => clampD(size.x / 900, 0.58, 1.35);
  double get driftY => clampD(waveClock * 4.0, 0, size.y * 0.04);
  double get minShipY => size.y * 0.62;
  double get maxShipY => size.y - 34 * scale - safe.bottom;
  double get minShipX => 26 * scale + safe.left;
  double get maxShipX => size.x - 26 * scale - safe.right;
  double get playerSpawnY => size.y - 62 * scale;

  int get eggCount => children.whereType<Egg>().length;
  Iterable<Chicken> get chickens => children.whereType<Chicken>();
  Iterable<Bullet> get bullets => children.whereType<Bullet>();

  double _pointerTargetX = 0;
  double _pointerTargetY = 0;
  double _dragOriginX = 0;
  double _dragOriginY = 0;
  double _dragShipX = 0;
  double _dragShipY = 0;
  bool pointerActive = false;
  bool pointerFiring = false;
  bool keyLeft = false;
  bool keyRight = false;
  bool keyUp = false;
  bool keyDown = false;
  bool keyFire = false;
  double inputLock = 0;

  @override
  Future<void> onLoad() async {
    await art.load();
    background = BackgroundComponent(art);
    hud = HudComponent(this);
    addAll([background, hud]);
    assetsReady.value = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    if (shake > 0.2) shake = math.max(0, shake - dt * 60);
    if (flash > 0) flash = math.max(0, flash - dt * 3);
    if (bannerT > 0) bannerT = math.max(0, bannerT - dt);
    if (eggGate > 0) eggGate -= dt;
    if (inputLock > 0) inputLock -= dt;

    if (phase.value != GamePhase.playing) return;

    waveClock += dt;
    _updatePlayer(dt);
    _updateWave(dt);
    _collide();
  }

  // ------------------------------------------------------------------ state
  void startGame({int startWave = 1}) {
    children.whereType<Chicken>().toList().forEach((c) => c.removeFromParent());
    children.whereType<Egg>().toList().forEach((e) => e.removeFromParent());
    children.whereType<Gift>().toList().forEach((g) => g.removeFromParent());
    children.whereType<Bullet>().toList().forEach((b) => b.removeFromParent());
    children.whereType<ExplosionFx>().toList().forEach((f) => f.removeFromParent());
    children.whereType<FloatText>().toList().forEach((t) => t.removeFromParent());
    boss?.removeFromParent();
    boss = null;

    score = 0;
    lives = 3;
    bombs.value = 1;
    killsSinceGift = 0;
    giftThreshold = 9;
    waveClock = 0;
    eggGate = 0;
    shake = 0;
    flash = 0;

    player = PlayerShip(assets: art)
      ..position = Vector2(size.x / 2, playerSpawnY);
    add(player);

    pointerActive = false;
    pointerFiring = false;
    keyFire = false;
    inputLock = 0.4;
    paused = false;
    phase.value = GamePhase.playing;
    spawnWave(startWave);
  }

  void togglePause() {
    if (phase.value == GamePhase.playing) {
      phase.value = GamePhase.paused;
      paused = true;
    } else if (phase.value == GamePhase.paused) {
      phase.value = GamePhase.playing;
      paused = false;
    }
  }

  void backToMenu() {
    children.whereType<Chicken>().toList().forEach((c) => c.removeFromParent());
    children.whereType<Egg>().toList().forEach((e) => e.removeFromParent());
    children.whereType<Gift>().toList().forEach((g) => g.removeFromParent());
    children.whereType<Bullet>().toList().forEach((b) => b.removeFromParent());
    boss?.removeFromParent();
    boss = null;
    if (children.contains(player)) player.removeFromParent();
    paused = false;
    phase.value = GamePhase.menu;
  }

  void useBomb() {
    if (bombs.value <= 0 || phase.value != GamePhase.playing) return;
    bombs.value = bombs.value - 1;
    _nuke();
  }

  // ------------------------------------------------------------------ waves
  void spawnWave(int n) {
    wave = n;
    waveClock = 0;
    diveClock = n <= 2 ? 4.0 : 2.2;
    banner = 'LEVEL $n';
    subBanner = n % 5 == 0 ? 'MOTHER HEN INCOMING' : '';
    bannerT = 2.0;
    bannerDur = 2.0;
    audio.play('wave', gain: 0.7);
    if (n % 5 == 0) {
      audio.play('boss', gain: 0.9);
      _spawnBoss(n);
    } else {
      _spawnFormation(n);
    }
  }

  void _spawnFormation(int n) {
    final r = 20.0 * scale;
    final maxCols = math.max(4, (size.x * 0.92 / (r * 3.55)).floor());
    final cols = math.min(math.min(5 + (n - 1) ~/ 3, 11), maxCols);
    final rows = math.min(3 + (n - 1) ~/ 4, 5);
    final gapX = math.min(r * 3.55, (size.x * 0.92) / cols);
    final totalW = gapX * (cols - 1);
    final startX = (size.x - totalW) / 2;
    final startY = size.y * 0.09;
    final band = size.y * 0.50 - startY;
    final gapY = math.min(r * 3.15, band / math.max(1, rows - 1));

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        var kind = ChickenKind.white;
        if (n >= 6 && row == 0) {
          kind = ChickenKind.ufo;
        } else if (n >= 3 && row == 0) {
          kind = ChickenKind.armored;
        } else if (n >= 2 && row == 1) {
          kind = ChickenKind.brown;
        }
        final hp = switch (kind) {
          ChickenKind.white => 1,
          ChickenKind.brown => 2,
          ChickenKind.armored => 3,
          ChickenKind.ufo => 4,
        };
        final home = Vector2(startX + col * gapX, startY + row * gapY);
        final from = Vector2(
          home.x + (col.isEven ? 1 : -1) * r * 2.2,
          -r * 2 - row * r * 0.8,
        );
        final hen = Chicken(
          assets: art,
          kind: kind,
          home: home,
          hp: hp,
          radius: r * (kind == ChickenKind.armored ? 1.06 : 1.0),
          entryFrom: from,
          entryDelay: (col + row) * 0.055 + rng.nextDouble() * 0.12,
          flap: rng.nextDouble() * math.pi * 2,
        );
        hen.eggTimer = 4.0 + rng.nextDouble() * 7.0;
        add(hen);
      }
    }
  }

  void _spawnBoss(int n) {
    final b = MotherHen(assets: art, hp: (40 + n * 12).toDouble());
    boss = b;
    add(b);
  }

  void bossVolley(MotherHen b) {
    audio.play('splat', gain: 0.5);
    for (var i = -2; i <= 2; i++) {
      final angle = math.pi / 2 + i * 0.28;
      final speed = 150.0 + wave * 6;
      add(
        Egg(
          assets: art,
          position: b.position + Vector2(0, b.size.y * 0.32),
          velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
          radius: 8 * scale,
        ),
      );
    }
  }

  void bossSpawnChicks(MotherHen b) {
    for (var i = 0; i < 3; i++) {
      final home = Vector2(
        b.position.x + (i - 1) * 90,
        size.y * 0.16,
      );
      final hen = Chicken(
        assets: art,
        kind: ChickenKind.brown,
        home: home,
        hp: 2,
        radius: 19 * scale,
        entryFrom: Vector2(home.x, -60),
        entryDelay: i * 0.08,
        flap: rng.nextDouble() * math.pi * 2,
      );
      hen.state = ChickenState.formation;
      hen.position = home.clone();
      add(hen);
    }
  }

  void _updateWave(double dt) {
    // a boss that finished its death animation removes itself from the tree,
    // so drop the stale reference or the level can never clear
    if (boss != null && !boss!.isMounted) boss = null;
    final hasChickens = chickens.isNotEmpty;
    if (!hasChickens && boss == null && !_clearing) {
      _clearing = true;
      _clearTimer = 2.0;
      final bonus = 250 * wave;
      score += bonus;
      banner = 'LEVEL CLEAR';
      subBanner = '+$bonus BONUS';
      bannerT = 1.9;
      bannerDur = 1.9;
    }
    if (_clearing) {
      _clearTimer -= dt;
      if (_clearTimer <= 0) {
        _clearing = false;
        spawnWave(wave + 1);
      }
    }

    // dive scheduler
    if (!hasChickens) return;
    diveClock -= dt;
    if (diveClock <= 0) {
      diveClock =
          math.max(1.5, 3.8 - wave * 0.18) * (0.8 + rng.nextDouble() * 0.6);
      final candidates = chickens
          .where((c) => c.state == ChickenState.formation)
          .toList();
      if (candidates.isNotEmpty) {
        final hen = candidates[rng.nextInt(candidates.length)];
        hen.state = ChickenState.diving;
        hen.diveT = 0;
        hen.diveStart = hen.position.clone();
        hen.diveDir = rng.nextBool() ? 1 : -1;
        hen.eggsDropped = 0;
        hen.eggsToDrop = wave <= 2 ? 0 : 1 + rng.nextInt(2);
        final side = rng.nextBool() ? 1.0 : -1.0;
        hen.diveTarget = Vector2(
          clampD(
            player.position.x + side * size.x * (0.16 + rng.nextDouble() * 0.14),
            size.x * 0.08,
            size.x * 0.92,
          ),
          size.y * (0.70 + rng.nextDouble() * 0.10),
        );
        audio.play('cluck', gain: 0.4);
      }
    }
  }

  bool _clearing = false;
  double _clearTimer = 0;

  // ----------------------------------------------------------------- player
  void _updatePlayer(double dt) {
    final p = player;
    var dx = 0.0;
    var dy = 0.0;
    if (keyLeft) dx -= 1;
    if (keyRight) dx += 1;
    if (keyUp) dy -= 1;
    if (keyDown) dy += 1;

    if (pointerActive && dx == 0 && dy == 0) {
      final tx = clampD(_pointerTargetX, minShipX, maxShipX);
      final ty = clampD(_pointerTargetY, minShipY, maxShipY);
      p.position.x += (tx - p.position.x) * math.min(1.0, dt * 16);
      p.position.y += (ty - p.position.y) * math.min(1.0, dt * 16);
      p.tilt = clampD((tx - p.position.x) * 0.0022, -0.3, 0.3);
    } else {
      p.position.x += dx * 540 * scale * dt;
      p.position.y += dy * 430 * scale * dt;
      p.tilt += (dx * 0.24 - p.tilt) * math.min(1, dt * 12);
    }
    p.position.x = clampD(p.position.x, minShipX, maxShipX);
    p.position.y = clampD(p.position.y, minShipY, maxShipY);
    p.angle = p.tilt;

    if ((keyFire || pointerFiring) && p.fireCooldown <= 0) _shoot();
  }

  void _shoot() {
    final p = player;
    final lvl = p.weaponLevel;
    p.fireCooldown = math.max(0.075, 0.195 - lvl * 0.017);
    p.muzzle = 1;
    final y = p.position.y - 30 * scale;
    final shots = switch (lvl) {
      1 => [(0.0, 0.0)],
      2 => [(-9.0, 0.0), (9.0, 0.0)],
      3 => [(0.0, 0.0), (-13.0, -0.10), (13.0, 0.10)],
      4 => [(-8.0, 0.0), (8.0, 0.0), (-17.0, -0.15), (17.0, 0.15)],
      _ => [
        (0.0, 0.0),
        (-9.0, -0.06),
        (9.0, 0.06),
        (-18.0, -0.18),
        (18.0, 0.18),
      ],
    };
    for (final s in shots) {
      final dir = Vector2(math.sin(s.$2), -math.cos(s.$2));
      add(
        Bullet(
          assets: art,
          position: Vector2(p.position.x + s.$1 * scale, y),
          velocity: dir * (770 + lvl * 22),
        ),
      );
    }
    audio.play('shoot');
  }

  // ------------------------------------------------------------------ eggs
  void dropEgg(Vector2 from, {bool aimed = false, double speedBoost = 0}) {
    if (eggGate > 0) return;
    eggGate = 0.38 + rng.nextDouble() * 0.34;
    var vx = (rng.nextDouble() - 0.5) * 40;
    var vy = 115 + wave * 7 + speedBoost;
    if (aimed) {
      final dx = player.position.x - from.x;
      final dy = player.position.y - from.y;
      final len = math.max(1.0, math.sqrt(dx * dx + dy * dy));
      final speed = 118 + wave * 7 + speedBoost;
      vx = dx / len * speed * 0.30;
      vy = speed;
    }
    add(
      Egg(
        assets: art,
        position: from.clone(),
        velocity: Vector2(vx, vy),
        radius: 8 * scale,
      ),
    );
  }

  // ------------------------------------------------------------ collisions
  void _collide() {
    final p = player;
    final pPos = p.position;
    const pRadius = 13.0;

    for (final b in bullets.toList()) {
      for (final c in chickens.toList()) {
        if (!c.isMounted || !b.isMounted) continue;
        final d = (c.position - b.position).length;
        if (d < c.radius * 0.95 + 8) {
          b.removeFromParent();
          _damageChicken(c);
          break;
        }
      }
      if (!b.isMounted) continue;
      final b2 = boss;
      if (b2 != null && !b2.dying) {
        final d = (b2.position - b.position).length;
        if (d < b2.size.x * 0.38) {
          b.removeFromParent();
          _damageBoss(1);
        }
      }
    }

    for (final e in children.whereType<Egg>().toList()) {
      if (!e.isMounted) continue;
      if ((e.position - pPos).length < e.radius * 0.9 + pRadius * 0.7) {
        e.removeFromParent();
        _splat(e.position, e.radius);
        _killPlayer();
      }
    }

    for (final g in children.whereType<Gift>().toList()) {
      if (!g.isMounted) continue;
      if ((g.position - pPos).length < 34) {
        g.removeFromParent();
        _collectGift(g.kind, g.position);
      }
    }

    if (p.invuln <= 0) {
      for (final c in chickens.toList()) {
        if (!c.isMounted) continue;
        if ((c.position - pPos).length < c.radius * 0.55 + pRadius * 0.6) {
          _damageChicken(c, force: true);
          _killPlayer();
          break;
        }
      }
      final b2 = boss;
      if (b2 != null &&
          !b2.dying &&
          (b2.position - pPos).length < b2.size.x * 0.3) {
        _killPlayer();
      }
    }
  }

  void _damageChicken(Chicken c, {bool force = false}) {
    c.hp -= 1;
    c.hitFlash = 1;
    audio.play('hit', gain: 0.4);
    if (c.hp > 0 && !force) return;
    _killChicken(c);
  }

  void _killChicken(Chicken c) {
    final pts = switch (c.kind) {
      ChickenKind.white => 100,
      ChickenKind.brown => 200,
      ChickenKind.armored => 350,
      ChickenKind.ufo => 400,
    };
    score += pts;
    _addText(c.position, '+$pts', kGold);
    spawnExplosion(c.position, c.radius, feathers: true);
    audio.play('squawk', gain: 0.55);
    audio.play('explosion', gain: c.radius > 26 ? 0.9 : 0.5);

    killsSinceGift++;
    if (killsSinceGift >= giftThreshold) {
      final onScreen = children.whereType<Gift>().length;
      if (onScreen < 2) {
        killsSinceGift = 0;
        giftThreshold = 10 + rng.nextInt(7);
        _spawnGift(c.position);
      }
    }
    c.removeFromParent();
  }

  void _damageBoss(int amount) {
    final b = boss;
    if (b == null || b.dying) return;
    b.hp -= amount;
    b.hitFlash = 1;
    audio.play('hit', gain: 0.5);
    if (b.hp <= 0) {
      b.dying = true;
      score += 5000;
      _addText(b.position, '+5000', kGold);
      audio.play('bossDeath', gain: 1.0);
      for (var i = 0; i < 3; i++) {
        _spawnGift(
          b.position +
              Vector2((rng.nextDouble() - 0.5) * 160, rng.nextDouble() * 60),
        );
      }
      shake = 26;
      flash = 0.6;
    }
  }

  void _killPlayer() {
    final p = player;
    if (p.invuln > 0 || phase.value != GamePhase.playing) return;
    lives--;
    shake = 18;
    flash = 0.45;
    audio.play('explosion', gain: 1.0);
    spawnExplosion(p.position, 30, feathers: true);
    if (lives <= 0) {
      best = math.max(best, score);
      phase.value = GamePhase.gameOver;
      paused = true;
      audio.play('gameover', gain: 0.8);
      return;
    }
    p.invuln = 2.8;
    p.position.setValues(size.x / 2, playerSpawnY);
    p.setWeaponLevel(math.max(1, p.weaponLevel - 1));
    pointerActive = false;
    pointerFiring = false;
  }

  void _collectGift(GiftKind kind, Vector2 at) {
    final p = player;
    if (kind == GiftKind.life) {
      audio.play('pickup');
    } else {
      audio.play('powerup');
    }
    switch (kind) {
      case GiftKind.weapon:
        if (p.weaponLevel < 5) {
          p.setWeaponLevel(p.weaponLevel + 1);
          _addText(at, 'WEAPON UP', kToxic);
        } else {
          score += 500;
          _addText(at, '+500', kGold);
        }
        break;
      case GiftKind.life:
        lives = math.min(6, lives + 1);
        _addText(at, '+1 LIFE', const Color(0xFFFF8FA3));
        break;
      case GiftKind.shield:
        p.invuln = math.max(p.invuln, 9);
        _addText(at, 'SHIELD', kToxicSoft);
        break;
      case GiftKind.nuke:
        if (bombs.value < 3) bombs.value = bombs.value + 1;
        _addText(at, '+MISSILE', kOrange);
        break;
    }
  }

  void _spawnGift(Vector2 at) {
    final roll = rng.nextDouble();
    final GiftKind kind;
    if (roll < 0.08) {
      kind = GiftKind.nuke;
    } else if (roll < 0.56) {
      kind = GiftKind.weapon;
    } else if (roll < 0.80) {
      kind = GiftKind.life;
    } else {
      kind = GiftKind.shield;
    }
    add(Gift(assets: art, kind: kind, position: at.clone()));
  }

  void _nuke() {
    flash = 0.9;
    shake = 30;
    audio.play('bossDeath', gain: 0.85);
    for (final c in chickens.toList()) {
      score += 100;
      spawnExplosion(c.position, c.radius, feathers: true);
      c.removeFromParent();
    }
    final b = boss;
    if (b != null && !b.dying) _damageBoss(16);
    for (var i = 0; i < 18; i++) {
      spawnExplosion(
        Vector2(
          rng.nextDouble() * size.x,
          size.y * 0.10 + rng.nextDouble() * size.y * 0.55,
        ),
        18 * scale,
        feathers: i.isEven,
      );
    }
  }

  void spawnExplosion(Vector2 at, double radius, {bool feathers = false}) {
    add(
      ExplosionFx(
        animation: art.explosion,
        position: at.clone(),
        size: radius * 4.6,
      ),
    );
    if (feathers) {
      add(
        ExplosionFx(
          animation: art.feathers,
          position: at.clone(),
          size: radius * 4.2,
        ),
      );
    }
  }

  void _splat(Vector2 at, double radius) {
    audio.play('splat', gain: 0.4);
    add(
      ExplosionFx(
        animation: art.feathers,
        position: at.clone(),
        size: radius * 3.2,
      ),
    );
  }

  void _addText(Vector2 at, String text, Color color) {
    add(
      FloatText(
        text: text,
        position: at.clone(),
        color: color,
        fontSize: 14 * scale,
      ),
    );
  }

  // ------------------------------------------------------------------ input
  void setKey({
    bool? left,
    bool? right,
    bool? up,
    bool? down,
    bool? fire,
  }) {
    if (left != null) keyLeft = left;
    if (right != null) keyRight = right;
    if (up != null) keyUp = up;
    if (down != null) keyDown = down;
    if (fire != null) keyFire = fire;
  }

  void pointerDown(double x, double y, {bool relative = false}) {
    if (inputLock > 0 || phase.value != GamePhase.playing) return;
    pointerActive = true;
    pointerFiring = true;
    if (relative) {
      _dragOriginX = x;
      _dragOriginY = y;
      _dragShipX = player.position.x;
      _dragShipY = player.position.y;
      _pointerTargetX = player.position.x;
      _pointerTargetY = player.position.y;
    } else {
      _pointerTargetX = x;
      _pointerTargetY = y;
    }
  }

  void pointerMove(double x, double y, {bool relative = false}) {
    if (!pointerActive) return;
    if (relative) {
      _pointerTargetX = _dragShipX + (x - _dragOriginX);
      _pointerTargetY = _dragShipY + (y - _dragOriginY);
    } else {
      _pointerTargetX = x;
      _pointerTargetY = y;
    }
  }

  void pointerUp() {
    pointerActive = false;
    pointerFiring = false;
  }
}

// ---------------------------------------------------------------- background
class BackgroundComponent extends PositionComponent
    with HasGameReference<ChickenFightGame> {
  BackgroundComponent(this.assets) : super(priority: -10);

  final GameAssets assets;

  @override
  void render(Canvas canvas) {
    final sprite = assets.background;
    final dst = Rect.fromLTWH(0, 0, game.size.x, game.size.y);
    canvas.drawImageRect(sprite.image, sprite.src, dst, Paint());
    canvas.drawRect(dst, Paint()..color = const Color(0x33000000));
  }
}

// ----------------------------------------------------------------------- HUD
class HudComponent extends PositionComponent
    with HasGameReference<ChickenFightGame> {
  HudComponent(this.gameRef) : super(priority: 100);

  final ChickenFightGame gameRef;

  final Map<String, TextPaint> _paintCache = {};

  TextPaint _paint(
    double size,
    Color color, {
    double spacing = 0,
    FontWeight weight = FontWeight.w900,
    List<Shadow>? shadows,
  }) {
    final key = '$size|$color|$spacing|$weight';
    return _paintCache.putIfAbsent(
      key,
      () => TextPaint(
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1.1,
          shadows: shadows ?? const [Shadow(color: Color(0x99000000), blurRadius: 6)],
        ),
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final g = gameRef;
    if (g.phase.value == GamePhase.menu) return;
    final s = g.size;
    final l = 20.0 + g.safe.left;
    final r = s.x - 20.0 - g.safe.right;

    _paint(10, const Color(0x80FFFFFF), spacing: 3)
        .render(canvas, 'SCORE', Vector2(l, 14));
    _paint(26, const Color(0xFFFFFFFF), spacing: 1.5)
        .render(canvas, g.score.toString().padLeft(6, '0'), Vector2(l, 26));

    // lives
    final ship = g.art.ship1.frames.first.sprite;
    for (var i = 0; i < g.lives; i++) {
      canvas.drawImageRect(
        ship.image,
        ship.src,
        Rect.fromLTWH(l + i * 27, 56, 26, 26),
        Paint(),
      );
    }

    _paint(10, const Color(0x80FFFFFF), spacing: 3).render(
      canvas,
      'LEVEL',
      Vector2(r, 14),
      anchor: Anchor.topRight,
    );
    _paint(26, const Color(0xFFFFFFFF), spacing: 1.5).render(
      canvas,
      g.wave.toString().padLeft(2, '0'),
      Vector2(r, 26),
      anchor: Anchor.topRight,
    );

    for (var i = 0; i < 5; i++) {
      final on = i < g.player.weaponLevel;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r - 74 + i * 15, 62, 11, 6),
          const Radius.circular(2),
        ),
        Paint()..color = on ? kToxic : const Color(0x29FFFFFF),
      );
    }

    // boss bar
    final b = g.boss;
    if (b != null && !b.dying) {
      final w = math.min(s.x * 0.52, 460.0);
      final left = (s.x - w) / 2;
      const top = 14.0;
      final frame = g.art.hudBarFrame;
      canvas.drawImageRect(
        frame.image,
        frame.src,
        Rect.fromLTWH(left, top, w, 22),
        Paint(),
      );
      final frac = clampD(b.hp / b.maxHp, 0, 1);
      final fw = (w - 12) * frac;
      if (fw > 1) {
        final fill = g.art.hudBossFill;
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left + 6, top + 6, fw, 10),
            const Radius.circular(5),
          ),
        );
        canvas.drawImageRect(
          fill.image,
          Rect.fromLTWH(0, 0, fill.src.width * frac, fill.src.height),
          Rect.fromLTWH(left + 6, top + 6, fw, 10),
          Paint(),
        );
        canvas.restore();
      }
      _paint(11, const Color(0xFFFFC7A1), spacing: 3).render(
        canvas,
        'MOTHER HEN',
        Vector2(s.x / 2, top + 24),
        anchor: Anchor.topCenter,
      );
    }

    // banner
    if (g.bannerT > 0 && g.banner.isNotEmpty) {
      final a = clampD(
        math.min((g.bannerDur - g.bannerT) / 0.18, g.bannerT / 0.55),
        0,
        1,
      );
      final dy = (1 - clampD((g.bannerDur - g.bannerT) / 0.35, 0, 1)) * 14;
      _paint(
        44,
        const Color(0xFFFFFFFF).withValues(alpha: a),
        spacing: 8,
        shadows: [
          Shadow(color: kToxic.withValues(alpha: a * 0.55), blurRadius: 24),
          Shadow(color: kToxic.withValues(alpha: a * 0.35), blurRadius: 48),
        ],
      ).render(
        canvas,
        g.banner,
        Vector2(s.x / 2, s.y * 0.36 - dy),
        anchor: Anchor.topCenter,
      );
      if (g.subBanner.isNotEmpty) {
        _paint(
          15,
          const Color(0xFFFFD166).withValues(alpha: a),
          spacing: 4,
        ).render(
          canvas,
          g.subBanner,
          Vector2(s.x / 2, s.y * 0.36 + 42 - dy),
          anchor: Anchor.topCenter,
        );
      }
    }

    // flash
    if (g.flash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s.x, s.y),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: g.flash * 0.25),
      );
    }
  }
}
