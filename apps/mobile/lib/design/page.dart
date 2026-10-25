import 'package:flutter/material.dart';

import 'glass.dart';
import 'theme.dart';
import 'tokens.g.dart';

/// A screen with a large title that hands over to a small one in the top bar as you scroll.
/// The bar is not glass: content fades out under a scroll edge, and only the buttons on it are glass.
/// [bottom] floats over the content at the bottom (tab bar, add button).
class NNPage extends StatefulWidget {
  const NNPage({
    super.key,
    required this.title,
    required this.slivers,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.onRefresh,
    this.onScrollDirection,
    this.titleKey,
  });

  final String title;
  final List<Widget> slivers;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final Future<void> Function()? onRefresh;

  /// Called with true while the person scrolls down past the title, false when they scroll back up.
  final ValueChanged<bool>? onScrollDirection;
  final Key? titleKey;

  @override
  State<NNPage> createState() => _NNPageState();
}

class _NNPageState extends State<NNPage> {
  final _scroll = ScrollController();
  bool _collapsed = false;

  /// False while the titles are fading between the large and the small one. Neither is in the
  /// semantics tree until it has fully appeared, so nothing half-transparent is ever read or checked.
  bool _settled = true;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final y = _scroll.offset;
    final collapsed = y > 44;
    if (collapsed != _collapsed) {
      setState(() {
        _collapsed = collapsed;
        _settled = false;
      });
    }
    if ((y - _last).abs() > 6) {
      widget.onScrollDirection?.call(y > _last && y > 80);
      _last = y;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - NNLayout.maxContent) / 2).clamp(
      NNSpace.margin,
      double.infinity,
    );
    final still = reduceMotion(context);
    final duration = still ? NNMotion.fade : const Duration(milliseconds: 220);
    // Both sides get the same width so the small title stays centred; wide enough for the buttons.
    final n = widget.actions.length;
    final sideWidth = n <= 1
        ? 96.0
        : (n * touchTarget(context) + (n - 1) * NNSpace.xs).clamp(96.0, 220.0);

    Widget list = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: pad.top + NNLayout.topBar)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverToBoxAdapter(
            child: AnimatedOpacity(
              opacity: _collapsed ? 0 : 1,
              duration: duration,
              onEnd: () {
                if (mounted && !_settled) setState(() => _settled = true);
              },
              child: AnimatedScale(
                scale: _collapsed && !still ? 0.96 : 1,
                duration: duration,
                alignment: AlignmentDirectional.centerStart.resolve(
                  Directionality.of(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: NNSpace.md),
                  child: ExcludeSemantics(
                    excluding: _collapsed || !_settled,
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        key: widget.titleKey,
                        style: NNType.largeTitle.copyWith(color: p.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final s in widget.slivers)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: s,
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: pad.bottom + NNLayout.tabBar + 56),
        ),
      ],
    );
    if (widget.onRefresh != null) {
      list = RefreshIndicator.adaptive(
        onRefresh: widget.onRefresh!,
        edgeOffset: pad.top + NNLayout.topBar,
        color: p.accent,
        child: list,
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          Positioned.fill(child: list),
          // Scroll edge: solid background that fades out at its lower edge. Shown once the title has scrolled away.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _collapsed ? 1 : 0,
                duration: duration,
                child: Container(
                  height: pad.top + NNLayout.topBar + 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [p.bg, p.bg, p.bg.withValues(alpha: 0)],
                      stops: [
                        0,
                        (pad.top + NNLayout.topBar) /
                            (pad.top + NNLayout.topBar + 24),
                        1,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: pad.top,
            left: 0,
            right: 0,
            height: NNLayout.topBar,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: (side - 12).clamp(8, double.infinity),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: sideWidth,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: widget.leading,
                    ),
                  ),
                  // The small title is a label, not a control: taps go through to the content.
                  Expanded(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        excluding: !_collapsed || !_settled,
                        child: AnimatedOpacity(
                          opacity: _collapsed ? 1 : 0,
                          duration: duration,
                          child: AnimatedSlide(
                            offset: _collapsed || still
                                ? Offset.zero
                                : const Offset(0, 0.15),
                            duration: duration,
                            child: Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NNType.headline.copyWith(color: p.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: sideWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < widget.actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: NNSpace.xs),
                          widget.actions[i],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.bottom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  (side - 4).clamp(16, double.infinity),
                  0,
                  (side - 4).clamp(16, double.infinity),
                  pad.bottom + 12,
                ),
                child: widget.bottom,
              ),
            ),
        ],
      ),
    );
  }
}
