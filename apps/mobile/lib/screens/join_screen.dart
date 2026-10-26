import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

/// What opens from an invite link: the group, the names, "which one are you?". Picking a name is
/// also how someone new starts: no other sign-up.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.token});
  final String token;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  ({Map<String, dynamic> group, List<Member> members})? _preview;
  bool _bad = false;
  String? _pick;
  final _name = TextEditingController();
  String? _error;

  /// Goes up with every error: the field or message shakes, with the error haptic.
  int _shakes = 0;

  void _fail(String message) => setState(() {
    _error = message;
    _shakes++;
  });
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await SessionScope.read(context).api.preview(widget.token);
      if (mounted) setState(() => _preview = p);
    } on ApiException {
      if (mounted) setState(() => _bad = true);
    }
  }

  void _leave() {
    final session = SessionScope.read(context);
    session.pendingInvite = null;
    session.touch();
  }

  Future<void> _join() async {
    final session = SessionScope.read(context);
    final s = session.s;
    final preview = _preview;
    if (preview == null || _pick == null) return;
    final chosen = _pick == 'new'
        ? _name.text.trim()
        : preview.members.firstWhere((m) => m.id == _pick).name;
    if (chosen.isEmpty) {
      _fail(s.yourNameHint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (session.me == null) {
        await session.start(chosen);
        // They came for this group, not to make a new one.
        session.firstRun = false;
      }
      final d = await session.api.join(
        widget.token,
        memberId: _pick == 'new' ? null : _pick,
        name: _pick == 'new' ? chosen : null,
      );
      await session.repo.took(d);
      session.openGroupId = d.id;
      _leave();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.offline ? s.offline : e.message;
          _shakes++;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final preview = _preview;
    Widget body;
    if (_bad) {
      body = Column(
        children: [
          EmptyState(
            title: s.badLink,
            body: '',
            art: const Coin(size: 72, join: 0),
          ),
          NNButton(label: s.back, kind: ButtonKind.tinted, onTap: _leave),
        ],
      );
    } else if (preview == null) {
      body = Padding(
        padding: const EdgeInsets.only(top: NNSpace.xxl),
        child: SkeletonRows(label: s.loading, count: 3, separate: false),
      );
    } else {
      final pickedName = _pick == null || _pick == 'new'
          ? null
          : preview.members.firstWhere((m) => m.id == _pick).name;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CoverTile(
              cover: groupCover(
                cover: preview.group['cover'] as String?,
                emoji: preview.group['emoji'] as String?,
              ),
              size: 88,
            ),
          ),
          const SizedBox(height: NNSpace.sm),
          Text(
            s.joinTitle,
            textAlign: TextAlign.center,
            style: NNType.subhead.copyWith(color: p.text2),
          ),
          Semantics(
            header: true,
            child: Text(
              preview.group['name'] as String? ?? '',
              textAlign: TextAlign.center,
              style: NNType.title1.copyWith(color: p.text),
            ),
          ),
          SectionLabel(s.joinWho),
          NNCard(
            padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
            child: Column(
              children: [
                for (final m in preview.members)
                  _Choice(
                    key: ValueKey('who-${m.id}'),
                    label: m.name,
                    note: m.claimed ? s.joinTaken : null,
                    selected: _pick == m.id,
                    onTap: m.claimed
                        ? null
                        : () => setState(() => _pick = m.id),
                  ),
                _Choice(
                  key: const ValueKey('who-new'),
                  label: s.joinNew,
                  selected: _pick == 'new',
                  onTap: () => setState(() => _pick = 'new'),
                ),
              ],
            ),
          ),
          if (_pick == 'new')
            Padding(
              padding: const EdgeInsets.only(top: NNSpace.md),
              child: NNField(
                label: s.joinNewName,
                controller: _name,
                autofocus: true,
                maxLength: 40,
                fieldKey: const ValueKey('join-name'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: NNSpace.md),
              child: ErrorText(_error!, shake: _shakes),
            ),
          const SizedBox(height: NNSpace.xl),
          NNButton(
            key: const ValueKey('join'),
            label: pickedName == null
                ? s.joinBtn
                : s.fill(s.joinAs, {'name': pickedName}),
            busy: _busy,
            onTap: _pick == null ? null : _join,
          ),
          const SizedBox(height: NNSpace.xs),
          NNButton(label: s.cancel, kind: ButtonKind.plain, onTap: _leave),
        ],
      );
    }
    return StepBack(
      child: Scaffold(
        key: const ValueKey('join-screen'),
        backgroundColor: p.bg,
        body: Ambient.behind(
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.all(NNSpace.xl),
                  children: [body],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
  });
  final String label;
  final String? note;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: note == null ? label : '$label, $note',
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.99,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? p.accent : p.text3,
              ),
              const SizedBox(width: NNSpace.sm),
              Expanded(
                child: Text(label, style: NNType.body.copyWith(color: p.text)),
              ),
              if (note != null)
                Text(note!, style: NNType.footnote.copyWith(color: p.text2)),
            ],
          ),
        ),
      ),
    );
  }
}
