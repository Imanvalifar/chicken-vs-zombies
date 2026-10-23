import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:flame/components.dart';

import 'game.dart';
import 'game_assets.dart';

const Color kToxic = Color(0xFF7CFF4F);
const Color kToxicSoft = Color(0xFF8FD8FF);
const Color kGold = Color(0xFFFFD166);
const Color kOrange = Color(0xFFFF7A45);

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Sprite that can be hidden without being removed from the tree.
class FxSprite extends SpriteComponent with HasVisibility {
  FxSprite({
    super.sprite,
    super.size,
    super.anchor,
    super.position,
    super.priority,
    super.paint,
  });
}

// ---------------------------------------------------------------- player ship
class PlayerShip extends SpriteAnimationComponent
    with HasGameReference<ChickenFightGame> {
  PlayerShip({required this.assets})
    : super(size: Vector2.all(96), anchor: Anchor.center);

  final GameAssets assets;

  double invuln = 0;
  double tilt = 0;
  double fireCooldown = 0;
  double muzzle = 0;
  int weaponLevel = 1;
  int tier = 1;

  late final FxSprite _glow;
  late final FxSprite _shield;

  @override
  Future<void> onLoad() async {
    animation = assets.ship1;
    _glow = FxSprite(
      sprite: assets.glow,
      size: Vector2.all(150),
      anchor: Anchor.center,
      position: Vector2(0, 18),
      priority: -1,
    );
    _shield = FxSprite(
      sprite: assets.shield,
      size: Vector2.all(126),
      anchor: Anchor.center,
    )..isVisible = false;
    addAll([_glow, _shield]);
  }

  void setWeaponLevel(int level) {
    weaponLevel = level;
    final t = level <= 2 ? 1 : (level <= 4 ? 2 : 3);
    if (t != tier) {
      tier = t;
      animation = t == 1
          ? assets.ship1
          : (t == 2 ? assets.ship2 : assets.ship3);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (invuln > 0) invuln -= dt;
    if (muzzle > 0) muzzle = math.max(0, muzzle - dt * 7);
    fireCooldown -= dt;
    _shield.isVisible = invuln > 0;
    _shield.paint.color = const Color(0xFFFFFFFF).withValues(
      alpha: 0.45 + 0.3 * math.sin(game.elapsed * 9),
    );
    // blink while invulnerable
    if (invuln > 0 && (game.elapsed * 12).floor().isEven) {
      opacity = 0.25;
    } else {
      opacity = 1;
    }
  }
}

// -------------------------------------------------------------------- bullets
class Bullet extends SpriteComponent with HasGameReference<ChickenFightGame> {
  Bullet({required this.assets, required Vector2 position, required this.velocity})
    : super(
        sprite: assets.bolt,
        size: Vector2(22, 46),
        anchor: Anchor.center,
        position: position,
      );

  final GameAssets assets;
  final Vector2 velocity;
  double radius = 6;

  @override
  void update(double dt) {
    position.addScaled(velocity, dt);
    angle = math.atan2(velocity.y, velocity.x) + math.pi / 2;
    if (position.y < -60 || position.y > game.size.y + 40) removeFromParent();
  }
}

// ----------------------------------------------------------------------- eggs
class Egg extends SpriteComponent with HasGameReference<ChickenFightGame> {
  Egg({
    required this.assets,
    required Vector2 position,
    required this.velocity,
    required this.radius,
    this.gift,
  }) : super(
         sprite: assets.egg,
         size: Vector2(radius * 2.6, radius * 3.3),
         anchor: Anchor.center,
         position: position,
       );

  final GameAssets assets;
  final Vector2 velocity;
  final double radius;
  final GiftKind? gift;
  double spin = 0;

  @override
  void update(double dt) {
    position.addScaled(velocity, dt);
    spin += dt * 2.4;
    angle = math.sin(spin) * 0.12;
    if (position.y > game.size.y + 50) removeFromParent();
  }
}

enum GiftKind { weapon, life, shield, nuke }

class Gift extends SpriteComponent with HasGameReference<ChickenFightGame> {
  Gift({
    required this.assets,
    required this.kind,
    required Vector2 position,
  }) : super(
         sprite: _spriteFor(assets, kind),
         size: Vector2.all(44),
         anchor: Anchor.center,
         position: position,
       );

  final GameAssets assets;
  final GiftKind kind;
  double _t = 0;

  static Sprite _spriteFor(GameAssets a, GiftKind kind) => switch (kind) {
    GiftKind.weapon => a.pickupMutagen,
    GiftKind.life => a.pickupDrumstick,
    GiftKind.shield => a.pickupBrain,
    GiftKind.nuke => a.pickupNuke,
  };

  @override
  void update(double dt) {
    _t += dt;
    position.y += 95 * dt;
    scale = Vector2.all(1 + 0.06 * math.sin(_t * 6));
    if (position.y > game.size.y + 50) removeFromParent();
  }
}

// -------------------------------------------------------------------- chicken
enum ChickenKind { white, brown, armored, ufo }

enum ChickenState { entering, formation, diving, returning }

class Chicken extends SpriteAnimationComponent
    with HasGameReference<ChickenFightGame> {
  Chicken({
    required this.assets,
    required this.kind,
    required this.home,
    required this.hp,
    required this.radius,
    required this.entryFrom,
    required this.entryDelay,
    required this.flap,
  }) : super(
         size: Vector2.all(radius * 3.25),
         anchor: Anchor.center,
         position: entryFrom,
       );

  final GameAssets assets;
  final ChickenKind kind;
  final Vector2 home;
  int hp;
  final double radius;
  final Vector2 entryFrom;
  final double entryDelay;
  final double flap;

  int maxHp = 1;
  ChickenState state = ChickenState.entering;
  double t = 0;
  double diveT = 0;
  Vector2 diveStart = Vector2.zero();
  Vector2 diveTarget = Vector2.zero();
  double diveDir = 1;
  int eggsToDrop = 1;
  int eggsDropped = 0;
  double eggTimer = 6;
  double hitFlash = 0;

  bool get alive => hp > 0;

  @override
  Future<void> onLoad() async {
    maxHp = hp;
    animation = switch (kind) {
      ChickenKind.white => assets.chickenGrunt,
      ChickenKind.brown => assets.chickenKamikaze,
      ChickenKind.armored => assets.chickenArmored,
      ChickenKind.ufo => assets.chickenUfo,
    };
    angle = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hitFlash > 0) hitFlash = math.max(0, hitFlash - dt * 4);

    switch (state) {
      case ChickenState.entering:
        t += dt;
        if (t < entryDelay) break;
        final k = clampD((t - entryDelay) / 0.65, 0, 1);
        final e = k * k * (3 - 2 * k);
        position.setValues(
          entryFrom.x + (home.x - entryFrom.x) * e,
          entryFrom.y + (home.y - entryFrom.y) * e,
        );
        if (k >= 1) {
          state = ChickenState.formation;
          t = 0;
        }
        break;
      case ChickenState.formation:
        position.setValues(
          home.x + math.sin(game.elapsed * 1.5 + flap) * 12,
          home.y + game.driftY + math.sin(game.elapsed * 2.1 + flap) * 6,
        );
        angle = math.sin(game.elapsed * 1.8 + flap) * 0.05;
        eggTimer -= dt;
        if (eggTimer <= 0) {
          eggTimer = math.max(4.0, 14.0 - game.wave * 0.6) *
              (0.7 + game.rng.nextDouble());
          if (game.wave >= 3 &&
              position.y < game.size.y * 0.5 &&
              game.eggCount < 26) {
            game.dropEgg(position + Vector2(0, radius * 0.7), aimed: true);
          }
        }
        break;
      case ChickenState.diving:
        diveT += dt / 1.85;
        final k = clampD(diveT, 0, 1);
        final p0 = diveStart;
        final p1 = Vector2(
          diveStart.x + diveDir * game.size.x * 0.17,
          diveStart.y + 90,
        );
        final p2 = Vector2(
          diveTarget.x - diveDir * game.size.x * 0.22,
          diveTarget.y - 120,
        );
        final p3 = diveTarget;
        final u = 1 - k;
        position.setValues(
          u * u * u * p0.x + 3 * u * u * k * p1.x + 3 * u * k * k * p2.x + k * k * k * p3.x,
          u * u * u * p0.y + 3 * u * u * k * p1.y + 3 * u * k * k * p2.y + k * k * k * p3.y,
        );
        angle = math.sin(k * math.pi) * diveDir * 0.35;
        if (eggsDropped < eggsToDrop && k > 0.45) {
          eggsDropped++;
          game.dropEgg(position, aimed: true, speedBoost: 40);
        }
        if (k >= 1) {
          state = ChickenState.returning;
          t = 0;
          angle = 0;
        }
        break;
      case ChickenState.returning:
        t += dt / 0.9;
        final k = clampD(t, 0, 1);
        position.setValues(
          diveTarget.x + (home.x - diveTarget.x) * k,
          diveTarget.y + (home.y - diveTarget.y) * k,
        );
        if (k >= 1) {
          state = ChickenState.formation;
          t = 0;
        }
        break;
    }
  }
}

// ----------------------------------------------------------------------- boss
class MotherHen extends SpriteAnimationComponent
    with HasGameReference<ChickenFightGame> {
  MotherHen({required this.assets, required this.hp})
    : super(size: Vector2.all(200), anchor: Anchor.center);

  final GameAssets assets;
  double hp;
  late double maxHp;
  double t = 0;
  double hitFlash = 0;
  double attackTimer = 1.6;
  double spawnTimer = 5;
  bool dying = false;
  double dyingT = 0;
  FxSprite? _damaged;

  @override
  Future<void> onLoad() async {
    maxHp = hp;
    animation = assets.boss;
    _damaged = FxSprite(
      sprite: assets.bossDamaged,
      size: size.clone(),
      anchor: Anchor.center,
      paint: Paint()..color = const Color(0xE6FFFFFF),
    )..isVisible = false;
    add(_damaged!);
    position = Vector2(game.size.x / 2, game.size.y * 0.30);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hitFlash > 0) hitFlash = math.max(0, hitFlash - dt * 4);
    _damaged?.isVisible = hp / maxHp < 0.45;

    if (dying) {
      dyingT += dt;
      position.y += 10 * dt;
      angle += dt * 0.5;
      if (game.rng.nextDouble() < dt * 9) {
        game.spawnExplosion(
          position +
              Vector2(
                (game.rng.nextDouble() - 0.5) * 160,
                (game.rng.nextDouble() - 0.5) * 140,
              ),
          26,
          feathers: true,
        );
      }
      if (dyingT > 1.5) {
        if (game.boss == this) game.boss = null;
        removeFromParent();
      }
      return;
    }

    t += dt;
    position.setValues(
      game.size.x / 2 + math.sin(t * 0.62) * game.size.x * 0.24,
      game.size.y * 0.30 + math.sin(t * 1.4) * 10,
    );
    angle = math.sin(t * 0.62 + math.pi / 2) * 0.12;

    attackTimer -= dt;
    if (attackTimer <= 0) {
      game.bossVolley(this);
      attackTimer = math.max(0.9, 1.9 - game.wave * 0.05);
    }
    spawnTimer -= dt;
    if (spawnTimer <= 0) {
      spawnTimer = 7;
      game.bossSpawnChicks(this);
    }
  }
}

// ------------------------------------------------------------------------ fx
class ExplosionFx extends SpriteAnimationComponent
    with HasGameReference<ChickenFightGame> {
  ExplosionFx({
    required SpriteAnimation animation,
    required Vector2 position,
    required double size,
    this.life = 0.55,
  }) : super(
         animation: animation,
         size: Vector2.all(size),
         anchor: Anchor.center,
         position: position,
       );

  final double life;
  double _t = 0;

  @override
  Future<void> onLoad() async {
    animation?.loop = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= life) removeFromParent();
  }
}

class FloatText extends TextComponent with HasGameReference<ChickenFightGame> {
  FloatText({
    required super.text,
    required super.position,
    required this.color,
    required this.fontSize,
    this.life = 0.85,
  }) : super(anchor: Anchor.center);

  final Color color;
  final double fontSize;
  double life;
  final double maxLife = 0.85;

  @override
  Future<void> onLoad() async {
    textRenderer = TextPaint(
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: color,
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
      ),
    );
  }

  @override
  void update(double dt) {
    life -= dt;
    position.y -= 34 * dt;
    opacity = clampD(life / maxLife, 0, 1);
    if (life <= 0) removeFromParent();
  }
}
