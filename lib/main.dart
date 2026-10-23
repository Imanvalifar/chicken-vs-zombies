import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flame/game.dart';

import 'flame/game.dart';
import 'game/audio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Full-screen landscape: this is a side-scrolling shooter.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ChickenApp());
}

class ChickenApp extends StatelessWidget {
  const ChickenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken vs Zombies',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060F),
        fontFamily: 'Roboto',
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late final GameAudio _audio;
  late final ChickenFightGame _game;
  final FocusNode _focus = FocusNode(debugLabel: 'game');

  @override
  void initState() {
    super.initState();
    _audio = GameAudio();
    _game = ChickenFightGame(_audio);
    _game.phase.addListener(_onPhaseChanged);
    _audio.init();
    WidgetsBinding.instance.addObserver(this);
  }

  void _onPhaseChanged() {
    final p = _game.phase.value;
    if (p == GamePhase.playing) {
      _audio.startMusic();
      _audio.setMusicPaused(false);
    } else {
      _audio.setMusicPaused(true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _game.phase.value == GamePhase.playing) {
      _game.togglePause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.phase.removeListener(_onPhaseChanged);
    _audio.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    final down = event is KeyDownEvent;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _game.setKey(left: down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _game.setKey(right: down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _game.setKey(up: down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _game.setKey(down: down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.controlLeft) {
      _game.setKey(fire: down);
      return KeyEventResult.handled;
    }
    if (down &&
        (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.escape)) {
      _game.togglePause();
      return KeyEventResult.handled;
    }
    if (down &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      if (_game.phase.value == GamePhase.menu ||
          _game.phase.value == GamePhase.gameOver) {
        _start();
      }
      return KeyEventResult.handled;
    }
    if (down && key == LogicalKeyboardKey.keyR) {
      if (_game.phase.value == GamePhase.gameOver) _start();
      return KeyEventResult.handled;
    }
    if (down && key == LogicalKeyboardKey.keyM) {
      _audio.enabled = !_audio.enabled;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _start() {
    _audio.startMusic();
    _game.setKey(
      left: false,
      right: false,
      up: false,
      down: false,
      fire: false,
    );
    _game.pointerUp();
    _game.startGame();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final phase = _game.phase.value;
        if (phase == GamePhase.playing) {
          _game.togglePause();
        } else if (phase == GamePhase.paused) {
          _game.backToMenu();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            _game.safe = MediaQuery.of(context).padding;
            _game.touchMode = _isTouchPlatform(context);
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                // taps on the bomb / pause cluster must not fire the gun
                final controls = Rect.fromLTWH(
                  size.width - 84 - _game.safe.right,
                  size.height - 140 - _game.safe.bottom,
                  84,
                  140,
                );
                if (controls.contains(e.localPosition)) return;
                _focus.requestFocus();
                _game.pointerDown(
                  e.localPosition.dx,
                  e.localPosition.dy,
                  relative: e.kind == PointerDeviceKind.touch,
                );
              },
              onPointerMove: (e) => _game.pointerMove(
                e.localPosition.dx,
                e.localPosition.dy,
                relative: e.kind == PointerDeviceKind.touch,
              ),
              onPointerUp: (e) => _game.pointerUp(),
              onPointerCancel: (e) => _game.pointerUp(),
              child: Focus(
                focusNode: _focus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GameWidget<ChickenFightGame>(
                      game: _game,
                      loadingBuilder: (context) => const _LoadingOverlay(),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([_game.phase, _game.assetsReady]),
                      builder: (context, _) {
                        final phase = _game.phase.value;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (phase == GamePhase.menu && _game.art.ready)
                              _MenuOverlay(game: _game, onStart: _start),
                            if (phase == GamePhase.paused)
                              _PauseOverlay(
                                onResume: () {
                                  _game.togglePause();
                                  _focus.requestFocus();
                                },
                                onQuit: () => _game.backToMenu(),
                              ),
                            if (phase == GamePhase.playing)
                              Positioned(
                                right: 12 + _game.safe.right,
                                bottom: 12 + _game.safe.bottom,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ValueListenableBuilder<int>(
                                      valueListenable: _game.bombs,
                                      builder: (context, count, _) =>
                                          _BombButton(
                                            count: count,
                                            onTap: _game.useBomb,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    _PauseButton(
                                      onTap: () => _game.togglePause(),
                                    ),
                                  ],
                                ),
                              ),
                            if (phase == GamePhase.gameOver)
                              _GameOverOverlay(
                                game: _game,
                                onRetry: _start,
                                onMenu: () => _game.backToMenu(),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatefulWidget {
  const _LoadingOverlay();

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay> {
  ui.Image? _splash;

  @override
  void initState() {
    super.initState();
    // Decode the banner ourselves and paint it with RawImage: drawing it
    // through Image.asset composited it over a light window and washed it out.
    rootBundle
        .load('assets/images/concept_art/splash_banner_zombies_vs_chickens.png')
        .then((data) async {
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          final frame = await codec.getNextFrame();
          if (mounted) setState(() => _splash = frame.image);
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF05070F),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_splash != null)
            RawImage(
              image: _splash,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: SizedBox(
                width: 210,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF8CFF5A)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonButton extends StatefulWidget {
  const _NeonButton({
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF5FF0FF),
    this.width = 260,
    this.height = 56,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final double width;
  final double height;
  final double fontSize;

  @override
  State<_NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<_NeonButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: widget.width,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.withValues(alpha: _hover ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.9), width: 1.6),
            boxShadow: [
              BoxShadow(
                color: c.withValues(alpha: _hover ? 0.55 : 0.25),
                blurRadius: _hover ? 26 : 14,
                spreadRadius: _hover ? 3 : 0,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              shadows: [Shadow(color: c, blurRadius: 12)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {required this.color, required this.size});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size,
        height: 0.95,
        fontWeight: FontWeight.w900,
        letterSpacing: size * 0.12,
        color: Colors.white,
        shadows: [
          Shadow(color: color, blurRadius: 18),
          Shadow(color: color.withValues(alpha: 0.7), blurRadius: 42),
          const Shadow(
            color: Color(0xAA000000),
            offset: Offset(0, 4),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

// =================================================================== menu

bool _isTouchPlatform(BuildContext context) {
  final p = Theme.of(context).platform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

class _MenuOverlay extends StatefulWidget {
  const _MenuOverlay({required this.game, required this.onStart});

  final ChickenFightGame game;
  final VoidCallback onStart;

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = _isTouchPlatform(context);
    return Container(
      color: const Color(0xFF05060F).withValues(alpha: 0.55),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 900,
            height: 500,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  height: 150,
                  child: CustomPaint(
                    painter: ShipPortrait(
                      animation: _c,
                      image: widget.game.art.heroShip.image,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Title('CHICKEN', color: const Color(0xFF8CFF5A), size: 52),
                _Title('VS ZOMBIES', color: const Color(0xFFFF5A6E), size: 40),
                const SizedBox(height: 12),
                Text(
                  'THE UNDEAD SHIP IS THE LAST LINE OF DEFENCE.\nSHOOT THE COSMIC HEN SWARM BEFORE THEY SCRAMBLE YOU.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2.2,
                    height: 1.8,
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                _NeonButton(
                  label: 'START GAME',
                  onTap: widget.onStart,
                  fontSize: 20,
                  color: const Color(0xFF8CFF5A),
                ),
                const SizedBox(height: 22),
                if (touch)
                  const Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 22,
                    children: [
                      _Hint('DRAG', 'MOVE ANY WAY'),
                      _Hint('TOUCH', 'FIRE'),
                      _Hint('BACK', 'PAUSE'),
                    ],
                  )
                else
                  const Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 20,
                    children: [
                      _Hint('WASD', 'MOVE'),
                      _Hint('SPACE', 'FIRE'),
                      _Hint('MOUSE', 'AIM & FIRE'),
                      _Hint('P', 'PAUSE'),
                    ],
                  ),
                const SizedBox(height: 16),
                if (widget.game.best > 0)
                  Text(
                    'BEST  ${widget.game.best}',
                    style: const TextStyle(
                      color: Color(0xFFFFD166),
                      fontSize: 13,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.keys, this.action);

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Text(
            keys,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.6,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          action,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 2,
            color: Colors.white.withValues(alpha: 0.45),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ================================================================== pause

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onQuit});

  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Title('PAUSED', color: Color(0xFF5FF0FF), size: 44),
            const SizedBox(height: 30),
            _NeonButton(
              label: 'RESUME',
              onTap: onResume,
              width: 220,
              height: 50,
            ),
            const SizedBox(height: 14),
            _NeonButton(
              label: 'QUIT TO MENU',
              onTap: onQuit,
              color: const Color(0xFFFF6B81),
              width: 220,
              height: 50,
              fontSize: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================== game over

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.game,
    required this.onRetry,
    required this.onMenu,
  });

  final ChickenFightGame game;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final best = math.max(game.best, game.score);
    final touch = _isTouchPlatform(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.68),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 620,
            height: 420,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _Title('GAME OVER', color: Color(0xFFFF4D6D), size: 44),
                const SizedBox(height: 18),
                Text(
                  'THE HENS GOT YOU',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    letterSpacing: 4,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Stat('SCORE', game.score.toString()),
                    const SizedBox(width: 32),
                    _Stat('WAVE', game.wave.toString()),
                    const SizedBox(width: 32),
                    _Stat('BEST', best.toString(), highlight: true),
                  ],
                ),
                const SizedBox(height: 30),
                _NeonButton(
                  label: 'RETRY',
                  onTap: onRetry,
                  width: 220,
                  height: 52,
                ),
                const SizedBox(height: 14),
                _NeonButton(
                  label: 'MENU',
                  onTap: onMenu,
                  color: const Color(0xFF9AA7C7),
                  width: 220,
                  height: 48,
                  fontSize: 14,
                ),
                const SizedBox(height: 18),
                Text(
                  touch ? 'TAP RETRY TO PLAY AGAIN' : 'PRESS  R  TO RETRY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BombButton extends StatelessWidget {
  const _BombButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: count > 0 ? 1 : 0.3,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/ui/ui_btn_bomb.png',
                  filterQuality: FilterQuality.medium,
                ),
              ),
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A45),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.38),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Image.asset(
            'assets/images/ui/ui_btn_pause.png',
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 3,
            color: Colors.white.withValues(alpha: 0.45),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: highlight ? const Color(0xFFFFD166) : Colors.white,
            shadows: [
              Shadow(
                color:
                    (highlight
                            ? const Color(0xFFFFD166)
                            : const Color(0xFF5FF0FF))
                        .withValues(alpha: 0.7),
                blurRadius: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================ menu hen art

class ShipPortrait extends CustomPainter {
  ShipPortrait({required this.animation, required this.image})
    : super(repaint: animation);

  final Animation<double> animation;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final bob = math.sin(t) * 5;
    final w = size.height * 1.05;
    final dst = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 + bob),
      width: w,
      height: w,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2 + bob + 6),
      w * 0.42,
      Paint()
        ..color = const Color(0xFF6BFF3C).withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant ShipPortrait oldDelegate) => false;
}
