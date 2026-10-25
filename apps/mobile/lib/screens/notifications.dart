import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/coin.dart';
import '../design/glass.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../format.dart';

/// Reminders the app sent on someone's behalf, newest first. Opening the inbox marks them read.
Future<void> showNotifications(BuildContext context) {
  return showNNSheet<void>(
    context,
    key: const ValueKey('notifications-sheet'),
    title: context.s.notifications,
    builder: (_) => const _Inbox(),
  );
}

class _Inbox extends StatefulWidget {
  const _Inbox();

  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  List<AppNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = SessionScope.read(context);
    try {
      final list = await session.api.notifications();
      if (!mounted) return;
      setState(() => _items = list);
      if (list.any((n) => !n.read)) {
        await session.api.markNotificationsRead();
        session.touch();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.offline ? session.s.offline : e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final items = _items;
    if (_error != null) {
      return Text(_error!, style: NNType.subhead.copyWith(color: p.danger));
    }
    if (items == null) return SkeletonRows(label: s.loading, count: 2);
    if (items.isEmpty) {
      return EmptyState(
        title: s.noNotifications,
        body: s.weeklyRemindersHint,
        art: const Coin(size: 56, join: 1),
      );
    }
    return NNCard(
      padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 0.5, color: p.separator),
            _Row(n: items[i]),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final d = n.data;
    final amount = d['amount'] is num && d['currency'] is String
        ? money((d['amount'] as num).toInt(), d['currency'] as String, s.lang)
        : '';
    final title = n.kind == 'reminder'
        ? s.fill(s.nReminder, {'to': '${d['to'] ?? ''}', 'amount': amount})
        : n.kind;
    final group = '${d['emoji'] ?? ''} ${d['group'] ?? ''}'.trim();
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.sm),
        child: Row(
          children: [
            Icon(
              Icons.notifications_rounded,
              color: n.read ? p.text3 : p.accent,
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: NNType.body.copyWith(
                      color: p.text,
                      fontWeight: n.read ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      if (group.isNotEmpty) group,
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(n.createdAt),
                    ].join(' · '),
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
