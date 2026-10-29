import 'i18n.dart';
import 'models.dart';

/// What an ask wants from members (web constants.ts ASK_TYPES): the one thing the asker picks, "What is your ask".
/// Its topic stays in the category; a few types fix it (a hire is always a job).
class AskTypeDef {
  final String value, label, short, hint, icon, emoji, fallback;
  final String? forced;
  const AskTypeDef(this.value, this.label, this.short, this.hint, this.icon, this.emoji, this.fallback, [this.forced]);
}

const kAskTypes = [
  AskTypeDef('hire', 'I want to hire someone', 'Hire', 'Staff, workers, freelancers', 'job', '👷', 'job', 'job'),
  AskTypeDef('quote', 'I need something or a service', 'Buy / Quote', 'Suppliers, repairs, a space, transport: get quotes', 'quote', '🔎', 'supplier'),
  AskTypeDef('offer', 'I have something to sell or rent', 'Sell / Offer', 'Goods, machines, a shop or godown', 'offer', '🏷️', 'buyer'),
  AskTypeDef('advice', 'I need advice', 'Advice', 'A question or an opinion', 'advice', '💡', 'advice'),
  AskTypeDef('poll', 'I want a vote', 'Poll', 'Let members choose between options', 'poll', '🗳️', 'advice'),
  AskTypeDef('recommend', 'Who do you recommend?', 'Recommend', 'Ask for a trusted name', 'recommend', '⭐', 'advice'),
  AskTypeDef('visit', 'I want members to visit my website', 'Visit', 'Share a link to your website or page', 'visit', '🔗', 'digital'),
  AskTypeDef('partner', 'I am looking for a partner', 'Partner', 'Co-founder, joint venture, franchise', 'partnership', '🤝', 'partnership', 'partnership'),
  AskTypeDef('funding', 'I am looking for funding', 'Funding', 'Loan, investor, working capital', 'funding', '💰', 'funding', 'funding'),
  AskTypeDef('other', 'Something else', 'Other', 'Say what it is in a few words', 'other', '💬', 'other', 'other'),
];

AskTypeDef? askTypeDef(String? v) {
  for (final t in kAskTypes) {
    if (t.value == v) return t;
  }
  return null;
}

/// The label of an ask, the same on the card's category line and on its first card: its type, then its topic ("Sell / Offer · Jobs / Manpower").
String askLabel(Post post) {
  final type = askTypeDef(askTypeOf(post)) ?? kAskTypes.last;
  if (post.category == 'other' && (post.categoryLabel ?? '').isNotEmpty) return post.categoryLabel!;
  return t(type.short);
}

/// an older ask (or one from before types) has the type its category implies
String typeOfCategory(String? c) {
  if (c == 'job') return 'hire';
  if (c == 'buyer' || c == 'machinery') return 'offer';
  if (c == 'advice' || c == 'mentorship') return 'advice';
  if (c == 'partnership') return 'partner';
  if (c == 'funding') return 'funding';
  if (c == 'other' || c == null || c.isEmpty) return 'other';
  return 'quote';
}

/// the category a type gives an ask: its own when it fixes one, else the words' topic when it fits, else its fallback
String categoryForType(String type, String? current) {
  final t = askTypeDef(type);
  if (t == null) return (current ?? '').isEmpty ? 'other' : current!;
  if (t.forced != null) return t.forced!;
  return (current ?? '').isNotEmpty && typeOfCategory(current) == type ? current! : t.fallback;
}

const kCategoryNoun = {
  'supplier': 'a supplier',
  'logistics': 'transport',
  'space': 'a space',
  'repair': 'a repair service',
  'digital': 'digital help',
  'printing': 'printing help',
  'events': 'event services',
  'rental': 'a vehicle or equipment on rent',
  'wellness': 'a wellness service',
  'daily': 'a home service',
  'jobwork': 'a job work partner',
  'compliance': 'GST or legal help',
  'consultant': 'a consultant',
  'export': 'export help',
  'tender': 'a tender',
  'training': 'training',
};

/// The ask's type: its own, else the one its category implies.
String askTypeOf(Post p) => p.askType ?? typeOfCategory(p.category);

/// the one line that says what the ask is, in the asker's name ("SkyQ is looking for a space"): the key and its values
({String key, Map<String, String> vars}) askSentence(Post p) {
  final name = p.authorType == 'entrepreneur' && p.authorCompany.isNotEmpty ? p.authorCompany : p.authorName.split(' ').first;
  final noun = kCategoryNoun[p.category ?? ''];
  switch (askTypeOf(p)) {
    case 'hire':
      return (key: '{name} is looking to hire someone', vars: {'name': name});
    case 'quote':
      return noun != null ? (key: '{name} is looking for {what}', vars: {'name': name, 'what': noun}) : (key: '{name} needs something and wants quotes', vars: {'name': name});
    case 'offer':
      return (key: '{name} has something to offer', vars: {'name': name});
    case 'advice':
      return (key: '{name} wants your advice', vars: {'name': name});
    case 'poll':
      return (key: '{name} wants your vote', vars: {'name': name});
    case 'recommend':
      return (key: '{name} wants a recommendation', vars: {'name': name});
    case 'visit':
      return (key: '{name} invites you to visit their website', vars: {'name': name});
    case 'partner':
      return (key: '{name} is looking for a partner', vars: {'name': name});
    case 'funding':
      return (key: '{name} is looking for funding', vars: {'name': name});
    default:
      return (key: '{name} has an ask for you', vars: {'name': name});
  }
}
