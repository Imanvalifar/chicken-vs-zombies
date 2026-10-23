import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

/// Loads every sprite once through Flame's image cache and builds the
/// [SpriteAnimation]s used by the components.
class GameAssets {
  late final SpriteAnimation ship1;
  late final SpriteAnimation ship2;
  late final SpriteAnimation ship3;
  late final SpriteAnimation chickenGrunt;
  late final SpriteAnimation chickenKamikaze;
  late final SpriteAnimation chickenArmored;
  late final SpriteAnimation chickenUfo;
  late final SpriteAnimation boss;
  late final SpriteAnimation explosion;
  late final SpriteAnimation feathers;

  late final Sprite shield;
  late final Sprite bolt;
  late final Sprite egg;
  late final Sprite muzzle;
  late final Sprite bossDamaged;
  late final Sprite heroShip;
  late final Sprite glow;

  late final Sprite pickupDrumstick;
  late final Sprite pickupBrain;
  late final Sprite pickupMutagen;
  late final Sprite pickupNuke;

  late final Sprite background;
  late final Sprite hudBarFrame;
  late final Sprite hudBossFill;

  bool ready = false;

  // Flame's image cache already prefixes 'assets/images/', so paths here are
  // relative to that folder.
  Future<ui.Image> _image(String path) => Flame.images.load(path);

  Future<Sprite> _sprite(String path) async => Sprite(await _image(path));

  Future<SpriteAnimation> _sheet(
    String path,
    int frames,
    double step,
    double textureSize,
  ) async {
    final image = await _image(path);
    return SpriteAnimation.fromFrameData(
      image,
      SpriteAnimationData.sequenced(
        amount: frames,
        stepTime: step,
        textureSize: Vector2.all(textureSize),
      ),
    );
  }

  Future<void> load() async {
    ship1 = await _sheet('ships/zombie_ship_tier1_sheet.png', 4, 0.11, 256);
    ship2 = await _sheet('ships/zombie_ship_tier2_sheet.png', 4, 0.11, 256);
    ship3 = await _sheet('ships/zombie_ship_tier3_sheet.png', 4, 0.11, 256);
    chickenGrunt = await _sheet('enemies/chicken_grunt_sheet.png', 4, 0.16, 192);
    chickenKamikaze = await _sheet(
      'enemies/chicken_kamikaze_sheet.png',
      4,
      0.16,
      192,
    );
    chickenArmored = await _sheet(
      'enemies/chicken_armored_sheet.png',
      4,
      0.16,
      192,
    );
    chickenUfo = await _sheet('enemies/chicken_ufo_sheet.png', 4, 0.16, 192);
    boss = await _sheet('enemies/boss_mother_hen_sheet.png', 4, 0.18, 512);
    explosion = await _sheet(
      'vfx/vfx_toxic_explosion_sheet.png',
      8,
      0.062,
      192,
    );
    feathers = await _sheet(
      'vfx/vfx_feather_burst_sheet.png',
      8,
      0.07,
      192,
    );

    shield = await _sprite('ships/zombie_shield_bubble.png');
    bolt = await _sprite('projectiles/fire_necro_bolt.png');
    egg = await _sprite('projectiles/enemy_egg_bomb.png');
    muzzle = await _sprite('vfx/vfx_muzzle_flash.png');
    bossDamaged = await _sprite('enemies/boss_mother_hen_damaged.png');
    heroShip = await _sprite('ships/zombie_ship_hero_ai_512.png');
    glow = await _sprite('vfx/glow_toxic.png');

    pickupDrumstick = await _sprite('pickups/pickup_roasted_drumstick.png');
    pickupBrain = await _sprite('pickups/pickup_golden_brain.png');
    pickupMutagen = await _sprite('pickups/pickup_mutagen_canister.png');
    pickupNuke = await _sprite('pickups/pickup_nuke_skull.png');

    background = await _sprite('backgrounds/bg_space_baked.png');
    hudBarFrame = await _sprite('ui/hud_health_bar_frame.png');
    hudBossFill = await _sprite('ui/hud_boss_bar_fill.png');
    ready = true;
  }
}
