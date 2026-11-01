/// The cover a page shows when its owner has not set one: one of the ten designs of its business group
/// (/defaults/cv/<group>-<n>.jpg, the same sets new members get), picked from the seed so a page keeps its own (the web's
/// defaultCoverStyle). A member's category or, for a contact that has not joined, the words it is saved under
/// (plumber, clinic, sweets…) choose the group.
const _groupOfCategory = {
  'Manufacturing': 'manufacturing',
  'Trading / Wholesale': 'trading',
  'Retail': 'retail',
  'IT & Software': 'it',
  'Logistics & Transport': 'logistics',
  'Construction & Real Estate': 'construction',
  'Food & Beverage': 'food',
  'Healthcare': 'healthcare',
  'Education & Training': 'education',
  'Professional Services': 'professional',
};

final _groupOfWords = <(RegExp, String)>[
  (RegExp(r'doctor|clinic|hospital|dentist|pharmac|medical|nurs|diagnostic|lab\b|physio|health', caseSensitive: false), 'healthcare'),
  (RegExp(r'food|restaurant|cafe|sweet|chaat|snack|biryani|pizza|juice|ice cream|bakery|caterer|tiffin|dhaba|hotel', caseSensitive: false), 'food'),
  (RegExp(r'plumb|electric|carpent|paint|mason|contractor|civil|fabricat|construction|builder|real estate|tiles|interior|welder|ac repair|waterproof', caseSensitive: false), 'construction'),
  (RegExp(r'transport|driver|truck|tempo|rickshaw|cab|taxi|packers|movers|courier|logistic|travel', caseSensitive: false), 'logistics'),
  (RegExp(r'teacher|tuition|coaching|school|class|education|training|academy', caseSensitive: false), 'education'),
  (RegExp(r'lawyer|advocate|\bca\b|accountant|architect|consultant|tax|insurance|notary|astrolog', caseSensitive: false), 'professional'),
  (RegExp(r'computer|software|laptop|mobile|\bit\b|web|cctv|printer', caseSensitive: false), 'it'),
  (RegExp(r'manufactur|factory|industr|works|fabric', caseSensitive: false), 'manufacturing'),
  (RegExp(r'wholesale|trader|trading|supplier', caseSensitive: false), 'trading'),
  (RegExp(r'shop|store|mart|retail|kirana|grocery|salon|parlour|boutique|tailor', caseSensitive: false), 'retail'),
];

String coverGroup({String? userType, String? category, List<String> words = const []}) {
  if (userType == 'job_seeker') return 'job-seeker';
  final c = _groupOfCategory[category ?? ''];
  if (c != null) return c;
  final text = [category ?? '', ...words].join(' ');
  for (final (re, g) in _groupOfWords) {
    if (re.hasMatch(text)) return g;
  }
  return 'other';
}

String defaultCoverUrl(String seed, {String? userType, String? category, List<String> words = const []}) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return '/defaults/cv/${coverGroup(userType: userType, category: category, words: words)}-${h % 10 + 1}.jpg';
}
