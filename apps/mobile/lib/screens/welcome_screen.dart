import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import 'account_sheets.dart';

/// First run: the coin, one line about what this is, and your name. No sign-up, no email.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  late final AnimationController _coin = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _asking = false;
  bool _busy = false;
  String? _error;

  /// Goes up with every error: the field or message shakes, with the error haptic.
  int _shakes = 0;

  void _fail(String message) => setState(() {
    _error = message;
    _shakes++;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (reduceMotion(context)) {
        _coin.value = 0;
      } else {
        _coin.springTo(0, NNMotion.gentle);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _coin.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final session = SessionScope.read(context);
    final s = session.s;
    if (!_asking) {
      setState(() => _asking = true);
      return;
    }
    if (_name.text.trim().isEmpty) {
      _fail(s.yourNameHint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.start(_name.text);
    } on ApiException catch (e) {
      if (mounted) _fail(e.offline ? s.offline : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    return StepBack(
      child: Scaffold(
        key: const ValueKey('welcome'),
        backgroundColor: p.bg,
        body: Ambient.behind(
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                // Every part is built at once (not lazily), so with very large text the button is
                // still there to scroll to, for people and for screen readers.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(NNSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () =>
                              session.setLang(s.isRtl ? 'en' : 'ar'),
                          child: Text(
                            s.isRtl ? 'English' : 'العربية',
                            style: NNType.subhead.copyWith(
                              color: p.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: NNSpace.xl),
                      Center(
                        child: AnimatedBuilder(
                          animation: _coin,
                          builder: (_, _) => Coin(size: 96, join: _coin.value),
                        ),
                      ),
                      const SizedBox(height: NNSpace.xl),
                      Semantics(
                        header: true,
                        child: Text(
                          s.welcomeTitle,
                          textAlign: TextAlign.center,
                          style: NNType.largeTitle.copyWith(color: p.text),
                        ),
                      ),
                      const SizedBox(height: NNSpace.sm),
                      Text(
                        s.welcomeBody,
                        textAlign: TextAlign.center,
                        style: NNType.callout.copyWith(color: p.text2),
                      ),
                      const SizedBox(height: NNSpace.xl),
                      // What it does, in three short cards.
                      for (final (i, c) in [
                        (Icons.touch_app_rounded, s.welcome1T, s.welcome1B),
                        (Icons.swap_horiz_rounded, s.welcome2T, s.welcome2B),
                        (Icons.link_rounded, s.welcome3T, s.welcome3B),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(height: NNSpace.xs),
                        _Card(
                          key: ValueKey('welcome-card-${i + 1}'),
                          icon: c.$1,
                          title: c.$2,
                          body: c.$3,
                        ),
                      ],
                      const SizedBox(height: NNSpace.xl),
                      AnimatedSize(
                        duration: reduceMotion(context)
                            ? Duration.zero
                            : NNMotion.standardDuration,
                        curve: Curves.easeOutCubic,
                        child: _asking
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  bottom: NNSpace.lg,
                                ),
                                child: NNField(
                                  label: s.yourName,
                                  help: s.yourNameHint,
                                  error: _error,
                                  shake: _shakes,
                                  controller: _name,
                                  autofocus: true,
                                  maxLength: 40,
                                  fieldKey: const ValueKey('name'),
                                  textInputAction: TextInputAction.go,
                                  onSubmitted: (_) => _start(),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      NNButton(
                        key: const ValueKey('start'),
                        label: s.start,
                        busy: _busy,
                        onTap: _start,
                      ),
                      const SizedBox(height: NNSpace.xs),
                      NNButton(
                        key: const ValueKey('have-account'),
                        label: s.haveAccount,
                        kind: ButtonKind.plain,
                        onTap: _busy ? null : () => showHaveCodeSheet(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing NussNuss does: an icon, a short title and a line.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return MergeSemantics(
      child: NNCard(
        padding: const EdgeInsets.all(NNSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: BorderRadius.circular(NNRadius.control),
              ),
              child: Icon(icon, color: p.onAccentSoft, size: 22),
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NNType.headline.copyWith(color: p.text)),
                  const SizedBox(height: 2),
                  Text(body, style: NNType.footnote.copyWith(color: p.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
