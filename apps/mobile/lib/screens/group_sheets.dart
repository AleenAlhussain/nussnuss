import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/motion.dart';
import '../design/widgets.dart';
import '../l10n/strings.g.dart';
import 'summary_card.dart';

const _emojis = [
  '🍽️',
  '✈️',
  '🏠',
  '🏖️',
  '🛒',
  '🎉',
  '⚽',
  '☕',
  '🌙',
  '🎁',
  '💍',
  '💼',
];

/// Ready starts: the emoji and a name for the usual reasons people share costs.
const _templates = [
  (key: 'trip', emoji: '✈️'),
  (key: 'flat', emoji: '🏠'),
  (key: 'dinner', emoji: '🍽️'),
  (key: 'iftar', emoji: '🌙'),
  (key: 'eid', emoji: '🎁'),
  (key: 'wedding', emoji: '💍'),
  (key: 'office', emoji: '💼'),
];

/// Where invite links open. The web join page lets friends join without installing anything.
String webUrl() {
  const fromBuild = String.fromEnvironment('WEB_URL');
  return fromBuild.isNotEmpty
      ? fromBuild.replaceAll(RegExp(r'/$'), '')
      : 'http://localhost:3000';
}

/// The currency from the phone's region, so most people never touch the picker.
String guessCurrency() {
  const byRegion = {
    'AE': 'AED', 'SA': 'SAR', 'KW': 'KWD', 'QA': 'QAR', 'BH': 'BHD', //
    'OM': 'OMR', 'EG': 'EGP', 'JO': 'JOD', 'SY': 'SYP', 'LB': 'LBP',
    'IQ': 'IQD', 'MA': 'MAD', 'TN': 'TND', 'DZ': 'DZD', 'TR': 'TRY',
    'GB': 'GBP', 'US': 'USD', 'IN': 'INR', 'PK': 'PKR', 'DE': 'EUR',
    'FR': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'NL': 'EUR',
  };
  final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  final code = byRegion[region];
  return code != null && currencies.any((c) => c.code == code) ? code : 'AED';
}

Future<GroupDetail?> showNewGroupSheet(BuildContext context, {Rect? origin}) {
  return showNNSheet<GroupDetail>(
    context,
    key: const ValueKey('new-group-sheet'),
    origin: origin,
    title: context.s.newGroup,
    builder: (_) => const NewGroupForm(),
  );
}

class NewGroupForm extends StatefulWidget {
  const NewGroupForm({super.key});

  @override
  State<NewGroupForm> createState() => _NewGroupFormState();
}

class _NewGroupFormState extends State<NewGroupForm> {
  final _name = TextEditingController();
  final _person = TextEditingController();
  final _people = <String>[];
  String _emoji = _emojis.first;
  String _currency = guessCurrency();
  String? _template;
  String? _error;
  bool _busy = false;

  void _pickTemplate(String key, String emoji) {
    final s = context.s;
    final typed = _name.text.trim();
    // A name the person typed stays; one we filled in from another template is replaced.
    final ours = _template != null && typed == s.raw('tplName_$_template');
    setState(() {
      _template = key;
      _emoji = emoji;
      if (typed.isEmpty || ours) {
        _name.text = key == 'trip' ? '' : s.raw('tplName_$key');
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _person.dispose();
    super.dispose();
  }

  void _addPerson() {
    final n = _person.text.trim();
    if (n.isEmpty) return;
    final me = SessionScope.read(context).me?.name ?? '';
    final taken = {me.toLowerCase(), ..._people.map((x) => x.toLowerCase())};
    if (taken.contains(n.toLowerCase())) {
      setState(() => _error = context.s.errDup);
      return;
    }
    setState(() {
      _people.add(n);
      _person.clear();
      _error = null;
    });
  }

  Future<void> _create() async {
    final s = context.s;
    if (_person.text.trim().isNotEmpty) _addPerson();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = s.errName);
      return;
    }
    if (_people.isEmpty) {
      setState(() => _error = s.errPeople);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await SessionScope.read(context).api.createGroup(
        name: _name.text.trim(),
        emoji: _emoji,
        currency: _currency,
        members: _people,
      );
      if (mounted) Navigator.of(context).pop(g);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.offline
              ? s.offline
              : (e.status == 409 ? s.errDup : e.message),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NNSpace.xxs,
            bottom: 6,
          ),
          child: Text(
            s.whatKind,
            style: NNType.footnote.copyWith(
              color: p.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in _templates)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NNSpace.xs),
                  child: NNChip(
                    key: ValueKey('tpl-${t.key}'),
                    label: '${t.emoji} ${s.raw('tpl_${t.key}')}',
                    selected: _template == t.key,
                    onTap: () => _pickTemplate(t.key, t.emoji),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NNSpace.md),
        NNField(
          label: s.groupName,
          hint: s.groupNamePh,
          controller: _name,
          fieldKey: const ValueKey('group-name'),
          autofocus: true,
        ),
        const SizedBox(height: NNSpace.sm),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in _emojis)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NNSpace.xs),
                  child: Pressable(
                    onTap: () => setState(() => _emoji = e),
                    selected: e == _emoji,
                    semanticLabel: e,
                    excludeChildSemantics: true,
                    haptic: Haptic.selection,
                    child: AnimatedContainer(
                      duration: NNMotion.fade,
                      width: 52,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: CircleBorder(
                          side: BorderSide(
                            color: e == _emoji ? p.accent : p.separator,
                            width: e == _emoji ? 2 : 1,
                          ),
                        ),
                        color: e == _emoji ? p.accentSoft : p.surface,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SectionLabel(s.currency),
        DropdownButtonFormField<String>(
          key: const ValueKey('group-currency'),
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
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        ),
        SectionLabel(s.people),
        Wrap(
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            NNChip(label: s.you, selected: true, onTap: null),
            for (final n in _people)
              NNChip(
                label: n,
                selected: false,
                onTap: () => setState(() => _people.remove(n)),
                trailing: Icon(Icons.close_rounded, size: 16, color: p.text2),
              ),
          ],
        ),
        const SizedBox(height: NNSpace.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('person-name'),
                controller: _person,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addPerson(),
                maxLength: 40,
                decoration: InputDecoration(
                  hintText: s.personPh,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: NNSpace.xs),
            NNButton(
              key: const ValueKey('add-person'),
              label: s.addPerson,
              kind: ButtonKind.tinted,
              expand: false,
              onTap: _addPerson,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: NNType.subhead.copyWith(color: p.danger),
              ),
            ),
          ),
        const SizedBox(height: NNSpace.xl),
        NNButton(
          key: const ValueKey('create-group'),
          label: s.create,
          busy: _busy,
          onTap: _create,
        ),
      ],
    );
  }
}

Future<void> showShareSheet(BuildContext context, GroupDetail g) {
  return showNNSheet<void>(
    context,
    key: const ValueKey('share-sheet'),
    title: context.s.shareTitle,
    builder: (_) => _ShareBody(group: g),
  );
}

class _ShareBody extends StatefulWidget {
  const _ShareBody({required this.group});
  final GroupDetail group;

  @override
  State<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends State<_ShareBody> {
  String? _link;
  String? _error;
  bool _copied = false;

  String _message(NNStrings s) =>
      '${s.fill(s.shareMessage, {'name': widget.group.name})} $_link';

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    final s = SessionScope.read(context).s;
    try {
      final token = await SessionScope.read(
        context,
      ).api.invite(widget.group.id);
      if (mounted) setState(() => _link = '${webUrl()}/join/$token');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.shareBody, style: NNType.callout.copyWith(color: p.text2)),
        const SizedBox(height: NNSpace.md),
        NNCard(
          child: _link == null
              ? Center(
                  child: _error == null
                      ? Skeleton(
                          label: s.loading,
                          child: const Bone(height: 18),
                        )
                      : Text(
                          _error!,
                          style: NNType.subhead.copyWith(color: p.danger),
                        ),
                )
              : SelectableText(
                  _link!,
                  key: const ValueKey('invite-link'),
                  style: NNType.subhead.copyWith(color: p.text),
                  textDirection: TextDirection.ltr,
                ),
        ),
        const SizedBox(height: NNSpace.lg),
        Builder(
          builder: (ctx) => NNButton(
            key: const ValueKey('share-link'),
            label: s.share,
            icon: Icons.ios_share_rounded,
            onTap: _link == null
                ? null
                : () => SessionScope.read(
                    context,
                  ).device.share(text: _message(s), origin: originOf(ctx)),
          ),
        ),
        const SizedBox(height: NNSpace.sm),
        NNButton(
          key: const ValueKey('whatsapp'),
          label: s.sendWhatsApp,
          icon: Icons.chat_rounded,
          kind: ButtonKind.tinted,
          onTap: _link == null
              ? null
              : () async {
                  final device = SessionScope.read(context).device;
                  final text = _message(s);
                  final ok = await device.open(
                    Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(text)}',
                    ),
                  );
                  if (!ok) await device.share(text: text);
                },
        ),
        const SizedBox(height: NNSpace.sm),
        NNButton(
          key: const ValueKey('copy-link'),
          label: _copied ? s.copied : s.copyLink,
          icon: _copied ? Icons.check_rounded : Icons.link_rounded,
          kind: ButtonKind.plain,
          onTap: _link == null
              ? null
              : () async {
                  await SessionScope.read(context).device.copy(_message(s));
                  haptic(Haptic.success);
                  if (!mounted) return;
                  setState(() => _copied = true);
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (mounted) setState(() => _copied = false);
                },
        ),
      ],
    );
  }
}
