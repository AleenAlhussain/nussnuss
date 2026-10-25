import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/session.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.onScrollDirection});
  final ValueChanged<bool>? onScrollDirection;

  Future<void> _delete(BuildContext context) async {
    final session = SessionScope.read(context);
    final s = session.s;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(s.deleteAccount),
        content: Text(s.deleteAccountBody),
        actions: [
          adaptiveAction(
            ctx,
            label: s.cancel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          adaptiveAction(
            ctx,
            label: s.deleteAccountConfirm,
            destructive: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await session.deleteAccount();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.offline ? s.offline : e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    return NNPage(
      key: const ValueKey('settings'),
      title: s.settings,
      onScrollDirection: onScrollDirection,
      slivers: [
        SliverList.list(
          children: [
            if ((session.me?.name ?? '').isNotEmpty)
              NNCard(
                child: Row(
                  children: [
                    Avatar(name: session.me!.name, size: 48),
                    const SizedBox(width: NNSpace.sm),
                    Expanded(
                      child: Text(
                        session.me!.name,
                        style: NNType.title3.copyWith(color: p.text),
                      ),
                    ),
                  ],
                ),
              ),
            SectionLabel(s.language),
            Segmented<String>(
              key: const ValueKey('settings-lang'),
              values: const ['en', 'ar'],
              selected: session.lang,
              label: (l) => l == 'ar' ? 'العربية' : 'English',
              onChanged: session.setLang,
            ),
            SectionLabel(s.theme),
            Segmented<ThemePref>(
              values: ThemePref.values,
              selected: session.theme,
              label: (t) => s.raw('theme_${t.name}'),
              onChanged: session.setTheme,
            ),
            SectionLabel(s.glass),
            Segmented<GlassPref>(
              key: const ValueKey('settings-glass'),
              values: GlassPref.values,
              selected: session.glass,
              label: (g) => g == GlassPref.clear ? s.glassAuto : s.glassFrosted,
              onChanged: session.setGlass,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: NNSpace.xxs,
                top: NNSpace.xs,
              ),
              child: Text(
                s.glassHint,
                style: NNType.footnote.copyWith(color: p.text2),
              ),
            ),
            const SizedBox(height: NNSpace.xxl),
            NNButton(
              key: const ValueKey('delete-account'),
              label: s.deleteAccount,
              kind: ButtonKind.danger,
              icon: Icons.delete_outline_rounded,
              onTap: () => _delete(context),
            ),
            Padding(
              padding: const EdgeInsets.all(NNSpace.xs),
              child: Text(
                s.deleteAccountBody,
                style: NNType.footnote.copyWith(color: p.text2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A dialog button that looks native on each platform.
Widget adaptiveAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
}) {
  final p = NNTheme.of(context).palette;
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        color: destructive ? p.danger : p.accent,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
