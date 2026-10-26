// Dart port of packages/core/src/identity.ts. Change both together; test/parity_extras_test.dart
// replays the TypeScript results.
//
// Identity: how groups and people look. Groups get a drawn icon on a two-tone cover; people get a
// photo, an emoji or their initial on a tone chosen once.

/// Drawn icons for group covers. Each app draws them itself (no emoji in the interface).
const coverIcons = [
  'plane',
  'beach',
  'mountain',
  'car',
  'home',
  'food',
  'coffee',
  'moon',
  'party',
  'gift',
  'cart',
  'heart',
  'ball',
  'work',
  'book',
  'music',
];

/// Tones shared by covers and avatars (tokens.json → covers).
const coverTones = [
  'violet',
  'saffron',
  'mint',
  'coral',
  'sky',
  'rose',
  'slate',
];

bool isCoverIcon(String s) => coverIcons.contains(s);
bool isCoverTone(String s) => coverTones.contains(s);

class Cover {
  const Cover(this.icon, this.tone);
  final String icon;
  final String tone;

  @override
  bool operator ==(Object other) =>
      other is Cover && other.icon == icon && other.tone == tone;

  @override
  int get hashCode => Object.hash(icon, tone);

  @override
  String toString() => coverKey(this);
}

/// "plane:sky" → a cover, or null when it isn't one.
Cover? parseCover(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  final icon = parts.isNotEmpty ? parts[0] : '';
  final tone = parts.length > 1 ? parts[1] : '';
  return icon.isNotEmpty &&
          tone.isNotEmpty &&
          isCoverIcon(icon) &&
          isCoverTone(tone)
      ? Cover(icon, tone)
      : null;
}

String coverKey(Cover c) => '${c.icon}:${c.tone}';

/// FNV-1a over UTF-16 code units: a stable, cheap hash both apps compute the same way.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// A tone picked from a name, so someone without a chosen colour always gets the same one.
String toneFor(String seed) =>
    coverTones[stableHash(seed.trim().toLowerCase()) % coverTones.length];

/// Groups made before covers had an emoji; this is the drawn icon that stands for it.
const _emojiIcons = <String, String>{
  '✈️': 'plane',
  '🧳': 'plane',
  '🌍': 'plane',
  '🏖️': 'beach',
  '🏝️': 'beach',
  '🏔️': 'mountain',
  '🏕️': 'mountain',
  '🚗': 'car',
  '🏠': 'home',
  '🏡': 'home',
  '🏢': 'home',
  '🛋️': 'home',
  '🍽️': 'food',
  '🍕': 'food',
  '🍔': 'food',
  '🥘': 'food',
  '☕': 'coffee',
  '🌙': 'moon',
  '🕌': 'moon',
  '🏮': 'moon',
  '🎉': 'party',
  '🎂': 'party',
  '🎁': 'gift',
  '💍': 'gift',
  '🛒': 'cart',
  '🛍️': 'cart',
  '❤️': 'heart',
  '⚽': 'ball',
  '🏀': 'ball',
  '💼': 'work',
  '📚': 'book',
  '🎵': 'music',
  '🎶': 'music',
};

String _stripVs(String s) => s.replaceAll('️', '');

final _stripped = {
  for (final e in _emojiIcons.entries) _stripVs(e.key): e.value,
};

const _iconTone = <String, String>{
  'plane': 'sky',
  'beach': 'saffron',
  'mountain': 'mint',
  'car': 'slate',
  'home': 'violet',
  'food': 'coral',
  'coffee': 'saffron',
  'moon': 'violet',
  'party': 'rose',
  'gift': 'rose',
  'cart': 'mint',
  'heart': 'rose',
  'ball': 'mint',
  'work': 'slate',
  'book': 'sky',
  'music': 'coral',
};

/// The cover a group shows: its own, or one drawn from its old emoji.
Cover groupCover({String? cover, String? emoji}) {
  final own = parseCover(cover);
  if (own != null) return own;
  final e = (emoji ?? '').trim();
  final icon = _emojiIcons[e] ?? _stripped[_stripVs(e)] ?? 'food';
  return Cover(icon, _iconTone[icon]!);
}

/// The default tone for an icon, used when someone picks an icon and hasn't chosen a colour.
String toneOfIcon(String icon) => _iconTone[icon] ?? 'violet';

/// The first letter of a name, as an avatar shows it ("omar" → "O", "مها" → "م").
String initialOf(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first).toUpperCase();
}

/// How a person looks: their initial or an emoji on a tone, or a photo the API serves at [url]
/// (relative to the API base).
class AvatarLook {
  const AvatarLook.initial(this.tone)
    : kind = 'initial',
      value = null,
      url = null;
  const AvatarLook.emoji(String this.value, this.tone)
    : kind = 'emoji',
      url = null;
  const AvatarLook.photo(String this.url, this.tone)
    : kind = 'photo',
      value = null;

  /// 'initial', 'emoji' or 'photo'.
  final String kind;
  final String tone;
  final String? value;
  final String? url;

  /// The look for someone the server sent nothing for: their initial on the tone of their name.
  factory AvatarLook.forName(String name) => AvatarLook.initial(toneFor(name));

  static AvatarLook? fromJson(Object? j, {String name = ''}) {
    if (j is! Map) return null;
    final raw = j['tone'];
    final tone = raw is String && isCoverTone(raw) ? raw : toneFor(name);
    final value = j['value'];
    final url = j['url'];
    switch (j['kind']) {
      case 'emoji' when value is String && value.isNotEmpty:
        return AvatarLook.emoji(value, tone);
      case 'photo' when url is String && url.isNotEmpty:
        return AvatarLook.photo(url, tone);
      default:
        return AvatarLook.initial(tone);
    }
  }

  Map<String, Object> toJson() => {
    'kind': kind,
    'tone': tone,
    'value': ?value,
    'url': ?url,
  };

  @override
  bool operator ==(Object other) =>
      other is AvatarLook &&
      other.kind == kind &&
      other.tone == tone &&
      other.value == value &&
      other.url == url;

  @override
  int get hashCode => Object.hash(kind, tone, value, url);
}

/// Emoji people can pick for themselves (avatars only; the interface itself uses drawn icons).
const avatarEmoji = [
  '😀',
  '😎',
  '🤓',
  '🥳',
  '🦊',
  '🐱',
  '🐼',
  '🦁',
  '🐢',
  '🐙',
  '🌵',
  '🌻',
  '⚽',
  '🎧',
  '☕',
  '🌙',
];
