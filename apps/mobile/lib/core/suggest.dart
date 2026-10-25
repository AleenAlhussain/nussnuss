// Dart port of packages/core/src/suggest.ts. Change both together.

/// Words the apps translate: `sug_$key` in the i18n files.
const suggestionKeys = [
  'breakfast',
  'coffee',
  'lunch',
  'dinner',
  'groceries',
  'taxi',
  'fuel',
  'hotel',
  'tickets',
  'rent',
  'internet',
  'electricity',
  'iftar',
  'suhoor',
  'gift',
];

class Suggestion {
  const Suggestion({required this.category, this.title, this.key});

  /// A title used in this group before, shown as it was typed.
  final String? title;

  /// Or an idea to translate.
  final String? key;
  final String category;

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.title == title &&
      other.key == key &&
      other.category == category;

  @override
  int get hashCode => Object.hash(title, key, category);

  @override
  String toString() => 'Suggestion(${title ?? key}, $category)';
}

const _ideas = {
  'breakfast': 'food',
  'coffee': 'food',
  'lunch': 'food',
  'dinner': 'food',
  'groceries': 'groceries',
  'taxi': 'transport',
  'fuel': 'transport',
  'hotel': 'stay',
  'tickets': 'fun',
  'rent': 'bills',
  'internet': 'bills',
  'electricity': 'bills',
  'iftar': 'food',
  'suhoor': 'food',
  'gift': 'shopping',
};

const _trip = ['✈️', '🏖️', '🏝️', '🏔️', '🚗', '🏕️', '🌍', '🧳'];
const _home = ['🏠', '🏡', '🏢', '🛋️'];
const _ramadan = ['🌙', '🕌', '🏮'];
const _gifts = ['🎁', '🎉', '💍', '🎂'];

List<String> _meals(int hour) {
  if (hour >= 5 && hour < 11) return ['breakfast', 'coffee'];
  if (hour >= 11 && hour < 16) return ['lunch', 'coffee'];
  if (hour >= 16 && hour < 18) return ['coffee', 'groceries'];
  return ['dinner', 'groceries'];
}

/// Ideas for the kind of group and the time of day, most likely first.
List<String> contextIdeas(int hour, [String emoji = '']) {
  bool any(List<String> set) => set.any(emoji.contains);
  if (any(_ramadan)) {
    return hour >= 0 && hour < 5
        ? ['suhoor', 'iftar', 'groceries']
        : ['iftar', 'suhoor', 'groceries'];
  }
  if (any(_trip)) {
    return [..._meals(hour).take(1), 'taxi', 'hotel', 'tickets', 'fuel'];
  }
  if (any(_home)) return ['groceries', 'rent', 'internet', 'electricity'];
  if (any(_gifts)) return ['gift', ..._meals(hour).take(1)];
  return [..._meals(hour), 'taxi'];
}

/// Up to [n] suggestions for an expense title: this group's most recent
/// distinct titles first (people repeat themselves), then ideas for the time
/// of day and the kind of group. [label] translates an idea, so an idea that
/// matches a recent title is not offered twice.
List<Suggestion> suggestTitles({
  required List<({String title, String category})> recent,
  required int hour,
  String emoji = '',
  int n = 4,
  String Function(String key)? label,
}) {
  final out = <Suggestion>[];
  final seen = <String>{};
  final firstRecent = n < 2 ? n : 2;
  for (final e in recent) {
    final k = e.title.trim().toLowerCase();
    if (k.isEmpty || seen.contains(k)) continue;
    seen.add(k);
    out.add(Suggestion(title: e.title.trim(), category: e.category));
    if (out.length >= firstRecent) break;
  }
  for (final key in contextIdeas(hour, emoji)) {
    if (out.length >= n) break;
    final k = (label?.call(key) ?? key).trim().toLowerCase();
    if (seen.contains(k)) continue;
    seen.add(k);
    out.add(Suggestion(key: key, category: _ideas[key]!));
  }
  return out;
}
