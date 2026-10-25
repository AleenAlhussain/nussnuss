import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/extras.dart';
import '../data/api.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

/// "I have a code": a recovery code, or a code made on another device. Signs in and replaces
/// whatever account this phone had.
Future<void> showHaveCodeSheet(BuildContext context) {
  return showNNSheet<void>(
    context,
    key: const ValueKey('have-code-sheet'),
    title: context.s.haveCode,
    builder: (_) => const _HaveCode(),
  );
}

class _HaveCode extends StatefulWidget {
  const _HaveCode();

  @override
  State<_HaveCode> createState() => _HaveCodeState();
}

class _HaveCodeState extends State<_HaveCode> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final session = SessionScope.read(context);
    final s = session.s;
    if (_code.text.trim().length < 6) {
      setState(() => _error = s.codeHint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signInWithCode(_code.text);
      if (mounted) Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.offline
              ? s.offline
              : (e.status == 401 ? s.codeBad : e.message),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NNField(
          label: s.codeLabel,
          help: s.codeHint,
          error: _error,
          controller: _code,
          autofocus: true,
          maxLength: 40,
          fieldKey: const ValueKey('code'),
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('use-code'),
          label: s.buy,
          busy: _busy,
          onTap: _go,
        ),
      ],
    );
  }
}

/// Shows a code once, large and easy to copy, with what to do with it.
class _CodeBody extends StatefulWidget {
  const _CodeBody({required this.make, required this.explain});
  final Future<({String code, DateTime? expiresAt})> Function() make;
  final String explain;

  @override
  State<_CodeBody> createState() => _CodeBodyState();
}

class _CodeBodyState extends State<_CodeBody> {
  ({String code, DateTime? expiresAt})? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget
        .make()
        .then((r) {
          if (mounted) setState(() => _r = r);
        })
        .catchError((Object e) {
          if (!mounted) return;
          final s = SessionScope.read(context).s;
          setState(
            () => _error = e is ApiException && !e.offline
                ? e.message
                : s.offline,
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final r = _r;
    final time = r?.expiresAt == null
        ? null
        : TimeOfDay.fromDateTime(r!.expiresAt!).format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.explain, style: NNType.callout.copyWith(color: p.text2)),
        const SizedBox(height: NNSpace.md),
        NNCard(
          child: r == null
              ? (_error != null
                    ? Text(
                        _error!,
                        style: NNType.subhead.copyWith(color: p.danger),
                      )
                    : Skeleton(label: s.loading, child: const Bone(height: 30)))
              : SelectableText(
                  r.code,
                  key: const ValueKey('shown-code'),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: NNType.title2.copyWith(
                    color: p.text,
                    letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
        if (time != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xs),
            child: Text(
              '⏱ $time',
              textAlign: TextAlign.center,
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ),
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('copy-code'),
          label: s.copy,
          icon: Icons.copy_rounded,
          onTap: r == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: r.code));
                  haptic(Haptic.success);
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(SnackBar(content: Text(s.codeCopied)));
                },
        ),
      ],
    );
  }
}

Future<void> showRecoveryCodeSheet(BuildContext context) {
  final session = SessionScope.read(context);
  return showNNSheet<void>(
    context,
    key: const ValueKey('recovery-sheet'),
    title: session.s.recoveryCode,
    builder: (_) => _CodeBody(
      explain: session.s.recoveryShow,
      make: () async =>
          (code: await session.api.makeRecoveryCode(), expiresAt: null),
    ),
  );
}

Future<void> showLinkCodeSheet(BuildContext context) {
  final session = SessionScope.read(context);
  return showNNSheet<void>(
    context,
    key: const ValueKey('link-sheet'),
    title: session.s.linkDevice,
    builder: (_) => _CodeBody(
      explain: session.s.linkShow,
      make: () async {
        final r = await session.api.makeLinkCode();
        return (code: r.code, expiresAt: r.expiresAt);
      },
    ),
  );
}

/// Adds one way to get paid: the kind, the number, address or link, and an optional label.
Future<PayTo?> showAddPayToSheet(BuildContext context) {
  return showNNSheet<PayTo>(
    context,
    key: const ValueKey('pay-to-sheet'),
    title: context.s.payAdd,
    builder: (_) => const _AddPayTo(),
  );
}

class _AddPayTo extends StatefulWidget {
  const _AddPayTo();

  @override
  State<_AddPayTo> createState() => _AddPayToState();
}

class _AddPayToState extends State<_AddPayTo> {
  String _kind = 'iban';
  final _value = TextEditingController();
  final _label = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = SessionScope.read(context);
    final s = session.s;
    if (_value.text.trim().length < 3) {
      setState(() => _error = s.payValue);
      return;
    }
    final item = PayTo(
      _kind,
      _value.text.trim(),
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The server checks the shape (IBAN, phone, https link) and says what is wrong.
      await session.setPayTo([...?session.me?.payTo, item]);
      if (mounted) Navigator.of(context).pop(item);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            for (final k in payToKinds)
              NNChip(
                key: ValueKey('kind-$k'),
                label: s.raw('pay_$k'),
                selected: _kind == k,
                onTap: () => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: NNSpace.md),
        NNField(
          label: s.raw('pay_$_kind'),
          hint: switch (_kind) {
            'iban' => 'AE07 0331 2345 6789 0123 456',
            'instapay' => 'name@instapay',
            'stcpay' || 'phone' => '+966 5x xxx xxxx',
            'paypal' => 'paypal.me/name',
            _ => 'https://',
          },
          error: _error,
          controller: _value,
          maxLength: 120,
          fieldKey: const ValueKey('pay-value'),
        ),
        const SizedBox(height: NNSpace.sm),
        NNField(
          label: s.payLabel,
          controller: _label,
          maxLength: 40,
          fieldKey: const ValueKey('pay-label'),
        ),
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('save-pay-to'),
          label: s.save,
          busy: _busy,
          onTap: _save,
        ),
      ],
    );
  }
}
