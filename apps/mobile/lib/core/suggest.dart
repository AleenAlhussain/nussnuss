// Dart port of packages/core/src/suggest.ts. Change both together.

import 'identity.dart';

/// The time suggestions are based on. Tests that compare screen images pin it, so a title suggested
/// at lunch does not turn into dinner when the tests run in the evening.
DateTime Function() suggestionClock = DateTime.now;

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

const _tripIcons = {'plane', 'beach', 'mountain', 'car'};

/// Ideas for the kind of group and the time of day, most likely first. [kind] is the cover icon
/// (or an old emoji).
List<String> contextIdeas(int hour, [String kind = '']) {
  final icon = isCoverIcon(kind) ? kind : null;
  bool any(List<String> set) => set.any(kind.contains);
  if (icon == 'moon' || any(_ramadan)) {
    return hour >= 0 && hour < 5
        ? ['suhoor', 'iftar', 'groceries']
        : ['iftar', 'suhoor', 'groceries'];
  }
  if ((icon != null && _tripIcons.contains(icon)) || any(_trip)) {
    return [..._meals(hour).take(1), 'taxi', 'hotel', 'tickets', 'fuel'];
  }
  if (icon == 'home' || any(_home)) {
    return ['groceries', 'rent', 'internet', 'electricity'];
  }
  if (icon == 'gift' || icon == 'party' || any(_gifts)) {
    return ['gift', ..._meals(hour).take(1)];
  }
  return [..._meals(hour), 'taxi'];
}

/// Words that name a category, in English and Arabic (normalised: lower case, no diacritics,
/// plain alef).
const _keywords = <String, List<String>>{
  'food': [
    'breakfast',
    'brunch',
    'lunch',
    'dinner',
    'supper',
    'coffee',
    'cafe',
    'café',
    'restaurant',
    'pizza',
    'burger',
    'burgers',
    'shawarma',
    'sushi',
    'kebab',
    'falafel',
    'snack',
    'snacks',
    'dessert',
    'desserts',
    'juice',
    'tea',
    'karak',
    'bakery',
    'iftar',
    'suhoor',
    'sohour',
    'food',
    'meal',
    'takeaway',
    'delivery',
    'bbq',
    'grill',
    'mandi',
    'kabsa',
    'فطور',
    'افطار',
    'غداء',
    'غدا',
    'عشاء',
    'عشا',
    'سحور',
    'قهوه',
    'كافيه',
    'مطعم',
    'بيتزا',
    'برجر',
    'برغر',
    'شاورما',
    'سوشي',
    'كباب',
    'فلافل',
    'حلويات',
    'حلا',
    'عصير',
    'شاي',
    'كرك',
    'مخبز',
    'فطاير',
    'مشاوي',
    'مندي',
    'كبسه',
    'اكل',
    'وجبه',
    'طلبات',
  ],
  'groceries': [
    'groceries',
    'grocery',
    'supermarket',
    'hypermarket',
    'market',
    'vegetables',
    'veggies',
    'fruit',
    'fruits',
    'milk',
    'bread',
    'water',
    'eggs',
    'meat',
    'chicken',
    'بقاله',
    'سوبرماركت',
    'ماركت',
    'هايبر',
    'خضار',
    'خضروات',
    'فواكه',
    'فاكهه',
    'حليب',
    'خبز',
    'ماي',
    'مويه',
    'بيض',
    'لحم',
    'دجاج',
    'مقاضي',
    'تموين',
  ],
  'transport': [
    'taxi',
    'cab',
    'fuel',
    'petrol',
    'gas',
    'diesel',
    'parking',
    'toll',
    'tolls',
    'bus',
    'metro',
    'train',
    'tram',
    'flight',
    'flights',
    'airline',
    'airport',
    'car',
    'rental',
    'ride',
    'ferry',
    'transport',
    'تاكسي',
    'تكسي',
    'بنزين',
    'وقود',
    'ديزل',
    'موقف',
    'مواقف',
    'باركينج',
    'باص',
    'حافله',
    'مترو',
    'قطار',
    'طيران',
    'مطار',
    'سياره',
    'توصيل',
    'مواصلات',
    'عباره',
  ],
  'stay': [
    'hotel',
    'hostel',
    'motel',
    'apartment',
    'resort',
    'room',
    'rooms',
    'chalet',
    'villa',
    'camp',
    'camping',
    'lodge',
    'stay',
    'فندق',
    'شقه',
    'منتجع',
    'غرفه',
    'شاليه',
    'فيلا',
    'استراحه',
    'مخيم',
    'سكن',
  ],
  'fun': [
    'tickets',
    'ticket',
    'cinema',
    'movie',
    'movies',
    'concert',
    'museum',
    'park',
    'zoo',
    'game',
    'games',
    'bowling',
    'karaoke',
    'show',
    'theatre',
    'theater',
    'boat',
    'diving',
    'safari',
    'match',
    'gym',
    'spa',
    'سينما',
    'فيلم',
    'حفله',
    'متحف',
    'حديقه',
    'ملاهي',
    'العاب',
    'بولينج',
    'مسرح',
    'قارب',
    'غوص',
    'سفاري',
    'تذاكر',
    'تذكره',
    'مباراه',
    'نادي',
  ],
  'bills': [
    'rent',
    'internet',
    'wifi',
    'electricity',
    'power',
    'phone',
    'mobile',
    'subscription',
    'cleaning',
    'cleaner',
    'maintenance',
    'insurance',
    'bill',
    'bills',
    'utilities',
    'ايجار',
    'انترنت',
    'كهرباء',
    'كهربا',
    'فاتوره',
    'فواتير',
    'جوال',
    'موبايل',
    'اشتراك',
    'تنظيف',
    'صيانه',
    'تامين',
  ],
  'shopping': [
    'gift',
    'gifts',
    'present',
    'presents',
    'clothes',
    'shoes',
    'mall',
    'shopping',
    'souvenir',
    'souvenirs',
    'electronics',
    'pharmacy',
    'medicine',
    'flowers',
    'هديه',
    'هدايا',
    'ملابس',
    'احذيه',
    'مول',
    'تسوق',
    'صيدليه',
    'دواء',
    'ورد',
    'عطور',
  ],
};

/// Phrases checked before single words ("water bill" is a bill, "water" is groceries).
const _phrases = <(String, String)>[
  ('water bill', 'bills'),
  ('gas bill', 'bills'),
  ('car rental', 'transport'),
  ('rental car', 'transport'),
  ('ice cream', 'food'),
  ('فاتوره ماء', 'bills'),
  ('فاتوره مويه', 'bills'),
  ('واي فاي', 'bills'),
  ('ايجار سياره', 'transport'),
];

final _wordCategory = () {
  final m = <String, String>{};
  for (final e in _keywords.entries) {
    for (final w in e.value) {
      m.putIfAbsent(w, () => e.key);
    }
  }
  return m;
}();

final _diacritics = RegExp('[\u064B-\u0652\u0670\u0640]');
final _alef = RegExp('[أإآٱ]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lower case, Arabic diacritics and tatweel removed, alef/ya/ta marbuta made plain.
String normalizeWords(String s) => s
    .toLowerCase()
    .replaceAll(_diacritics, '')
    .replaceAll(_alef, 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .trim();

/// The category a title names, or null when no word gives it away. "Fuel" → transport,
/// "عشاء" → food.
String? categoryFromTitle(String title) {
  final s = normalizeWords(title);
  if (s.isEmpty) return null;
  for (final (p, cat) in _phrases) {
    if (s.contains(p)) return cat;
  }
  for (final raw in s.split(_nonWord)) {
    if (raw.isEmpty) continue;
    final hit =
        _wordCategory[raw] ??
        (raw.startsWith('ال') && raw.length > 3
            ? _wordCategory[raw.substring(2)]
            : null);
    if (hit != null) return hit;
  }
  return null;
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
