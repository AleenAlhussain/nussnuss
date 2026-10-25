import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/split.dart';
import '../core/types.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../format.dart';
import 'keypad.dart';

class ExpenseResult {
  const ExpenseResult(this.detail, {this.deletedId});
  final GroupDetail detail;
  final String? deletedId;
}

Future<ExpenseResult?> showExpenseSheet(
  BuildContext context, {
  required GroupDetail group,
  Expense? editing,
}) {
  final s = context.s;
  return showNNSheet<ExpenseResult>(
    context,
    key: const ValueKey('expense-sheet'),
    title: editing == null ? s.addExpense : s.editExpense,
    builder: (_) => ExpenseForm(group: group, editing: editing),
  );
}

/// Amount on the keypad, what it was for, who paid and how to split it. The split preview updates as you go
/// and uses the same rules as the server, so what you see is exactly what gets saved.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, required this.group, this.editing});
  final GroupDetail group;
  final Expense? editing;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  late final GroupDetail g = widget.group;
  late final String _id = widget.editing?.id ?? newId();
  late String _amount;
  late final TextEditingController _title;
  late String _category;
  late String _paidBy;
  late SplitMode _mode;
  late Set<String> _included;
  late Map<String, int> _shares;
  late Map<String, TextEditingController> _exact;
  late Map<String, TextEditingController> _percent;
  String? _error;
  bool _busy = false;

  String get _currency => widget.editing?.currency ?? g.currency;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final ids = [for (final m in g.members) m.id];
    final value = {
      for (final i in e?.items ?? const <SplitItem>[]) i.memberId: i.value,
    };
    _amount = e == null ? '' : minorToInput(e.amount, _currency);
    _title = TextEditingController(text: e?.title ?? '');
    _category = e?.category ?? 'other';
    _paidBy = e?.paidBy ?? g.me;
    _mode = e?.mode ?? SplitMode.equal;
    _included = e == null || e.mode != SplitMode.equal
        ? ids.toSet()
        : {
            for (final id in ids)
              if ((value[id] ?? 0) > 0) id,
          };
    _shares = {
      for (final id in ids)
        id: e?.mode == SplitMode.shares ? (value[id] ?? 0) : 1,
    };
    _exact = {
      for (final id in ids)
        id: TextEditingController(
          text: e?.mode == SplitMode.exact && (value[id] ?? 0) > 0
              ? minorToInput(value[id]!, _currency)
              : '',
        ),
    };
    _percent = {
      for (final id in ids)
        id: TextEditingController(
          text: e?.mode == SplitMode.percent && (value[id] ?? 0) > 0
              ? minorToInput(value[id]!, 'USD')
              : '',
        ),
    };
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in [..._exact.values, ..._percent.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _total => parseAmountExpression(_amount, _currency);

  List<SplitItem> get _items => [
    for (final m in g.members)
      SplitItem(m.id, switch (_mode) {
        SplitMode.equal => _included.contains(m.id) ? 1 : 0,
        SplitMode.shares => _shares[m.id] ?? 0,
        // Percent is typed like money with two decimals: 33.33 % = 3333 basis points.
        SplitMode.exact => parseAmount(_exact[m.id]!.text, _currency) ?? 0,
        SplitMode.percent => parseAmount(_percent[m.id]!.text, 'USD') ?? 0,
      }),
  ];

  Map<String, int> get _owed {
    final total = _total;
    if (total == null) return const {};
    if (_mode == SplitMode.percent || _mode == SplitMode.exact) {
      if (validateSplit(total, _mode, _items, _paidBy, [
            for (final m in g.members) m.id,
          ]) !=
          null) {
        return const {};
      }
    }
    return owedInExpenseCurrency(
      ExpenseLike(
        amount: total,
        currency: _currency,
        paidBy: _paidBy,
        mode: _mode,
        items: _items,
      ),
    );
  }

  Future<void> _save() async {
    final s = context.s;
    final total = _total;
    final title = _title.text.trim();
    String? err;
    if (total == null) {
      err = s.errAmount;
    } else if (title.isEmpty) {
      err = s.errTitle;
    } else if (validateSplit(total, _mode, _items, _paidBy, [
          for (final m in g.members) m.id,
        ]) !=
        null) {
      err = s.errSplit;
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final api = SessionScope.read(context).api;
    final input = ExpenseInput(
      id: _id,
      title: title,
      amount: total!,
      paidBy: _paidBy,
      mode: _mode,
      items: _items,
      category: _category,
    );
    try {
      final detail = widget.editing == null
          ? await api.addExpense(g.id, input)
          : await api.updateExpense(input);
      if (mounted) Navigator.of(context).pop(ExpenseResult(detail));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final s = context.s;
    final id = widget.editing!.id;
    setState(() => _busy = true);
    try {
      final detail = await SessionScope.read(context).api.deleteExpense(id);
      if (mounted) {
        Navigator.of(context).pop(ExpenseResult(detail, deletedId: id));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final owed = _owed;
    final total = _total ?? 0;
    final items = _items;
    final assigned = items.fold<int>(0, (a, b) => a + b.value);

    String? remaining;
    if (_mode == SplitMode.exact && total > 0 && assigned != total) {
      remaining = s.fill(s.left, {
        'amount': money(total - assigned, _currency, s.lang),
      });
    } else if (_mode == SplitMode.percent && assigned != 10000) {
      remaining = s.fill(s.percentLeft, {
        'n': formatNumber(
          10000 - assigned,
          'USD',
        ).replaceAll(RegExp(r'\.00$'), ''),
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Keypad(
          value: _amount,
          onChanged: (v) => setState(() => _amount = v),
          currency: _currency,
          lang: s.lang,
          label: s.amount,
        ),
        const SizedBox(height: NNSpace.lg),
        NNField(
          label: s.whatFor,
          hint: s.whatForPh,
          controller: _title,
          fieldKey: const ValueKey('title'),
          maxLength: 80,
        ),
        SectionLabel(s.category),
        Wrap(
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            for (final c in categories)
              NNChip(
                key: ValueKey('cat-$c'),
                label: s.raw('cat_$c'),
                icon: categoryIcon(c),
                selected: _category == c,
                onTap: () => setState(() => _category = c),
              ),
          ],
        ),
        SectionLabel(s.paidBy),
        Wrap(
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            for (final m in g.members)
              NNChip(
                key: ValueKey('payer-${m.id}'),
                label: m.isMe ? s.you : m.name,
                selected: _paidBy == m.id,
                onTap: () => setState(() => _paidBy = m.id),
              ),
          ],
        ),
        SectionLabel(s.split),
        Segmented<SplitMode>(
          values: SplitMode.values,
          selected: _mode,
          label: (m) => s.raw('mode_${m.name}'),
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: NNSpace.sm),
        _ShareBar(members: g.members, owed: owed, total: total),
        const SizedBox(height: NNSpace.sm),
        NNCard(
          padding: const EdgeInsets.symmetric(
            horizontal: NNSpace.md,
            vertical: NNSpace.xxs,
          ),
          child: Column(
            children: [
              for (var i = 0; i < g.members.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 0.5, color: p.separator),
                _personRow(g.members[i], owed[g.members[i].id]),
              ],
            ],
          ),
        ),
        if (remaining != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xs),
            child: Text(
              remaining,
              textAlign: TextAlign.end,
              style: NNType.footnote.copyWith(
                color: p.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('expense-error'),
                style: NNType.subhead.copyWith(color: p.danger),
              ),
            ),
          ),
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('save-expense'),
          label: s.save,
          busy: _busy,
          onTap: _save,
        ),
        if (widget.editing != null) ...[
          const SizedBox(height: NNSpace.sm),
          NNButton(
            key: const ValueKey('delete-expense'),
            label: s.delete,
            kind: ButtonKind.danger,
            onTap: _busy ? null : _delete,
          ),
        ],
      ],
    );
  }

  Widget _personRow(Member m, int? owes) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final name = m.isMe ? s.you : m.name;
    final share = owes == null || owes == 0
        ? ''
        : money(owes, _currency, s.lang);

    final Widget control = switch (_mode) {
      SplitMode.equal => Icon(
        _included.contains(m.id)
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: _included.contains(m.id) ? p.accent : p.text3,
        size: 26,
      ),
      SplitMode.shares => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            label: '$name −',
            onTap: (_shares[m.id] ?? 0) > 0
                ? () => setState(() => _shares[m.id] = (_shares[m.id] ?? 0) - 1)
                : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${_shares[m.id] ?? 0}',
              key: ValueKey('share-count-${m.id}'),
              textAlign: TextAlign.center,
              style: NNType.headline.copyWith(
                color: p.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            label: '$name +',
            onTap: (_shares[m.id] ?? 0) < 99
                ? () => setState(() => _shares[m.id] = (_shares[m.id] ?? 0) + 1)
                : null,
          ),
        ],
      ),
      SplitMode.exact || SplitMode.percent => SizedBox(
        width: 112,
        child: TextField(
          controller: _mode == SplitMode.exact ? _exact[m.id] : _percent[m.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          onChanged: (_) => setState(() {}),
          style: NNType.body.copyWith(
            color: p.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: _mode == SplitMode.exact
                ? minorToInput(0, _currency)
                : '0',
            suffixText: _mode == SplitMode.percent ? '%' : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 14,
            ),
            semanticCounterText: '',
          ),
        ),
      ),
    };

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Avatar(name: m.name, size: 32),
          const SizedBox(width: NNSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: NNType.body.copyWith(color: p.text)),
                if (share.isNotEmpty)
                  Text(share, style: NNType.footnote.copyWith(color: p.text2)),
              ],
            ),
          ),
          control,
        ],
      ),
    );

    if (_mode != SplitMode.equal) return Semantics(label: name, child: row);
    return Pressable(
      key: ValueKey('include-${m.id}'),
      onTap: () => setState(
        () => _included.contains(m.id)
            ? _included.remove(m.id)
            : _included.add(m.id),
      ),
      checked: _included.contains(m.id),
      semanticLabel: share.isEmpty ? name : '$name, $share',
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.98,
      child: row,
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.9,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Container(
          width: touchTarget(context),
          height: touchTarget(context),
          alignment: Alignment.center,
          child: Container(
            width: 32,
            height: 32,
            decoration: ShapeDecoration(
              shape: const CircleBorder(),
              color: p.accentSoft,
            ),
            child: Icon(icon, size: 20, color: p.onAccentSoft),
          ),
        ),
      ),
    );
  }
}

/// Who pays what, as one bar split into each person's share. It moves as the split changes.
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.members,
    required this.owed,
    required this.total,
  });
  final List<Member> members;
  final Map<String, int> owed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final colors = [
      p.accent,
      p.highlight,
      p.success,
      p.danger,
      p.onAccentSoft,
      p.text2,
    ];
    final parts = [
      for (var i = 0; i < members.length; i++)
        if ((owed[members[i].id] ?? 0) > 0)
          (flex: owed[members[i].id]!, color: colors[i % colors.length]),
    ];
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NNRadius.pill),
        child: SizedBox(
          height: 8,
          child: total <= 0 || parts.isEmpty
              ? ColoredBox(color: p.surface2)
              : Row(
                  children: [
                    for (var i = 0; i < parts.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        // Flex has to be a small int: scale shares to a per-mille of the total.
                        flex: (parts[i].flex * 1000 ~/ total).clamp(1, 1000),
                        child: AnimatedContainer(
                          duration: NNMotion.fade,
                          color: parts[i].color,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
