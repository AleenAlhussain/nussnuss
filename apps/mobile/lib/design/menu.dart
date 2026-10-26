import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// One choice in a context menu.
class NNMenuItem {
  const NNMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  /// For the row's key: `menu-<id>`.
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Deleting: in red, last.
  final bool destructive;
}

/// A long-press menu, like iOS: the screen dims, a solid preview of what was pressed comes up with
/// the choices under it. Tapping outside closes it; a choice closes it and then runs. The press
/// that opens it plays its own haptic (Pressable's longPressHaptic), so this plays none.
Future<void> showNNMenu(
  BuildContext context, {
  Widget? preview,
  required List<NNMenuItem> items,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: nav.context);
  final chosen = await nav.push<NNMenuItem>(
    _MenuRoute(
      themes: themes,
      preview: preview,
      items: items,
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
  chosen?.onTap();
}

class _MenuRoute extends PopupRoute<NNMenuItem> {
  _MenuRoute({
    required this.themes,
    required this.preview,
    required this.items,
    required this.label,
  });
  final CapturedThemes themes;
  final Widget? preview;
  final List<NNMenuItem> items;
  final String label;

  @override
  Color? get barrierColor => const Color(0x59000000);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    Material(
      type: MaterialType.transparency,
      child: _MenuBody(preview: preview, items: items),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (reduceMotion(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

class _MenuBody extends StatelessWidget {
  const _MenuBody({required this.preview, required this.items});
  final Widget? preview;
  final List<NNMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NNSpace.lg),
            child: Column(
              key: const ValueKey('context-menu'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preview != null) ...[
                  // The preview is a picture of the row, solid (never glass), not a control.
                  IgnorePointer(
                    child: Container(
                      key: const ValueKey('menu-preview'),
                      padding: const EdgeInsets.all(NNSpace.md),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(NNRadius.card),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: preview,
                    ),
                  ),
                  const SizedBox(height: NNSpace.sm),
                ],
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(NNRadius.row),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: p.separator,
                          ),
                        _MenuRow(item: items[i]),
                      ],
                    ],
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

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});
  final NNMenuItem item;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final color = item.destructive ? p.danger : p.text;
    return Pressable(
      key: ValueKey('menu-${item.id}'),
      onTap: () => Navigator.of(context).pop(item),
      semanticLabel: item.label,
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.99,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: touchTarget(context) + 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NNSpace.md,
            vertical: NNSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: NNType.body.copyWith(color: color),
                ),
              ),
              const SizedBox(width: NNSpace.sm),
              Icon(item.icon, size: 22, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
