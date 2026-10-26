import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Whether the launch intro plays. Tests turn it off unless they are about the intro.
bool launchIntroEnabled = true;

const _seenKey = 'nn:introSeen';

/// The coin's size, and how far above the middle of the screen it sits.
const _d = 138.0;
const _lift = 60.0;

/// The people colours of the six coins that swirl in, then the accent and highlight.
const _people = [
  Color(0xFF0F766E),
  Color(0xFFC2410C),
  Color(0xFFB4235F),
  Color(0xFF1D4ED8),
];
const _swirlSizes = [16.0, 22.0, 18.0, 24.0, 20.0, 17.0];

/// How the intro ends: the coin grows over the screen, then its halves slide apart like doors.
class _Doors {
  const _Doors({
    required this.grow,
    required this.slideAt,
    required this.slide,
    required this.fadeAt,
    required this.fade,
  });
  final int grow;
  final int slideAt;
  final int slide;
  final int fadeAt;
  final int fade;
  int get total => math.max(slideAt + slide, fadeAt + fade);
}

const _fullDoors = _Doors(
  grow: 480,
  slideAt: 420,
  slide: 560,
  fadeAt: 380,
  fade: 240,
);
const _shortDoors = _Doors(
  grow: 280,
  slideAt: 200,
  slide: 300,
  fadeAt: 160,
  fade: 180,
);

/// Story lengths before the doors open.
const _fullStory = 3700;
const _shortStory = 480;

enum _Phase { waiting, story, doors, still, done }

double _seg(double m, double a, double b) =>
    ((m - a) / (b - a)).clamp(0.0, 1.0);

/// The launch intro, a short story about splitting fairly, over the app (which is already built
/// underneath from the first frame). The first launch plays it in full (about 4.7 s); later cold
/// starts play a short version (under 1 s): the coin snaps shut and the doors open. Tapping
/// anywhere, or Skip, goes straight to the doors. With Reduce Motion it is a still coin that fades
/// into the app; with a screen reader on there is no intro at all. The coin is the brand mark and
/// never mirrors; the words follow the language.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child});
  final Widget child;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with TickerProviderStateMixin {
  late final AnimationController _story = AnimationController(vsync: this);
  late final AnimationController _doors = AnimationController(vsync: this);
  late final AnimationController _fade = AnimationController(vsync: this);
  _Phase _phase = launchIntroEnabled ? _Phase.waiting : _Phase.done;
  bool _full = true;
  double _last = 0;

  int get _storyMs => _full ? _fullStory : _shortStory;
  _Doors get _doorTimes => _full ? _fullDoors : _shortDoors;

  @override
  void initState() {
    super.initState();
    _story
      ..addListener(_beats)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _openDoors();
      });
    _doors.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _fade.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    if (_phase == _Phase.waiting) _decide();
  }

  Future<void> _decide() async {
    final store = SessionScope.read(context).store;
    final seen = await store.read(_seenKey) != null;
    if (!mounted || _phase != _Phase.waiting) return;
    if (MediaQuery.accessibleNavigationOf(context)) return _finish();
    _full = !seen;
    if (_full) unawaited(store.write(_seenKey, '1'));
    if (reduceMotion(context)) {
      // A still coin, then a cross-fade into the app.
      final hold = _full ? 500 : 150;
      _fade.duration = Duration(milliseconds: hold + 300);
      setState(() => _phase = _Phase.still);
      _fade.forward();
      return;
    }
    _story.duration = Duration(milliseconds: _storyMs);
    setState(() => _phase = _Phase.story);
    _story.forward();
  }

  /// The haptics that go with the story: a light tap when the coin appears (or, in the short
  /// version, when it snaps shut) and a firm one when the halves snap back together.
  void _beats() {
    final m = _story.value * _storyMs;
    bool passed(double at) => _last < at && m >= at;
    if (_full) {
      if (passed(880)) haptic(Haptic.light);
      if (passed(2520)) haptic(Haptic.medium);
    } else {
      if (passed(340)) haptic(Haptic.light);
    }
    _last = m;
  }

  void _openDoors() {
    if (!mounted || _phase != _Phase.story) return;
    _story.stop();
    _doors.duration = Duration(milliseconds: _doorTimes.total);
    setState(() => _phase = _Phase.doors);
    _doors.forward(from: 0);
  }

  void _skip() {
    switch (_phase) {
      case _Phase.story:
        _openDoors();
      case _Phase.waiting:
        _finish();
      case _Phase.still:
        _fade.value = math.max(_fade.value, 1 - 300 / _fadeTotal);
        _fade.forward();
      case _Phase.doors || _Phase.done:
        break;
    }
  }

  double get _fadeTotal => (_fade.duration ?? const Duration(milliseconds: 300))
      .inMilliseconds
      .toDouble();

  void _finish() {
    if (!mounted || _phase == _Phase.done) return;
    _story.stop();
    setState(() => _phase = _Phase.done);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phase != _Phase.done && MediaQuery.accessibleNavigationOf(context)) {
      // Screen readers go straight to the app.
      _phase = _Phase.done;
      _story.stop();
    }
  }

  @override
  void dispose() {
    _story.dispose();
    _doors.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app stays in the same place in the tree throughout, so it never rebuilds from scratch.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_phase != _Phase.done)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_story, _doors, _fade]),
              builder: (context, _) => _overlay(context),
            ),
          ),
      ],
    );
  }

  Widget _overlay(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final s = context.s;
    final pad = MediaQuery.paddingOf(context);
    final doors = _phase == _Phase.doors;
    final still = _phase == _Phase.still;
    final m = switch (_phase) {
      _Phase.story => _story.value * _storyMs,
      // Skipped or finished: everything as it is at the end of the story.
      _Phase.doors || _Phase.still => _full ? 3600.0 : _shortStory.toDouble(),
      _ => 0.0,
    };
    final d = doors ? _doors.value * _doorTimes.total : 0.0;
    final t = _doorTimes;

    // Fading out: the doors' background, or the whole thing with Reduce Motion.
    final fadeIn = _fadeTotal;
    final bgOpacity = doors
        ? 1 - _seg(d, t.fadeAt.toDouble(), (t.fadeAt + t.fade).toDouble())
        : 1.0;
    final allOpacity = still
        ? 1 - _seg(_fade.value * fadeIn, fadeIn - 300, fadeIn)
        : 1.0;
    // Words, glow and rings leave as the doors start.
    final extras = doors ? 1 - _seg(d, 0, 150) : 1.0;

    final overlay = LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final c = Offset(size.width / 2, size.height / 2 - _lift);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: bgOpacity,
                child: ColoredBox(color: p.bg, child: const Ambient()),
              ),
            ),
            if (!still && _full && m < 900) ..._swirl(c, m, p),
            if (!still && _full && m > 840 && m < 1360) _flash(c, m),
            if (_full && (m > 2450 || still)) _glow(c, m, p, extras, still),
            if (!still && _full) ..._rings(c, m, p, extras),
            _coin(context, c, size, m, d, doors, still),
            if (_full && !still && m > 1880 && m < 2500) _middle(c, m, p),
            if (_full && _phase != _Phase.waiting)
              _wordmark(context, c, m, extras, still),
            if (_full && _phase != _Phase.waiting)
              _tagline(context, c, m, extras, still),
            if (!doors)
              PositionedDirectional(
                top: pad.top + NNSpace.xs,
                end: NNSpace.md,
                child: Opacity(
                  opacity: still ? 1 : _seg(m, 0, 250),
                  child: _SkipButton(label: s.introSkip, onTap: _skip),
                ),
              ),
          ],
        );
      },
    );

    return IgnorePointer(
      // The doors are already opening: let taps reach the app.
      ignoring: doors,
      child: Opacity(
        opacity: allOpacity,
        child: GestureDetector(
          key: const ValueKey('intro'),
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: overlay,
        ),
      ),
    );
  }

  /// Six small coins, one per person, spiral in from far out and vanish into the middle.
  List<Widget> _swirl(Offset c, double m, NNPalette p) {
    final e = Curves.easeInCubic.transform(_seg(m, 0, 900));
    final colors = [..._people, p.accent, p.highlight];
    return [
      for (var i = 0; i < 6; i++)
        () {
          final angle = (i * 60 + 320 * e) * math.pi / 180;
          final r = 250 * (1 - e);
          final at = c + Offset(math.cos(angle), math.sin(angle)) * r;
          final size = _swirlSizes[i] * ui.lerpDouble(1.15, 0.25, e)!;
          final opacity = _seg(m, 0, 120) * (1 - _seg(m, 720, 900));
          return Positioned(
            left: at.dx - size / 2,
            top: at.dy - size / 2,
            child: Opacity(
              opacity: opacity,
              child: _MiniCoin(color: colors[i], size: size),
            ),
          );
        }(),
    ];
  }

  /// A white flash where the coins meet.
  Widget _flash(Offset c, double m) {
    final u = _seg(m, 840, 1360);
    final scale = ui.lerpDouble(0.2, 2.2, Curves.easeOutCubic.transform(u))!;
    final opacity = u < 0.3 ? u / 0.3 : 1 - (u - 0.3) / 0.7;
    final r = _d / 2 * scale;
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: opacity),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A soft saffron-to-indigo glow that swells behind the coin once it is whole again.
  Widget _glow(Offset c, double m, NNPalette p, double extras, bool still) {
    final g = still ? 1.0 : Curves.easeOutCubic.transform(_seg(m, 2450, 3000));
    final r = _d * 0.95 * ui.lerpDouble(0.5, 1.6, g)!;
    final a = 0.5 * g * extras;
    return Positioned(
      left: c.dx - r,
      top: c.dy - r,
      child: Container(
        width: r * 2,
        height: r * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              p.highlight.withValues(alpha: a),
              p.accent.withValues(alpha: a * 0.55),
              p.accent.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }

  /// Two rings, indigo then saffron, that spread from the coin and fade.
  List<Widget> _rings(Offset c, double m, NNPalette p, double extras) => [
    for (final (start, color) in [(2470.0, p.accent), (2590.0, p.highlight)])
      if (m > start && m < start + 800)
        () {
          final r = _seg(m, start, start + 800);
          final size =
              _d * ui.lerpDouble(1, 2.7, Curves.easeOutCubic.transform(r))!;
          return Positioned(
            left: c.dx - size / 2,
            top: c.dy - size / 2,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.9 * (1 - r) * extras),
                  width: 2,
                ),
              ),
            ),
          );
        }(),
  ];

  /// The coin: pops in, flips, draws its middle line, splits and snaps back, catches the light;
  /// in the doors it grows over the screen and its halves slide apart.
  Widget _coin(
    BuildContext context,
    Offset c,
    Size screen,
    double m,
    double d,
    bool doors,
    bool still,
  ) {
    var scale = 1.0;
    var flip = 0.0;
    var split = 0.0;
    var line = 0.0;
    var lineOpacity = 0.0;
    var band = -1.0;
    if (!still && !doors) {
      if (_full) {
        if (m < 880) {
          scale = 0;
        } else if (m < 1130) {
          scale = 1.12 * Curves.easeOutCubic.transform(_seg(m, 880, 1130));
        } else {
          scale = ui.lerpDouble(
            1.12,
            1,
            Curves.easeInOut.transform(_seg(m, 1130, 1260)),
          )!;
        }
        flip =
            2 * math.pi * Curves.easeInOutCubic.transform(_seg(m, 1180, 1740));
        if (m > 1640 && m < 1940) {
          line = Curves.easeOutCubic.transform(_seg(m, 1640, 1840));
          lineOpacity = 1 - _seg(m, 1840, 1940);
        }
        if (m < 1780) {
          split = 0;
        } else if (m < 2420) {
          split = 74 * Curves.easeOutCubic.transform(_seg(m, 1780, 2060));
        } else if (m < 2520) {
          split = 74 * (1 - Curves.easeInCubic.transform(_seg(m, 2420, 2520)));
        } else if (m < 2560) {
          split = -4 * Curves.easeOutCubic.transform(_seg(m, 2520, 2560));
        } else {
          split = -4 * (1 - Curves.easeInOut.transform(_seg(m, 2560, 2600)));
        }
        if (m > 2560 && m < 3180) {
          band = Curves.easeInOut.transform(_seg(m, 2560, 3180));
        }
      } else {
        scale = Curves.easeOutBack.transform(_seg(m, 0, 200));
        split = m < 180
            ? 10
            : 10 * (1 - Curves.easeOutBack.transform(_seg(m, 180, 480)));
      }
    }

    // Doors: the coin grows until it covers the screen, then the halves slide off.
    var apart = 0.0;
    if (doors) {
      final t = _doorTimes;
      final far = [
        c,
        Offset(screen.width - c.dx, c.dy),
        Offset(c.dx, screen.height - c.dy),
        Offset(screen.width - c.dx, screen.height - c.dy),
      ].map((o) => o.distance).reduce(math.max);
      final cover = 2 * far / _d * 1.04;
      scale = ui.lerpDouble(
        1,
        cover,
        Curves.easeInCubic.transform(_seg(d, 0, t.grow.toDouble())),
      )!;
      apart =
          (screen.width / 2 + 8) *
          Curves.easeInOutCubic.transform(
            _seg(d, t.slideAt.toDouble(), (t.slideAt + t.slide).toDouble()),
          );
    }

    // Not there yet.
    if (scale <= 0.001) return const SizedBox.shrink();
    final tilt = 6 * math.pi / 180 * (split / 74);
    Widget half(bool left) {
      final dir = left ? -1.0 : 1.0;
      return Transform(
        alignment: Alignment.center,
        // The coin is scaled as a whole; the doors slide in screen points.
        transform: Matrix4.translationValues(
          dir * (split + (apart == 0 ? 0 : apart / scale)),
          0,
          0,
        )..rotateZ(-dir * tilt),
        child: CoinHalf(left: left, size: _d),
      );
    }

    Widget coin = SizedBox.square(
      dimension: _d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          half(true),
          half(false),
          if (lineOpacity > 0)
            Positioned.fill(
              child: CustomPaint(painter: _MiddleLine(line, lineOpacity)),
            ),
          if (band >= 0)
            Positioned.fill(
              child: ClipOval(child: CustomPaint(painter: _LightBand(band))),
            ),
        ],
      ),
    );
    if (flip > 0 && flip < 2 * math.pi) {
      // Seen from behind half way through the turn, the coin still shows its face.
      final behind = math.cos(flip) < 0;
      coin = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(flip),
        child: behind ? Transform.flip(flipX: true, child: coin) : coin,
      );
    }
    coin = Transform.scale(scale: scale, child: coin);
    return Positioned(
      left: c.dx - _d / 2,
      top: c.dy - _d / 2,
      child: KeyedSubtree(
        key: ValueKey(doors ? 'intro-doors' : 'intro-coin'),
        child: coin,
      ),
    );
  }

  /// "نص نص" between the parted halves: half and half, in the brand's own words.
  Widget _middle(Offset c, double m, NNPalette p) {
    final inn = Curves.easeOutCubic.transform(_seg(m, 1880, 2100));
    final out = _seg(m, 2420, 2500);
    return Positioned(
      left: c.dx - 70,
      top: c.dy - 22,
      width: 140,
      height: 44,
      child: Opacity(
        opacity: inn * (1 - out),
        child: Transform.scale(
          scale: ui.lerpDouble(0.7, 1, inn)!,
          child: Center(
            child: Text(
              'نص نص',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'ReadexPro',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: p.text,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "NussNuss", one letter at a time, each rising with a little overshoot.
  Widget _wordmark(
    BuildContext context,
    Offset c,
    double m,
    double extras,
    bool still,
  ) {
    final p = NNTheme.of(context).palette;
    final deep = NNTheme.of(context).isDark ? p.accent : p.onAccentSoft;
    const word = 'NussNuss';
    return Positioned(
      left: 0,
      right: 0,
      top: c.dy + _d / 2 + 36,
      child: Opacity(
        opacity: extras,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            key: const ValueKey('intro-wordmark'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < word.length; i++)
                () {
                  final at = 2560.0 + 45 * i;
                  final rise = still
                      ? 1.0
                      : Curves.easeOutBack.transform(_seg(m, at, at + 420));
                  return Opacity(
                    opacity: still ? 1 : _seg(m, at, at + 180),
                    child: Transform.translate(
                      offset: Offset(0, 22 * (1 - rise)),
                      child: Text(
                        word[i],
                        style: TextStyle(
                          fontFamily: 'ReadexPro',
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: i < 4 ? deep : p.text,
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }

  /// "Split it fair." (or its Arabic), rising under the name.
  Widget _tagline(
    BuildContext context,
    Offset c,
    double m,
    double extras,
    bool still,
  ) {
    final p = NNTheme.of(context).palette;
    final q = still ? 1.0 : _seg(m, 3050, 3450);
    return Positioned(
      left: NNSpace.xl,
      right: NNSpace.xl,
      top: c.dy + _d / 2 + 36 + 56,
      child: Opacity(
        opacity: q * extras,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - Curves.easeOutCubic.transform(q))),
          child: Text(
            context.s.welcomeTitle,
            textAlign: TextAlign.center,
            style: NNType.title3.copyWith(color: p.text2),
          ),
        ),
      ),
    );
  }
}

/// A small coin in one person's colour, with a light rim.
class _MiniCoin extends StatelessWidget {
  const _MiniCoin({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.35),
        width: math.max(1, size * 0.08),
      ),
    ),
  );
}

/// The white line down the middle of the coin, drawn from top to bottom.
class _MiddleLine extends CustomPainter {
  _MiddleLine(this.progress, this.opacity);
  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    canvas.drawLine(
      Offset(x, size.height * 0.04),
      Offset(x, size.height * (0.04 + 0.92 * progress)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * opacity)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MiddleLine old) =>
      old.progress != progress || old.opacity != opacity;
}

/// A slanted band of light that sweeps across the coin (clipped to the circle by the caller).
class _LightBand extends CustomPainter {
  _LightBand(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final x = ui.lerpDouble(-0.5, 1.5, t)! * size.width;
    final w = size.width * 0.32;
    final strength = math.sin(math.pi * t);
    canvas
      ..save()
      ..translate(x, size.height / 2)
      ..rotate(-0.35)
      ..drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: size.height * 2),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(-w / 2, 0),
            Offset(w / 2, 0),
            [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.5 * strength),
              Colors.white.withValues(alpha: 0),
            ],
            const [0, 0.5, 1],
          ),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_LightBand old) => old.t != t;
}

/// Skip: a small glass capsule at the top trailing corner.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      key: const ValueKey('intro-skip'),
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      haptic: Haptic.light,
      scale: NNMotion.glassPressScale,
      child: Glass(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: touchTarget(context),
            minWidth: touchTarget(context) + 24,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: NNType.subhead.copyWith(
                  color: p.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
