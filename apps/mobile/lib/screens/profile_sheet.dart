import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/identity.dart';
import '../data/api.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';

/// "Photo, name and colour": how friends see you. A live preview on top; a photo from the library,
/// an emoji or your initial; one of seven colours; your name.
Future<void> showProfileSheet(BuildContext context) {
  return showNNSheet<void>(
    context,
    key: const ValueKey('profile-sheet'),
    title: context.s.profileEdit,
    builder: (_) => const _ProfileForm(),
  );
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm();

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final Session _session = SessionScope.read(context);
  late final _name = TextEditingController(text: _session.me?.name ?? '');
  late AvatarLook _start = _session.me?.look ?? AvatarLook.forName('');
  late String _kind = _start.kind;
  late String _tone = _start.tone;
  late String _emoji = _start.kind == 'emoji'
      ? _start.value!
      : avatarEmoji.first;
  bool _busy = false;
  String? _error;
  int _shake = 0;

  /// The server's photo, when there is one.
  String? get _photoUrl => _session.me?.look.url;

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

  AvatarLook get _draft => switch (_kind) {
    'photo' when _photoUrl != null => AvatarLook.photo(_photoUrl!, _tone),
    'emoji' => AvatarLook.emoji(_emoji, _tone),
    _ => AvatarLook.initial(_tone),
  };

  void _fail(String message) {
    haptic(Haptic.error);
    setState(() {
      _busy = false;
      _error = message;
      _shake++;
    });
  }

  Future<void> _choosePhoto() async {
    final s = _session.s;
    final bytes = await _session.device.pickAvatarPhoto();
    if (bytes == null || !mounted) return;
    if (bytes.length > 70000) return _fail(s.photoTooBig);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.setPhoto(base64Encode(bytes));
      if (!mounted) return;
      haptic(Haptic.success);
      setState(() {
        _busy = false;
        _kind = 'photo';
        _start = _session.me?.look ?? _start;
      });
    } on ApiException catch (e) {
      if (mounted) _fail(e.offline ? s.offline : e.message);
    }
  }

  Future<void> _removePhoto() async {
    final s = _session.s;
    setState(() => _busy = true);
    try {
      await _session.removePhoto();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _kind = 'initial';
        _start = _session.me?.look ?? _start;
      });
    } on ApiException catch (e) {
      if (mounted) _fail(e.offline ? s.offline : e.message);
    }
  }

  Future<void> _save() async {
    final s = _session.s;
    final name = _name.text.trim();
    if (name.isEmpty) return _fail(s.errName);
    final look = _draft;
    final me = _session.me;
    // A photo keeps itself; an emoji or an initial is sent when it changed.
    final avatar = look.kind == 'photo' || look == me?.look ? null : look;
    if (name == me?.name && avatar == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.setProfile(
        name: name == me?.name ? null : name,
        avatar: avatar,
      );
      if (!mounted) return;
      haptic(Haptic.success);
      final nav = Navigator.of(context);
      showToast(context, s.profileSaved, check: true);
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) _fail(e.offline ? s.offline : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final nn = NNTheme.of(context);
    final p = nn.palette;
    final covers = nn.isDark ? NNCovers.dark : NNCovers.light;
    final name = _name.text.trim().isEmpty
        ? (_session.me?.name ?? '')
        : _name.text.trim();
    final hasPhoto = _photoUrl != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The preview: how friends will see you.
        Semantics(
          label: s.preview,
          container: true,
          child: Column(
            key: const ValueKey('profile-preview'),
            children: [
              Avatar(
                key: ValueKey('preview-${_draft.kind}-${_draft.tone}'),
                name: name,
                look: _draft,
                size: 96,
              ),
              const SizedBox(height: NNSpace.xs),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NNType.title3.copyWith(color: p.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: NNSpace.lg),
        Segmented<String>(
          key: const ValueKey('avatar-kind'),
          values: const ['photo', 'emoji', 'initial'],
          selected: _kind,
          label: (k) => switch (k) {
            'photo' => s.photo,
            'emoji' => s.avatarEmoji,
            _ => s.avatarInitial,
          },
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: NNSpace.md),
        if (_kind == 'photo')
          Wrap(
            spacing: NNSpace.xs,
            runSpacing: NNSpace.xs,
            children: [
              NNButton(
                key: const ValueKey('choose-photo'),
                label: s.choosePhoto,
                icon: Icons.photo_library_outlined,
                kind: ButtonKind.tinted,
                expand: false,
                busy: _busy,
                onTap: _choosePhoto,
              ),
              if (hasPhoto)
                NNButton(
                  key: const ValueKey('remove-photo'),
                  label: s.removePhoto,
                  kind: ButtonKind.plain,
                  expand: false,
                  onTap: _busy ? null : _removePhoto,
                ),
            ],
          )
        else if (_kind == 'emoji')
          Wrap(
            key: const ValueKey('emoji-grid'),
            spacing: NNSpace.xs,
            runSpacing: NNSpace.xs,
            children: [
              for (var i = 0; i < avatarEmoji.length; i++)
                Pressable(
                  key: ValueKey('emoji-$i'),
                  onTap: () => setState(() => _emoji = avatarEmoji[i]),
                  selected: _emoji == avatarEmoji[i],
                  semanticLabel: avatarEmoji[i],
                  excludeChildSemantics: true,
                  haptic: Haptic.selection,
                  child: AnimatedContainer(
                    duration: NNMotion.fade,
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      shape: CircleBorder(
                        side: BorderSide(
                          color: _emoji == avatarEmoji[i] ? p.accent : p.edge,
                          width: _emoji == avatarEmoji[i] ? 2 : 1,
                        ),
                      ),
                      color: p.surface,
                    ),
                    child: Text(
                      avatarEmoji[i],
                      style: const TextStyle(fontSize: 24, height: 1.1),
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                ),
            ],
          ),
        SectionLabel(s.colour),
        Wrap(
          key: const ValueKey('tones'),
          spacing: NNSpace.xs,
          runSpacing: NNSpace.xs,
          children: [
            for (final t in coverTones)
              Pressable(
                key: ValueKey('tone-$t'),
                onTap: () => setState(() => _tone = t),
                selected: _tone == t,
                semanticLabel: s.raw('tone_$t'),
                excludeChildSemantics: true,
                haptic: Haptic.selection,
                child: AnimatedContainer(
                  duration: NNMotion.fade,
                  width: touchTarget(context),
                  height: touchTarget(context),
                  padding: const EdgeInsets.all(3),
                  decoration: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(
                        color: _tone == t
                            ? p.accent
                            : p.edge.withValues(alpha: 0),
                        width: 2,
                      ),
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: CircleBorder(side: BorderSide(color: p.edge)),
                      color: covers[t]?.bg,
                    ),
                    child: _tone == t
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: covers[t]?.fg,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NNSpace.md),
        NNField(
          label: s.yourName,
          controller: _name,
          fieldKey: const ValueKey('profile-name'),
          textInputAction: TextInputAction.done,
          shake: _error == s.errName ? _shake : 0,
        ),
        if (_error != null) ...[
          const SizedBox(height: NNSpace.xs),
          ErrorText(
            _error!,
            shake: _shake,
            textKey: const ValueKey('profile-error'),
          ),
        ],
        const SizedBox(height: NNSpace.lg),
        NNButton(
          key: const ValueKey('profile-save'),
          label: s.save,
          busy: _busy,
          onTap: _save,
        ),
      ],
    );
  }
}
