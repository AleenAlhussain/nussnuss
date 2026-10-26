import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../core/money.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/motion.dart';
import '../design/qr_view.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import '../l10n/strings.g.dart';
import 'pickers.dart';
import 'summary_card.dart';

/// The emoji each drawn icon stands for, sent with the cover for apps from before covers (the
/// same map as the web's group sheets).
const coverEmoji = <String, String>{
  'plane': '✈️',
  'beach': '🏖️',
  'mountain': '🏔️',
  'car': '🚗',
  'home': '🏠',
  'food': '🍽️',
  'coffee': '☕',
  'moon': '🌙',
  'party': '🎉',
  'gift': '🎁',
  'cart': '🛒',
  'heart': '❤️',
  'ball': '⚽',
  'work': '💼',
  'book': '📚',
  'music': '🎵',
};

/// Ready starts: the cover and a name for the usual reasons people share costs.
const _templates = [
  (key: 'trip', icon: 'plane'),
  (key: 'flat', icon: 'home'),
  (key: 'dinner', icon: 'food'),
  (key: 'iftar', icon: 'moon'),
  (key: 'eid', icon: 'gift'),
  (key: 'wedding', icon: 'heart'),
  (key: 'office', icon: 'work'),
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

  /// A trip until the person picks something else (as on the web).
  Cover _cover = const Cover('plane', 'sky');
  String _currency = guessCurrency();
  String? _template;
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
    // The preview beside the cover shows the name as it is typed.
    _name.addListener(() => setState(() {}));
  }

  void _pickTemplate(String key, String icon) {
    final s = context.s;
    final typed = _name.text.trim();
    // A name the person typed stays; one we filled in from another template is replaced.
    final ours = _template != null && typed == s.raw('tplName_$_template');
    setState(() {
      _template = key;
      _cover = Cover(icon, toneOfIcon(icon));
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
      _fail(context.s.errDup);
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
      _fail(s.errName);
      return;
    }
    if (_people.isEmpty) {
      _fail(s.errPeople);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await SessionScope.read(context).api.createGroup(
        name: _name.text.trim(),
        emoji: coverEmoji[_cover.icon] ?? '🍽️',
        cover: coverKey(_cover),
        currency: _currency,
        members: _people,
      );
      if (mounted) Navigator.of(context).pop(g);
    } on ApiException catch (e) {
      if (mounted) {
        _fail(e.offline ? s.offline : (e.status == 409 ? s.errDup : e.message));
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
                    label: s.raw('tpl_${t.key}'),
                    icon: coverIconData[t.icon],
                    selected: _template == t.key,
                    onTap: () => _pickTemplate(t.key, t.icon),
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
        SectionLabel(s.cover),
        Row(
          children: [
            CoverTile(
              key: ValueKey('new-cover-${coverKey(_cover)}'),
              cover: _cover,
              size: 56,
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Text(
                _name.text.trim().isEmpty ? s.groupNamePh : _name.text.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NNType.headline.copyWith(color: p.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: NNSpace.sm),
        CoverPicker(
          value: _cover,
          onChanged: (c) => setState(() => _cover = c),
        ),
        SectionLabel(s.currency),
        PickerField(
          key: const ValueKey('group-currency'),
          label: s.currency,
          value: currencyLabel(_currency, s.lang),
          onTap: () async {
            final v = await showCurrencyPicker(
              context,
              selected: _currency,
              title: s.currency,
            );
            if (v != null && mounted) setState(() => _currency = v);
          },
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
            child: ErrorText(_error!, shake: _shakes),
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

  late final Session _session = SessionScope.read(context);

  @override
  void initState() {
    super.initState();
    // invite runs from this sheet opening to the link going out (shared or copied).
    _session.timings.start('invite');
    _make();
  }

  @override
  void dispose() {
    _session.timings.cancel('invite');
    super.dispose();
  }

  void _sent() => _session.timings.finish('invite');

  Future<void> _make() async {
    final s = _session.s;
    try {
      // The short link (/j/<code>); servers before it only sent the token.
      final link = await _session.api.inviteLink(widget.group.id);
      if (mounted) setState(() => _link = '${webUrl()}${link.path}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? s.offline : e.message);
    }
  }

  Future<void> _copy() async {
    final link = _link;
    if (link == null) return;
    await _session.device.copy(link);
    _sent();
    haptic(Haptic.success);
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    final g = widget.group;
    final link = _link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What friends will see when they open it.
        NNCard(
          key: const ValueKey('invite-preview'),
          child: Row(
            children: [
              CoverTile(cover: g.cover, size: 48),
              const SizedBox(width: NNSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NNType.headline.copyWith(color: p.text),
                    ),
                    Text(
                      s.fill(s.joinMeta, {
                        'n': g.members.length,
                        'currency': g.currency,
                      }),
                      style: NNType.footnote.copyWith(color: p.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NNSpace.sm),
        Text(s.inviteBody, style: NNType.callout.copyWith(color: p.text2)),
        const SizedBox(height: NNSpace.md),
        if (link == null)
          NNCard(
            child: Center(
              child: _error == null
                  ? Skeleton(
                      label: s.loading,
                      child: const Bone(width: 196, height: 196, radius: 16),
                    )
                  : Text(
                      _error!,
                      style: NNType.subhead.copyWith(color: p.danger),
                    ),
            ),
          )
        else ...[
          Center(
            child: QrView(
              key: const ValueKey('invite-qr'),
              data: link,
              label: '${s.scanToJoin}, $link',
            ),
          ),
          const SizedBox(height: NNSpace.xs),
          Text(
            s.scanToJoin,
            textAlign: TextAlign.center,
            style: NNType.footnote.copyWith(color: p.text2),
          ),
          const SizedBox(height: NNSpace.md),
          // The short link, readable, with Copy beside it (Copy is how it is taken, so the text
          // itself is plain and not a second, smaller control).
          NNCard(
            padding: const EdgeInsets.only(
              left: NNSpace.md,
              right: NNSpace.xs,
              top: NNSpace.xxs,
              bottom: NNSpace.xxs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    link.replaceFirst(RegExp(r'^https?://'), ''),
                    key: const ValueKey('invite-link'),
                    textDirection: TextDirection.ltr,
                    style: NNType.callout.copyWith(
                      color: p.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                NNButton(
                  key: const ValueKey('copy-link'),
                  label: _copied ? s.copied : s.copy,
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  kind: ButtonKind.tinted,
                  expand: false,
                  onTap: _copy,
                ),
              ],
            ),
          ),
        ],
        SectionLabel(s.people),
        NNCard(
          padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
          child: Column(
            children: [
              for (var i = 0; i < g.members.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 44,
                    color: p.separator,
                  ),
                MergeSemantics(
                  key: ValueKey('invite-member-${g.members[i].id}'),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Row(
                      children: [
                        Avatar(
                          name: g.members[i].name,
                          look: g.members[i].avatar,
                          size: 32,
                        ),
                        const SizedBox(width: NNSpace.sm),
                        Expanded(
                          child: Text(
                            g.members[i].isMe ? s.you : g.members[i].name,
                            style: NNType.body.copyWith(color: p.text),
                          ),
                        ),
                        if (g.members[i].claimed) ...[
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: p.success,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          g.members[i].claimed ? s.joined : s.notJoined,
                          style: NNType.footnote.copyWith(
                            color: g.members[i].claimed ? p.success : p.text2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: NNSpace.lg),
        Builder(
          builder: (ctx) => NNButton(
            key: const ValueKey('share-link'),
            label: s.shareLink,
            icon: Icons.ios_share_rounded,
            onTap: link == null
                ? null
                : () async {
                    await _session.device.share(
                      text: _message(s),
                      origin: originOf(ctx),
                    );
                    _sent();
                  },
          ),
        ),
        const SizedBox(height: NNSpace.sm),
        NNButton(
          key: const ValueKey('whatsapp'),
          label: s.sendWhatsApp,
          icon: Icons.chat_rounded,
          kind: ButtonKind.tinted,
          onTap: link == null
              ? null
              : () async {
                  final device = _session.device;
                  final text = _message(s);
                  final ok = await device.open(
                    Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(text)}',
                    ),
                  );
                  if (!ok) await device.share(text: text);
                  _sent();
                },
        ),
      ],
    );
  }
}

/// "Cover and name": the group's name and its cover, saved together.
Future<GroupDetail?> showCoverSheet(BuildContext context, GroupDetail g) {
  return showNNSheet<GroupDetail>(
    context,
    key: const ValueKey('cover-sheet'),
    title: context.s.coverAndName,
    builder: (_) => _CoverForm(group: g),
  );
}

class _CoverForm extends StatefulWidget {
  const _CoverForm({required this.group});
  final GroupDetail group;

  @override
  State<_CoverForm> createState() => _CoverFormState();
}

class _CoverFormState extends State<_CoverForm> {
  late final _name = TextEditingController(text: widget.group.name);
  late Cover _cover = widget.group.cover;
  bool _busy = false;
  String? _error;
  int _shakes = 0;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = SessionScope.read(context);
    final s = session.s;
    final name = _name.text.trim();
    if (name.isEmpty) {
      haptic(Haptic.error);
      setState(() {
        _error = s.errName;
        _shakes++;
      });
      return;
    }
    final g = widget.group;
    final cover = coverKey(_cover);
    if (name == g.name && cover == coverKey(g.cover)) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await session.repo.took(
        await session.api.patchGroup(
          g.id,
          name: name == g.name ? null : name,
          cover: cover,
        ),
      );
      haptic(Haptic.success);
      session.touch();
      if (mounted) Navigator.of(context).pop(d);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.offline ? s.offline : e.message;
          _shakes++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final p = NNTheme.of(context).palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CoverTile(
              key: ValueKey('edit-cover-${coverKey(_cover)}'),
              cover: _cover,
              size: 56,
            ),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Text(
                _name.text.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NNType.title3.copyWith(color: p.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: NNSpace.md),
        NNField(
          label: s.groupName,
          controller: _name,
          fieldKey: const ValueKey('edit-group-name'),
          shake: _error == s.errName ? _shakes : 0,
        ),
        SectionLabel(s.cover),
        CoverPicker(
          value: _cover,
          onChanged: (c) => setState(() => _cover = c),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: NNSpace.md),
            child: ErrorText(_error!, shake: _shakes),
          ),
        const SizedBox(height: NNSpace.xl),
        NNButton(
          key: const ValueKey('save-cover'),
          label: s.save,
          busy: _busy,
          onTap: _save,
        ),
      ],
    );
  }
}
