import 'package:flutter/material.dart';

import '../core/extras.dart';
import '../core/money.dart';
import '../core/split.dart';
import '../core/suggest.dart';
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
import 'paywall.dart';

class ExpenseResult {
  const ExpenseResult(this.detail, {this.deletedId, this.queued = false});
  final GroupDetail detail;
  final String? deletedId;

  /// Saved on this device only, waiting for a connection.
  final bool queued;
}

Future<ExpenseResult?> showExpenseSheet(
  BuildContext context, {
  required GroupDetail group,
  Expense? editing,
  Rect? origin,
}) {
  final s = context.s;
  return showNNSheet<ExpenseResult>(
    context,
    key: const ValueKey('expense-sheet'),
    title: editing == null ? s.addExpense : s.editExpense,
    origin: origin,
    builder: (_) => ExpenseForm(group: group, editing: editing),
  );
}

/// How the bill is shared. Items is worked out on the device and sent as exact amounts.
enum SplitChoice { equal, exact, percent, shares, items }

/// One line of a receipt while it is being typed.
class _Item {
  _Item() : name = TextEditingController(), price = TextEditingController();
  final TextEditingController name;
  final TextEditingController price;
  final Set<String> members = {};

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

DateTime _nextPeriod(DateTime d, String every) {
  if (every == 'week') return d.add(const Duration(days: 7));
  final last = DateTime(d.year, d.month + 2, 0).day;
  return DateTime(
    d.year,
    d.month + 1,
    d.day > last ? last : d.day,
    d.hour,
    d.minute,
  );
}

/// Three taps: the amount, a suggested title (or your own), save. Who paid defaults to you and the
/// split to everyone equally; Details opens the rest only when someone needs it. The split preview
/// uses the same rules as the server, so what you see is exactly what gets saved.
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
  late final List<String> _ids = [for (final m in g.members) m.id];
  String _amount = '';
  final _title = TextEditingController();
  final _rate = TextEditingController();

  /// Picked by the person; null means "work it out from the title" (see [_cat]).
  String? _category;
  late String _paidBy = g.me;
  SplitChoice _mode = SplitChoice.equal;
  late Set<String> _included = _ids.toSet();
  late Map<String, int> _shares = {for (final id in _ids) id: 1};
  late final Map<String, TextEditingController> _exact = {
    for (final id in _ids) id: TextEditingController(),
  };
  late final Map<String, TextEditingController> _percent = {
    for (final id in _ids) id: TextEditingController(),
  };
  final _items = <_Item>[];
  late String _currency = g.currency;
  bool _rateLive = false;
  String _repeat = 'none';
  bool _details = false;
  String? _error;
  bool _busy = false;
  List<Suggestion>? _suggestions;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _fill(e);
      _details = true;
    }
    // The summary and the chips follow the title as it is typed.
    _title.addListener(_onTitle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.s;
    _suggestions ??= suggestTitles(
      recent: [
        for (final e in g.expenses.take(30))
          (title: e.title, category: e.category),
      ],
      hour: suggestionClock().hour,
      emoji: g.emoji,
      label: (k) => s.raw('sug_$k'),
    );
  }

  /// Copies an expense into the form: for editing it, or to add the same again.
  void _fill(Expense e) {
    final value = {for (final i in e.items) i.memberId: i.value};
    _currency = e.currency;
    _amount = minorToInput(e.amount, e.currency);
    _title.text = e.title;
    _category = e.category;
    _paidBy = _ids.contains(e.paidBy) ? e.paidBy : g.me;
    _mode = SplitChoice.values.byName(e.mode.name);
    _rate.text = e.currency == g.currency ? '' : _rateText(e.rate);
    _included = e.mode != SplitMode.equal
        ? _ids.toSet()
        : {
            for (final id in _ids)
              if ((value[id] ?? 0) > 0) id,
          };
    _shares = {
      for (final id in _ids)
        id: e.mode == SplitMode.shares ? (value[id] ?? 0) : 1,
    };
    for (final id in _ids) {
      _exact[id]!.text = e.mode == SplitMode.exact && (value[id] ?? 0) > 0
          ? minorToInput(value[id]!, e.currency)
          : '';
      _percent[id]!.text = e.mode == SplitMode.percent && (value[id] ?? 0) > 0
          ? minorToInput(value[id]!, 'USD')
          : '';
    }
  }

  String _rateText(double r) => r
      .toStringAsFixed(6)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');

  @override
  void dispose() {
    _title
      ..removeListener(_onTitle)
      ..dispose();
    _rate.dispose();
    for (final c in [..._exact.values, ..._percent.values]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  bool get _foreign => _currency != g.currency;
  int? get _total => parseAmountExpression(_amount, _currency);
  double? get _rateValue {
    if (!_foreign) return 1;
    final r = double.tryParse(normalizeDigits(_rate.text).replaceAll(',', '.'));
    return r != null && r > 0 ? r : null;
  }

  String _suggestionLabel(Suggestion x) =>
      x.title ?? context.s.raw('sug_${x.key}');

  void _onTitle() => setState(() {});

  /// The title that will be saved: what was typed, or else the first suggestion.
  String get _shownTitle {
    final typed = _title.text.trim();
    if (typed.isNotEmpty) return typed;
    final first = _suggestions?.firstOrNull;
    return first != null ? _suggestionLabel(first) : context.s.raw('cat_other');
  }

  /// Same as the web: a category the person picked; else that of a recent expense with the same
  /// title; else that of the matching suggestion (Lunch → food, Taxi → transport); else other.
  String get _cat {
    final picked = _category;
    if (picked != null) return picked;
    final k = _shownTitle.toLowerCase();
    for (final e in g.expenses) {
      if (e.title.trim().toLowerCase() == k) return e.category;
    }
    for (final x in _suggestions ?? const <Suggestion>[]) {
      if (_suggestionLabel(x).toLowerCase() == k) return x.category;
    }
    return 'other';
  }

  ({List<SplitItem> items, int rest})? get _itemized {
    final total = _total;
    if (total == null) return null;
    return itemizedSplit(total, [
      for (final i in _items)
        ReceiptItem(
          parseAmount(i.price.text, _currency) ?? 0,
          i.members.toList(),
        ),
    ], _ids);
  }

  SplitMode get _apiMode => _mode == SplitChoice.items
      ? SplitMode.exact
      : SplitMode.values.byName(_mode.name);

  List<SplitItem> get _splitItems => switch (_mode) {
    SplitChoice.items =>
      _itemized?.items ?? [for (final id in _ids) SplitItem(id, 0)],
    _ => [
      for (final id in _ids)
        SplitItem(id, switch (_mode) {
          SplitChoice.equal => _included.contains(id) ? 1 : 0,
          SplitChoice.shares => _shares[id] ?? 0,
          // Percent is typed like money with two decimals: 33.33 % = 3333 basis points.
          SplitChoice.exact => parseAmount(_exact[id]!.text, _currency) ?? 0,
          _ => parseAmount(_percent[id]!.text, 'USD') ?? 0,
        }),
    ],
  };

  bool _valid(int total) =>
      validateSplit(total, _apiMode, _splitItems, _paidBy, _ids) == null;

  Map<String, int> get _owed {
    final total = _total;
    if (total == null) return const {};
    if (_mode != SplitChoice.equal && _mode != SplitChoice.shares) {
      if (!_valid(total)) return const {};
    }
    return owedInExpenseCurrency(
      ExpenseLike(
        amount: total,
        currency: _currency,
        paidBy: _paidBy,
        mode: _apiMode,
        items: _splitItems,
      ),
    );
  }

  Future<void> _pickCurrency(String code) async {
    setState(() {
      _currency = code;
      _rateLive = false;
      if (!_foreign) _rate.clear();
    });
    if (!_foreign) return;
    final session = SessionScope.read(context);
    if (!session.hasPlus(g)) return;
    try {
      final r = await session.api.rate(code, g.currency, groupId: g.id);
      if (!mounted || _currency != code) return;
      setState(() {
        _rate.text = _rateText(r);
        _rateLive = true;
      });
    } on ApiException {
      // Typed by hand instead.
    }
  }

  Future<void> _pickRepeat(String every) async {
    final session = SessionScope.read(context);
    if (every != 'none' && !session.hasPlus(g)) {
      final ok = await showPaywall(context, group: g);
      if (!mounted || !ok) return;
    }
    setState(() => _repeat = every);
  }

  Future<void> _save() async {
    final session = SessionScope.read(context);
    final s = session.s;
    final total = _total;
    final title = _shownTitle;
    final category = _cat;
    String? err;
    if (total == null) {
      err = s.errAmount;
    } else if (_mode == SplitChoice.items && _itemized == null) {
      err = s.itemsOver;
    } else if (!_valid(total)) {
      err = s.errSplit;
    } else if (_rateValue == null) {
      err = s.errRate;
    }
    if (err != null) {
      setState(() {
        _error = err;
        if (err == s.errRate || err == s.errSplit || err == s.itemsOver) {
          _details = true;
        }
      });
      haptic(Haptic.light);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final input = ExpenseInput(
      id: _id,
      title: title,
      amount: total!,
      paidBy: _paidBy,
      mode: _apiMode,
      items: [
        for (final i in _splitItems)
          if (i.value > 0) i,
      ],
      category: category,
      currency: _foreign ? _currency : null,
      rate: _foreign ? _rateValue : null,
    );
    try {
      final r = await session.repo.saveExpense(
        g,
        input,
        editing: widget.editing != null,
      );
      var detail = r.detail;
      if (_repeat != 'none' && !r.queued) {
        try {
          detail = await session.repo.took(
            await session.api.addRecurring(
              g.id,
              input,
              every: _repeat,
              startAt: _nextPeriod(DateTime.now(), _repeat),
            ),
          );
        } on ApiException catch (e) {
          if (mounted) setState(() => _error = e.message);
        }
      }
      session.click();
      haptic(Haptic.success);
      if (mounted) {
        Navigator.of(context).pop(ExpenseResult(detail, queued: r.queued));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final session = SessionScope.read(context);
    final id = widget.editing!.id;
    setState(() => _busy = true);
    try {
      final r = await session.repo.deleteExpense(g, id);
      if (mounted) {
        Navigator.of(
          context,
        ).pop(ExpenseResult(r.detail, deletedId: id, queued: r.queued));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _summary() {
    final s = context.s;
    final payer = _paidBy == g.me
        ? s.youPaid
        : s.fill(s.paidByName, {'name': g.nameOf(_paidBy)});
    final split = switch (_mode) {
      SplitChoice.equal =>
        _included.length == _ids.length
            ? s.splitEqualAll
            : s.fill(s.splitEqualN, {'n': _included.length}),
      _ => s.raw('mode_${_mode.name}'),
    };
    return [
      payer,
      split,
      s.raw('cat_$_cat'),
      if (_foreign) _currency,
      if (_repeat != 'none') s.raw('every_$_repeat'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final suggestions = _suggestions ?? const <Suggestion>[];
    final last = widget.editing == null && g.expenses.isNotEmpty
        ? g.expenses.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (last != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: NNSpace.xs),
              child: NNChip(
                key: const ValueKey('repeat-last'),
                label: s.fill(s.repeatLast, {'title': last.title}),
                icon: Icons.replay_rounded,
                selected: false,
                onTap: () => setState(() {
                  _fill(last);
                  _currency = last.currency;
                }),
              ),
            ),
          ),
        Keypad(
          value: _amount,
          onChanged: (v) => setState(() => _amount = v),
          currency: _currency,
          lang: s.lang,
          label: s.amount,
        ),
        const SizedBox(height: NNSpace.md),
        NNField(
          label: s.whatFor,
          hint: suggestions.isEmpty
              ? s.whatForPh
              : _suggestionLabel(suggestions.first),
          controller: _title,
          fieldKey: const ValueKey('title'),
          maxLength: 80,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: NNSpace.xs),
          Semantics(
            container: true,
            label: s.suggestions,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < suggestions.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: NNSpace.xs,
                      ),
                      child: NNChip(
                        key: ValueKey('sug-$i'),
                        label: _suggestionLabel(suggestions[i]),
                        icon: categoryIcon(suggestions[i].category),
                        selected:
                            _title.text.trim() ==
                            _suggestionLabel(suggestions[i]),
                        onTap: () => setState(() {
                          _title.text = _suggestionLabel(suggestions[i]);
                          _category = null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: NNSpace.md),
        _DetailsRow(
          open: _details,
          title: s.details,
          summary: _summary(),
          onTap: () => setState(() => _details = !_details),
        ),
        AnimatedSize(
          duration: reduceMotion(context)
              ? Duration.zero
              : NNMotion.standardDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _details
              ? _detailsBody()
              : const SizedBox(width: double.infinity),
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

  Widget _detailsBody() {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final owed = _owed;
    final total = _total ?? 0;
    final items = _splitItems;
    final assigned = items.fold<int>(0, (a, b) => a + b.value);
    final plus = session.hasPlus(g);

    String? remaining;
    var remainingBad = true;
    if (_mode == SplitChoice.exact && total > 0 && assigned != total) {
      remaining = s.fill(s.left, {
        'amount': money(total - assigned, _currency, s.lang),
      });
    } else if (_mode == SplitChoice.percent && assigned != 10000) {
      remaining = s.fill(s.percentLeft, {
        'n': formatNumber(
          10000 - assigned,
          'USD',
        ).replaceAll(RegExp(r'\.00$'), ''),
      });
    } else if (_mode == SplitChoice.items && total > 0) {
      final it = _itemized;
      if (it == null) {
        remaining = _items.isEmpty ? null : s.itemsOver;
      } else if (it.rest > 0) {
        remaining = s.fill(s.itemsRest, {
          'amount': money(it.rest, _currency, s.lang),
        });
        remainingBad = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                selected: _cat == c,
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
        Segmented<SplitChoice>(
          values: SplitChoice.values,
          selected: _mode,
          label: (m) => s.raw('mode_${m.name}'),
          onChanged: (m) => setState(() {
            _mode = m;
            if (m == SplitChoice.items && _items.isEmpty) _items.add(_Item());
          }),
        ),
        const SizedBox(height: NNSpace.sm),
        _ShareBar(members: g.members, owed: owed, total: total),
        const SizedBox(height: NNSpace.sm),
        if (_mode == SplitChoice.items) ..._itemRows(),
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
              key: const ValueKey('remaining'),
              textAlign: TextAlign.end,
              style: NNType.footnote.copyWith(
                color: remainingBad ? p.danger : p.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        SectionLabel(s.paidIn),
        DropdownButtonFormField<String>(
          key: const ValueKey('currency'),
          initialValue: _currency,
          isExpanded: true,
          borderRadius: BorderRadius.circular(NNRadius.row),
          dropdownColor: p.surface,
          menuMaxHeight: 420,
          items: [
            for (final c in currencies)
              DropdownMenuItem(
                value: c.code,
                child: Text(
                  '${c.code} · ${c.name(s.lang)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null && v != _currency) _pickCurrency(v);
          },
        ),
        if (_foreign) ...[
          const SizedBox(height: NNSpace.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.rate,
                  style: NNType.subhead.copyWith(color: p.text2),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  key: const ValueKey('rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  onChanged: (_) => setState(() => _rateLive = false),
                  style: NNType.body.copyWith(
                    color: p.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '1.0',
                    semanticCounterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    suffixText: g.currency,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.xxs),
            child: Text(
              [
                s.fill(s.rateLine, {
                  'from': _currency,
                  'rate': _rate.text.isEmpty ? '?' : _rate.text,
                  'to': g.currency,
                }),
                if (_rateLive) s.rateLive,
                if (!plus) '${s.plusFRates}: ${s.needsPlus}',
              ].join(' · '),
              key: const ValueKey('rate-line'),
              style: NNType.footnote.copyWith(color: p.text2),
            ),
          ),
        ],
        if (widget.editing == null) ...[
          SectionLabel(s.repeats),
          Segmented<String>(
            values: const ['none', 'week', 'month'],
            selected: _repeat,
            label: (v) => s.raw('every_$v'),
            onChanged: _pickRepeat,
          ),
        ],
      ],
    );
  }

  List<Widget> _itemRows() {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return [
      for (var i = 0; i < _items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: NNSpace.sm),
          child: NNCard(
            key: ValueKey('item-$i'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('item-name-$i'),
                        controller: _items[i].name,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: s.itemName,
                          counterText: '',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: NNSpace.xs),
                    SizedBox(
                      width: 112,
                      child: TextField(
                        key: ValueKey('item-price-$i'),
                        controller: _items[i].price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: s.itemPrice,
                          isDense: true,
                          semanticCounterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NNSpace.xs),
                Wrap(
                  spacing: NNSpace.xs,
                  runSpacing: NNSpace.xs,
                  children: [
                    for (final m in g.members)
                      NNChip(
                        key: ValueKey('item-$i-${m.id}'),
                        label: m.isMe ? s.you : m.name,
                        selected: _items[i].members.contains(m.id),
                        onTap: () => setState(
                          () => _items[i].members.contains(m.id)
                              ? _items[i].members.remove(m.id)
                              : _items[i].members.add(m.id),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.only(bottom: NNSpace.sm),
          child: NNButton(
            key: const ValueKey('add-item'),
            label: s.addItem,
            icon: Icons.add_rounded,
            kind: ButtonKind.tinted,
            expand: false,
            onTap: () => setState(() => _items.add(_Item())),
          ),
        ),
      ),
      if (_items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: NNSpace.xs),
          child: Divider(height: 1, color: p.separator),
        ),
    ];
  }

  Widget _personRow(Member m, int? owes) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final name = m.isMe ? s.you : m.name;
    final share = owes == null || owes == 0
        ? ''
        : money(owes, _currency, s.lang);

    final Widget control = switch (_mode) {
      SplitChoice.equal => Icon(
        _included.contains(m.id)
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: _included.contains(m.id) ? p.accent : p.text3,
        size: 26,
      ),
      SplitChoice.items => const SizedBox.shrink(),
      SplitChoice.shares => Row(
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
      SplitChoice.exact || SplitChoice.percent => SizedBox(
        width: 112,
        child: TextField(
          key: ValueKey('split-${m.id}'),
          controller: _mode == SplitChoice.exact
              ? _exact[m.id]
              : _percent[m.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          onChanged: (_) => setState(() {}),
          style: NNType.body.copyWith(
            color: p.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: _mode == SplitChoice.exact
                ? minorToInput(0, _currency)
                : '0',
            suffixText: _mode == SplitChoice.percent ? '%' : null,
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

    if (_mode != SplitChoice.equal) {
      return Semantics(
        label: share.isEmpty ? name : '$name, $share',
        child: row,
      );
    }
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

/// The folded part of the form: one row that says what the defaults are, tap to change them.
class _DetailsRow extends StatelessWidget {
  const _DetailsRow({
    required this.open,
    required this.title,
    required this.summary,
    required this.onTap,
  });
  final bool open;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Pressable(
      key: const ValueKey('details'),
      onTap: onTap,
      semanticLabel: '$title, $summary',
      excludeChildSemantics: true,
      haptic: Haptic.selection,
      scale: 0.99,
      child: NNCard(
        padding: const EdgeInsets.symmetric(
          horizontal: NNSpace.md,
          vertical: NNSpace.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NNType.headline.copyWith(color: p.text)),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    key: const ValueKey('details-summary'),
                    style: NNType.footnote.copyWith(color: p.text2),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: reduceMotion(context)
                  ? Duration.zero
                  : NNMotion.standardDuration,
              child: Icon(Icons.expand_more_rounded, color: p.text2),
            ),
          ],
        ),
      ),
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
