/// Domain models and option lists. Mirrors web/src/lib/types.ts and web/src/lib/constants.ts
/// (same names, same JSON the API returns), so the app and the web stay in step.
library;

DateTime _ms(dynamic v) => DateTime.fromMillisecondsSinceEpoch((v as num?)?.toInt() ?? 0);
DateTime? _msOpt(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
List<String> _strings(dynamic v) => ((v as List?) ?? const []).map((e) => '$e').toList();

// ===================== option lists (web/src/lib/constants.ts) =====================

class Option {
  final String value, label;
  const Option(this.value, this.label);
}

const kUserTypes = [Option('entrepreneur', 'Entrepreneur'), Option('job_seeker', 'Job Seeker')];

const kProfileCategories = [
  Option('Manufacturing', 'Manufacturing'), Option('Trading / Wholesale', 'Trading / Wholesale'), Option('Retail', 'Retail'),
  Option('IT & Software', 'IT & Software'), Option('Logistics & Transport', 'Logistics & Transport'),
  Option('Construction & Real Estate', 'Construction & Real Estate'), Option('Food & Beverage', 'Food & Beverage'),
  Option('Healthcare', 'Healthcare'), Option('Education & Training', 'Education & Training'),
  Option('Professional Services', 'Professional Services'), Option('Other', 'Other'),
];

const kPostCategories = [
  Option('job', 'Job / Manpower Requirement'),
  Option('supplier', 'Supplier / Vendor Requirement'),
  Option('buyer', 'Buyer / Customer Requirement'),
  Option('logistics', 'Logistics / Transport / Warehouse Requirement'),
  Option('funding', 'Funding / Investment Requirement'),
  Option('advice', 'Advice / Suggestion Needed'),
  Option('mentorship', 'Free Advice / Mentorship Offer'),
  Option('partnership', 'Partnership / Collaboration'),
  Option('machinery', 'Machinery / Equipment for Sale or Rent'),
  Option('space', 'Space / Office / Godown Requirement'),
  Option('training', 'Training / Skill Development'),
  Option('jobwork', 'Job Work / Contract Manufacturing'),
  Option('compliance', 'GST / Compliance / Legal Help'),
  Option('consultant', 'Consultant / Advisor Needed'),
  Option('export', 'Export / Import Help'),
  Option('tender', 'Tender / Government Order'),
  Option('digital', 'Website / Digital Marketing'),
  Option('repair', 'Repair / Maintenance Service'),
  Option('other', 'Other'),
];

const kCategoryShort = {
  'job': 'Jobs / Manpower', 'supplier': 'Supplier / Vendor', 'buyer': 'Buyer / Customer', 'logistics': 'Logistics',
  'funding': 'Funding', 'advice': 'Advice', 'mentorship': 'Mentorship', 'partnership': 'Partnership',
  'machinery': 'Machinery', 'space': 'Space / Godown', 'training': 'Training', 'jobwork': 'Job work',
  'compliance': 'GST / Legal', 'consultant': 'Consultant / Advisor', 'export': 'Export / Import', 'tender': 'Tenders', 'digital': 'Digital',
  'repair': 'Repair / AMC', 'other': 'Other',
};

const kUrgencies = [Option('immediate', 'Immediate'), Option('7_days', 'Within 7 days'), Option('30_days', 'Within 30 days'), Option('flexible', 'Flexible')];

String labelOf(List<Option> options, String? value) {
  if (value == null) return '';
  for (final o in options) {
    if (o.value == value) return o.label;
  }
  return value;
}

/// web verified-badge.tsx VERIFICATION_LABEL / VERIFICATION_HOW
const kVerificationLabel = {0: 'Not verified', 1: 'Contact verified', 2: 'Documents verified', 3: 'Owner verified'};
const kVerificationHow = {
  0: 'No verification badge yet.',
  1: 'Confirmed with a one-time code on their mobile number or email.',
  2: 'A valid GST number was added to the profile.',
  3: 'Documents verified and a proven track record of 3+ positive ratings.',
};

const kReactions = ['heart', 'thumbs', 'namaskar'];
const kReactionEmoji = {'heart': '❤️', 'thumbs': '👍', 'namaskar': '🙏'};

// ===================== profile =====================

/// Profile strength (own profile only): what is done and what to add next.
class CompletionItem {
  final String key, label;
  final int weight;
  final bool done;
  const CompletionItem(this.key, this.label, this.weight, this.done);
}

class Completion {
  final int percent;
  final List<CompletionItem> items;
  final List<String> badges;
  const Completion(this.percent, this.items, this.badges);
  factory Completion.fromJson(Map j) => Completion(
        (j['percent'] as num?)?.toInt() ?? 0,
        ((j['items'] as List?) ?? const [])
            .map((e) => e as Map)
            .map((e) => CompletionItem('${e['key']}', '${e['label']}', (e['weight'] as num?)?.toInt() ?? 0, e['done'] == true))
            .toList(),
        _strings(j['badges']),
      );
  /// The undone item worth the most.
  CompletionItem? get next {
    final todo = items.where((i) => !i.done).toList()..sort((a, b) => b.weight.compareTo(a.weight));
    return todo.isEmpty ? null : todo.first;
  }
}

/// A UPI ID on a member's page (web UpiId).
class UpiId {
  final String id, vpa;
  final bool isDefault;
  /// the account holder's name as the bank holds it, when the UPI ID was verified (Razorpay)
  final String? verifiedName;
  const UpiId({required this.id, required this.vpa, this.isDefault = false, this.verifiedName});
  factory UpiId.fromJson(Map j) =>
      UpiId(id: '${j['id']}', vpa: '${j['vpa']}', isDefault: j['isDefault'] == true, verifiedName: j['verifiedName'] as String?);
}

class Profile {
  final String uid, handle, name, company, userType, category, location;
  final String? photoUrl, bannerUrl, bio, experience, education, contactMasked;
  /// Public GSTIN (businesses); `gstNumber` on /me, `gstin` on public profiles.
  final String? gstin;
  /// Only on your own profile (GET /me).
  final Completion? completion;
  final List<String> services, skills;
  final int contributions;
  final int? statPosts, statShared;
  /// asks whose owner chose them ("deals won")
  final int statWon;
  /// 0 none, 1 mobile verified, 2 documents, 3 owner verified
  final int verification;
  /// WEBWEB Premium: given only by an admin, shown next to the earned badge
  final bool premium;
  /// paid plan below Premium ('plus' < 'pro'), while it runs
  final String? plan;
  /// has a live update (gold ring on the avatar)
  final bool hasUpdate;
  /// UPI IDs linked to the page, the default first
  final List<UpiId> upi;
  final DateTime createdAt;

  const Profile({
    required this.uid, required this.handle, required this.name, required this.company, required this.userType,
    required this.category, required this.location, this.photoUrl, this.bannerUrl, this.gstin, this.completion, this.bio, this.experience, this.education,
    this.contactMasked, this.services = const [], this.skills = const [], this.contributions = 0,
    this.statPosts, this.statShared, this.statWon = 0, this.verification = 1, this.premium = false, this.plan, this.hasUpdate = false, this.upi = const [], required this.createdAt,
  });

  bool get isEntrepreneur => userType == 'entrepreneur';
  bool get isJobSeeker => userType == 'job_seeker';

  factory Profile.fromJson(Map j) {
    final stats = j['stats'] as Map?;
    return Profile(
      uid: '${j['uid']}', handle: '${j['handle'] ?? ''}', name: '${j['name'] ?? ''}', company: '${j['company'] ?? ''}',
      userType: '${j['userType'] ?? 'entrepreneur'}', category: '${j['category'] ?? ''}', location: '${j['location'] ?? ''}',
      photoUrl: j['photoURL'] as String?, bannerUrl: j['bannerURL'] as String?,
      gstin: (j['gstin'] ?? j['gstNumber']) as String?,
      completion: j['completion'] == null ? null : Completion.fromJson(j['completion'] as Map),
      bio: j['bio'] as String?, experience: j['experience'] as String?,
      education: j['education'] as String?, contactMasked: j['contactMasked'] as String?,
      services: _strings(j['services']), skills: _strings(j['skills']),
      contributions: (j['contributions'] as num?)?.toInt() ?? (stats?['contributions'] as num?)?.toInt() ?? 0,
      statPosts: (stats?['posts'] as num?)?.toInt(), statShared: (stats?['shared'] as num?)?.toInt(), statWon: (stats?['won'] as num?)?.toInt() ?? 0,
      verification: (j['verificationLevel'] as num?)?.toInt() ?? 1, premium: j['premium'] == true, plan: j['plan'] as String?, hasUpdate: stats?['hasUpdate'] == true,
      upi: [for (final u in (j['upi'] as List?) ?? const []) UpiId.fromJson(u as Map)],
      createdAt: _ms(j['createdAt']),
    );
  }
}

// ===================== posts =====================

class ResponseLog {
  final String uid, name, handle, kind; // kind: contact | media | info | referral
  final String userType, company;
  final int verification;
  final String? photoUrl, reaction;
  /// a text reply's words / a photo reply's picture (public for the newest replies; never a shared number)
  final String? text, imageUrl;
  final int? rating;
  final DateTime createdAt;
  /// on the card's latest replies: members' reactions and replies to this reply, and mine
  final int reactionsCount, repliesCount;
  final String? myReaction;
  /// "I can do this": an offer, with an optional price and when (today | week | month)
  final bool canDo;
  final String? quote, readyWhen;
  ResponseLog({required this.uid, required this.name, required this.handle, required this.kind, this.userType = 'entrepreneur', this.company = '', this.verification = 0, this.photoUrl, this.reaction, this.rating, this.text, this.imageUrl, required this.createdAt, this.reactionsCount = 0, this.repliesCount = 0, this.myReaction, this.canDo = false, this.quote, this.readyWhen});
  factory ResponseLog.fromJson(Map j) => ResponseLog(
        uid: '${j['uid']}', name: '${j['name']}', handle: '${j['handle'] ?? ''}', kind: '${j['kind']}', photoUrl: j['photoURL'] as String?,
        userType: '${j['userType'] ?? 'entrepreneur'}', company: '${j['company'] ?? ''}', verification: (j['verification'] as num?)?.toInt() ?? 0,
        reaction: j['reaction'] as String?, rating: (j['rating'] as num?)?.toInt(), createdAt: _ms(j['createdAt']),
        text: j['text'] as String?, imageUrl: j['imageUrl'] as String?,
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, repliesCount: (j['repliesCount'] as num?)?.toInt() ?? 0,
        myReaction: j['myReaction'] as String?,
        canDo: j['canDo'] == true, quote: j['quote'] as String?, readyWhen: j['readyWhen'] as String?,
      );
}

/// A reply to a reply (one level deep, as on x.com).
class ReplyComment {
  final int id;
  final String text, uid, name, company, userType, handle;
  final int verification, reactionsCount;
  final String? photoUrl, myReaction;
  final DateTime createdAt;
  ReplyComment({required this.id, required this.text, required this.uid, required this.name, this.company = '', this.userType = 'entrepreneur', required this.handle, this.verification = 0, this.reactionsCount = 0, this.photoUrl, this.myReaction, required this.createdAt});
  factory ReplyComment.fromJson(Map j) => ReplyComment(
        id: (j['id'] as num).toInt(), text: '${j['text']}', uid: '${j['uid']}', name: '${j['name']}', company: '${j['company'] ?? ''}',
        userType: '${j['userType'] ?? 'entrepreneur'}', handle: '${j['handle'] ?? ''}', verification: (j['verification'] as num?)?.toInt() ?? 0,
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, photoUrl: j['photoURL'] as String?, myReaction: j['myReaction'] as String?,
        createdAt: _ms(j['createdAt']),
      );
  String get display => userType == 'entrepreneur' && company.isNotEmpty ? company : name;
}

/// Who referred contacts on an ask, with how many (the people referred are never shown).
class Referrer {
  final String name, handle;
  final int n;
  const Referrer(this.name, this.handle, this.n);
  factory Referrer.fromJson(Map j) => Referrer('${j['name']}', '${j['handle'] ?? ''}', (j['n'] as num?)?.toInt() ?? 1);
}

class Post {
  final String id, kind, authorUid, authorName, authorCompany, authorHandle; // kind: requirement | update
  final String? authorPhotoUrl, title, description, category, locationPref, budget, urgency, matchReason, slug, categoryLabel;
  final String authorType;
  final int authorVerification;
  final bool authorPremium;
  final String? authorPlan;
  /// Metres from the viewer's area (matched feed only).
  final num? distanceM;
  /// Reach circle picked on the map, in metres.
  final num? radiusM;
  /// Centre of the reach circle (rounded to about 1 km).
  final double? lat, lng;
  /// When the owner last changed the ask.
  final DateTime? editedAt;
  /// when [repostedByName] reposted it (Connect and a member's page)
  final DateTime? repostedAt;
  /// On a member's page: the member who reposted this ask (it is someone else's).
  final String? repostedByName, repostedByHandle;
  /// the reposter as the repost's own header shows them (x.com style): uid, photoURL, userType, verification, premium, plan
  final Map<String, dynamic>? repostedBy;
  final List<String> images;
  final int sharesCount;
  final bool authorHasUpdate;
  final DateTime createdAt;
  final List<ResponseLog> recentResponses;
  /// the card's "Latest replies": the 3 newest replies with what they said
  final List<ResponseLog> latestReplies;
  final List<Referrer> referrers;
  // viewer state (changes locally for optimistic updates)
  int reactionsCount, repostsCount, referralsCount;
  /// members who have seen it (each once, never the author)
  int viewsCount;
  bool reacted, reposted, bookmarked;
  String? myReaction;
  /// how the ask ended (found_here | found_elsewhere | not_needed); a closed ask takes no new replies
  final String? outcome;
  /// the member the owner chose (found here)
  final String? wonBy;
  /// on "Leads for you": why it fits, and whether the member has seen it yet
  final String? leadReason;
  final bool leadNew;

  Post({
    required this.id, required this.kind, required this.authorUid, required this.authorName, required this.authorCompany,
    required this.authorHandle, this.authorPhotoUrl, this.title, this.description, this.category, this.locationPref, this.budget,
    this.urgency, this.matchReason, this.slug, this.categoryLabel, this.authorType = 'entrepreneur', this.authorVerification = 1, this.authorPremium = false, this.authorPlan, this.distanceM, this.radiusM, this.lat, this.lng, this.editedAt, this.repostedByName, this.repostedByHandle, this.repostedBy, this.repostedAt, this.images = const [], this.sharesCount = 0, this.authorHasUpdate = false, required this.createdAt,
    this.recentResponses = const [], this.latestReplies = const [], this.referrers = const [], this.reactionsCount = 0, this.repostsCount = 0, this.referralsCount = 0, this.viewsCount = 0,
    this.reacted = false, this.reposted = false, this.bookmarked = false, this.myReaction,
    this.outcome, this.wonBy, this.leadReason, this.leadNew = false,
  });

  bool get closed => outcome != null;

  bool get isRequirement => kind == 'requirement';
  String get shownName => authorType == 'entrepreneur' && authorCompany.isNotEmpty ? authorCompany : authorName;
  /// Category chip text: own label for "Other", else the short name.
  String get categoryText => category == 'other' && (categoryLabel ?? '').isNotEmpty ? categoryLabel! : (kCategoryShort[category] ?? 'Ask');

  /// Public link, same as the web (`/@handle/ask/slug`).
  String get webUrl => isRequirement && authorHandle.isNotEmpty ? 'https://webweb.ai/@$authorHandle/ask/${slug ?? id}' : 'https://webweb.ai/post/$id';

  factory Post.fromJson(Map j) => Post(
        id: '${j['id']}', kind: '${j['kind']}', authorUid: '${j['authorUid']}', authorName: '${j['authorName']}',
        authorCompany: '${j['authorCompany'] ?? ''}', authorHandle: '${j['authorHandle'] ?? ''}', authorPhotoUrl: j['authorPhotoURL'] as String?,
        title: j['title'] as String?, description: j['description'] as String?, category: j['category'] as String?,
        locationPref: j['locationPref'] as String?, budget: j['budget'] as String?, urgency: j['urgency'] as String?,
        matchReason: j['matchReason'] as String?, slug: j['slug'] as String?, categoryLabel: j['categoryLabel'] as String?,
        authorType: '${j['authorType'] ?? 'entrepreneur'}', authorVerification: (j['authorVerification'] as num?)?.toInt() ?? 1, authorPremium: j['authorPremium'] == true, authorPlan: j['authorPlan'] as String?, distanceM: j['distanceM'] as num?, radiusM: j['radiusM'] as num?,
        lat: (j['lat'] as num?)?.toDouble(), lng: (j['lng'] as num?)?.toDouble(), editedAt: j['editedAt'] == null ? null : _ms(j['editedAt']),
        repostedByName: (j['repostedBy'] as Map?)?['name'] as String?, repostedByHandle: (j['repostedBy'] as Map?)?['handle'] as String?,
        repostedBy: j['repostedBy'] == null ? null : Map<String, dynamic>.from(j['repostedBy'] as Map),
        repostedAt: j['repostedAt'] == null ? null : _ms(j['repostedAt']),
        images: _strings(j['images']), sharesCount: (j['sharesCount'] as num?)?.toInt() ?? 0,
        authorHasUpdate: j['authorHasUpdate'] == true, createdAt: _ms(j['createdAt']),
        recentResponses: ((j['recentResponses'] as List?) ?? const []).map((e) => ResponseLog.fromJson(e as Map)).toList(),
        latestReplies: ((j['latestReplies'] as List?) ?? const []).map((e) => ResponseLog.fromJson(e as Map)).toList(),
        referrers: ((j['referrers'] as List?) ?? const []).map((e) => Referrer.fromJson(e as Map)).toList(),
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, viewsCount: (j['viewsCount'] as num?)?.toInt() ?? 0, repostsCount: (j['repostsCount'] as num?)?.toInt() ?? 0,
        referralsCount: (j['referralsCount'] as num?)?.toInt() ?? 0, reacted: j['reacted'] == true, reposted: j['reposted'] == true,
        bookmarked: j['bookmarked'] == true, myReaction: j['myReaction'] as String? ?? (j['reacted'] == true ? 'heart' : null),
        outcome: j['outcome'] as String?, wonBy: j['wonBy'] as String?, leadReason: j['leadReason'] as String?, leadNew: j['leadNew'] == true,
      );
}

/// What the viewer already did on someone's ask (GET /posts/:id/share/me).
class MyResponse {
  final bool shared;
  final String? kind, askStatus, ownerReaction;
  /// your own content (info text / photo), for editing
  final String? text, imageUrl;
  final int? rating;
  final bool canDo;
  final String? quote, readyWhen;
  const MyResponse({required this.shared, this.kind, this.askStatus, this.ownerReaction, this.text, this.imageUrl, this.rating, this.canDo = false, this.quote, this.readyWhen});
  factory MyResponse.fromJson(Map j) => MyResponse(
        shared: j['shared'] == true, kind: j['kind'] as String?, askStatus: j['askStatus'] as String?,
        ownerReaction: j['ownerReaction'] as String?, text: j['text'] as String?, imageUrl: j['imageUrl'] as String?,
        rating: (j['rating'] as num?)?.toInt(), canDo: j['canDo'] == true, quote: j['quote'] as String?, readyWhen: j['readyWhen'] as String?,
      );
}

/// Owner's view of one response (content only after the responder approved).
class ContactShare {
  final String id, sharerUid, sharerName, sharerCompany, kind;
  final String? sharerType, sharerHandle, sharerPhotoUrl, askStatus, ownerReaction, payload;
  /// a photo sent with a note (kind info)
  final String? imageUrl;
  final int? rating;
  final bool revealed;
  final DateTime createdAt;
  final bool canDo;
  final String? quote, readyWhen;
  ContactShare({
    this.id = '', required this.sharerUid, required this.sharerName, required this.sharerCompany, required this.kind, this.sharerType, this.sharerHandle,
    this.sharerPhotoUrl, this.askStatus, this.ownerReaction, this.payload, this.imageUrl, this.rating, required this.revealed, required this.createdAt,
    this.canDo = false, this.quote, this.readyWhen,
  });
  factory ContactShare.fromJson(Map j) => ContactShare(
        id: '${j['id'] ?? j['sharerUid']}', sharerUid: '${j['sharerUid']}', sharerName: '${j['sharerName']}', sharerCompany: '${j['sharerCompany'] ?? ''}', kind: '${j['kind']}',
        sharerType: j['sharerType'] as String?, sharerHandle: j['sharerHandle'] as String?, sharerPhotoUrl: j['sharerPhotoURL'] as String?, askStatus: j['askStatus'] as String?,
        ownerReaction: j['ownerReaction'] as String?, payload: j['payload'] as String?, imageUrl: j['imageUrl'] as String?, rating: (j['rating'] as num?)?.toInt(),
        revealed: j['revealed'] == true, createdAt: _ms(j['createdAt']),
        canDo: j['canDo'] == true, quote: j['quote'] as String?, readyWhen: j['readyWhen'] as String?,
      );
}

/// A third party's contact referred on an ask (owner sees all; a referrer sees their own).
class Referral {
  final String id, name, phone;
  final String? note, referrerName, referrerHandle, referrerUid, referrerPhotoUrl;
  final DateTime createdAt;
  Referral({required this.id, required this.name, required this.phone, this.note, this.referrerName, this.referrerHandle, this.referrerUid, this.referrerPhotoUrl, required this.createdAt});
  factory Referral.fromJson(Map j) => Referral(
        id: '${j['id']}', name: '${j['name']}', phone: '${j['phone']}', note: j['note'] as String?,
        referrerName: j['referrerName'] as String?, referrerHandle: j['referrerHandle'] as String?,
        referrerUid: j['referrerUid'] as String?, referrerPhotoUrl: j['referrerPhotoURL'] as String?, createdAt: _ms(j['createdAt']),
      );
}

/// "Owner asked me to reveal what I shared" (GET /posts/asks/me).
class AskItem {
  final String postId, postTitle, kind, ownerName, ownerCompany;
  final DateTime createdAt;
  AskItem({required this.postId, required this.postTitle, required this.kind, required this.ownerName, required this.ownerCompany, required this.createdAt});
  factory AskItem.fromJson(Map j) => AskItem(
        postId: '${j['postId']}', postTitle: '${j['postTitle']}', kind: '${j['kind']}', ownerName: '${j['ownerName']}',
        ownerCompany: '${j['ownerCompany'] ?? ''}', createdAt: _ms(j['createdAt']),
      );
}

/// What I shared on other people's asks, with feedback.
/// Connects on a profile: an ask this member answered, who asked it, how they answered (never the contact itself),
/// the asker's feedback and how the ask ended.
class Deal {
  final String postId, postTitle, ownerName, ownerCompany, ownerHandle, kind;
  final String? postSlug, category, categoryLabel, ownerUid, ownerType, ownerPhotoUrl, outcome, quote, readyWhen;
  final int ownerVerification;
  final bool canDo;
  final int? rating;
  final String? reaction;
  final DateTime createdAt;
  /// the owner chose them for this ask
  final bool won;
  Deal({required this.postId, required this.postTitle, required this.ownerName, required this.ownerCompany, required this.ownerHandle, required this.kind, this.rating, this.reaction, required this.createdAt, this.won = false,
      this.postSlug, this.category, this.categoryLabel, this.ownerUid, this.ownerType, this.ownerPhotoUrl, this.ownerVerification = 1, this.outcome, this.canDo = false, this.quote, this.readyWhen});
  String get askerName => (ownerType ?? 'entrepreneur') == 'entrepreneur' && ownerCompany.isNotEmpty ? ownerCompany : ownerName;
  String get categoryText => category == 'other' && (categoryLabel ?? '').isNotEmpty ? categoryLabel! : (kCategoryShort[category] ?? 'Ask');
  factory Deal.fromJson(Map j) => Deal(
        postId: '${j['postId']}', postTitle: '${j['postTitle']}', ownerName: '${j['ownerName']}', ownerCompany: '${j['ownerCompany'] ?? ''}',
        ownerHandle: '${j['ownerHandle'] ?? ''}', kind: '${j['kind']}', rating: (j['rating'] as num?)?.toInt(), reaction: j['reaction'] as String?,
        createdAt: _ms(j['createdAt']), won: j['won'] == true,
        postSlug: j['postSlug'] as String?, category: j['category'] as String?, categoryLabel: j['categoryLabel'] as String?,
        ownerUid: j['ownerUid'] as String?, ownerType: j['ownerType'] as String?, ownerPhotoUrl: j['ownerPhotoURL'] as String?,
        ownerVerification: (j['ownerVerification'] as num?)?.toInt() ?? 1, outcome: j['outcome'] as String?,
        canDo: j['canDo'] == true, quote: j['quote'] as String?, readyWhen: j['readyWhen'] as String?,
      );
}

// ===================== leads & your week (P1) =====================

/// "Leads for you" on the Connect header: new (unseen), open, and arrived this week.
class LeadSummary {
  final int unseen, open, week;
  final String? category, location;
  /// false: nothing to match on yet, so the header asks what they do
  final bool hasTrade;
  const LeadSummary({this.unseen = 0, this.open = 0, this.week = 0, this.category, this.location, this.hasTrade = true});
  factory LeadSummary.fromJson(Map j) => LeadSummary(
        unseen: (j['unseen'] as num?)?.toInt() ?? 0, open: (j['open'] as num?)?.toInt() ?? 0, week: (j['week'] as num?)?.toInt() ?? 0,
        category: j['category'] as String?, location: j['location'] as String?, hasTrade: j['hasTrade'] != false,
      );
}

/// "Your week": the last 7 days, and rank in trade (and area).
class WeekStats {
  final String? category, location;
  final int leads, replied, won, wonTotal, askViews, responsesReceived, newAsksInTrade, openLeads;
  final int? rank, rankOf;
  final String? rankArea;
  const WeekStats({this.category, this.location, this.leads = 0, this.replied = 0, this.won = 0, this.wonTotal = 0, this.askViews = 0, this.responsesReceived = 0, this.newAsksInTrade = 0, this.openLeads = 0, this.rank, this.rankOf, this.rankArea});
  bool get hasNews => leads + replied + won + responsesReceived + askViews > 0;
  factory WeekStats.fromJson(Map j) {
    final r = j['rank'] as Map?;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return WeekStats(
      category: j['category'] as String?, location: j['location'] as String?, leads: n('leads'), replied: n('replied'), won: n('won'),
      wonTotal: n('wonTotal'), askViews: n('askViews'), responsesReceived: n('responsesReceived'), newAsksInTrade: n('newAsksInTrade'),
      openLeads: n('openLeads'), rank: (r?['rank'] as num?)?.toInt(), rankOf: (r?['of'] as num?)?.toInt(), rankArea: r?['area'] as String?,
    );
  }
}

// ===================== catalog & stories =====================

class Product {
  final String id, name, kind; // kind: product | service
  final bool available;
  final String? price, description, imageUrl, category;
  /// short public id: /@handle/item/<slug>
  final String? slug;
  Product({required this.id, required this.name, required this.kind, this.available = true, this.price, this.description, this.imageUrl, this.category, this.slug});
  /// Public link path, like an ask's (`/@handle/item/slug`); older items without a slug use `?item=<id>`.
  String pathFor(String handle) => slug != null ? '/@$handle/item/$slug' : '/@$handle?item=${Uri.encodeQueryComponent(id)}';
  factory Product.fromJson(Map j) => Product(
        id: '${j['id']}', name: '${j['name']}', kind: '${j['kind'] ?? 'product'}', available: j['available'] != false, slug: j['slug'] as String?,
        price: j['price'] as String?, description: j['description'] as String?, imageUrl: j['imageUrl'] as String?,
        category: (j['category'] as String?)?.trim().isEmpty == true ? null : j['category'] as String?,
      );
}

/// A catalog item in the Connect feed, with the same controls as an ask (GET /products/feed).
class FeedProduct extends Product {
  int reactionsCount, repostsCount, referralsCount, enquiriesCount;
  String? myReaction;
  bool bookmarked, reposted;
  FeedProduct({
    required super.id, required super.name, required super.kind, super.available, super.price, super.description, super.imageUrl, super.slug, super.category,
    this.reactionsCount = 0, this.repostsCount = 0, this.referralsCount = 0, this.enquiriesCount = 0, this.myReaction,
    this.bookmarked = false, this.reposted = false,
  });
  factory FeedProduct.fromJson(Map j) => FeedProduct(
        id: '${j['id']}', name: '${j['name']}', kind: '${j['kind'] ?? 'product'}', available: j['available'] != false, slug: j['slug'] as String?,
        category: (j['category'] as String?)?.trim().isEmpty == true ? null : j['category'] as String?,
        price: j['price'] as String?, description: j['description'] as String?, imageUrl: j['imageUrl'] as String?,
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, repostsCount: (j['repostsCount'] as num?)?.toInt() ?? 0,
        referralsCount: (j['referralsCount'] as num?)?.toInt() ?? 0, enquiriesCount: (j['enquiriesCount'] as num?)?.toInt() ?? 0,
        myReaction: j['myReaction'] as String?, bookmarked: j['bookmarked'] == true, reposted: j['reposted'] == true,
      );
}

/// One business and some of what it offers.
class CatalogGroup {
  final Peer owner;
  final String? location;
  final int verification;
  final int total;
  final List<FeedProduct> items;
  CatalogGroup({required this.owner, this.location, this.verification = 0, required this.total, required this.items});
  factory CatalogGroup.fromJson(Map j) {
    final o = j['owner'] as Map;
    return CatalogGroup(
      owner: Peer.fromJson(o),
      location: o['location'] as String?,
      verification: (o['verification'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      items: ((j['items'] as List?) ?? const []).map((e) => FeedProduct.fromJson(e as Map)).toList(),
    );
  }
}

class StoryItem {
  final String id;
  final String? imageUrl, text;
  final DateTime createdAt;
  int reactionsCount;
  String? myReaction;
  /// set when this update is a repost of someone else's: {handle, name}
  final Map<String, dynamic>? repostedFrom;
  StoryItem({required this.id, this.imageUrl, this.text, required this.createdAt, this.reactionsCount = 0, this.myReaction, this.repostedFrom});
  factory StoryItem.fromJson(Map j) => StoryItem(
        id: '${j['id']}', imageUrl: j['imageUrl'] as String?, text: j['text'] as String?, createdAt: _ms(j['createdAt']),
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, myReaction: j['myReaction'] as String?,
        repostedFrom: j['repostedFrom'] == null ? null : Map<String, dynamic>.from(j['repostedFrom'] as Map),
      );
}

class StoryGroup {
  final String uid, name, handle;
  final String userType, company;
  final int verification;
  final String? photoUrl;
  final List<StoryItem> items;
  StoryGroup({required this.uid, required this.name, required this.handle, this.userType = 'entrepreneur', this.company = '', this.verification = 0, this.photoUrl, required this.items});
  String get shownName => userType == 'entrepreneur' && company.isNotEmpty ? company : name;
  factory StoryGroup.fromJson(Map j) => StoryGroup(
        uid: '${j['uid']}', name: '${j['name']}', handle: '${j['handle'] ?? ''}', photoUrl: j['photoURL'] as String?,
        userType: '${j['userType'] ?? 'entrepreneur'}', company: '${j['company'] ?? ''}', verification: (j['verification'] as num?)?.toInt() ?? 0,
        items: ((j['items'] as List?) ?? const []).map((e) => StoryItem.fromJson(e as Map)).toList(),
      );
}

// ===================== people, chats, calls =====================

/// Someone you can talk to (a chat peer, a search hit, a call peer).
class Peer {
  final String uid, name, company, handle, userType;
  final String? photoUrl;
  final int verification;
  final bool premium;
  final String? plan;
  const Peer({required this.uid, required this.name, this.company = '', this.handle = '', this.userType = 'entrepreneur', this.photoUrl, this.verification = 0, this.premium = false, this.plan});
  String get shownName => userType == 'entrepreneur' && company.isNotEmpty ? company : name;
  factory Peer.fromJson(Map j) => Peer(
        uid: '${j['uid']}', name: '${j['name'] ?? ''}', company: '${j['company'] ?? ''}', handle: '${j['handle'] ?? ''}',
        userType: '${j['userType'] ?? 'entrepreneur'}', photoUrl: j['photoURL'] as String?,
        verification: (j['verification'] ?? j['verificationLevel'] as num?)?.toInt() ?? 0,
        premium: j['premium'] == true, plan: j['plan'] as String?,
      );
  factory Peer.fromProfile(Profile p) => Peer(uid: p.uid, name: p.name, company: p.company, handle: p.handle, userType: p.userType, photoUrl: p.photoUrl, verification: p.verification, premium: p.premium, plan: p.plan);
}

/// The message a reply quotes (web: Message.replyTo).
class MsgQuote {
  final String id, senderUid, text, kind;
  const MsgQuote({required this.id, required this.senderUid, required this.text, required this.kind});
  factory MsgQuote.fromJson(Map j) => MsgQuote(id: '${j['id']}', senderUid: '${j['senderUid']}', text: '${j['text'] ?? ''}', kind: '${j['kind'] ?? 'text'}');
}

class MsgReaction {
  final String emoji;
  final int count;
  final bool mine;
  const MsgReaction(this.emoji, this.count, this.mine);
  factory MsgReaction.fromJson(Map j) => MsgReaction('${j['emoji']}', (j['count'] as num?)?.toInt() ?? 1, j['mine'] == true);
}

class Msg {
  final int id;
  final String senderUid, text;
  final String? imageUrl;
  final Map<String, dynamic>? attachment; // {type: contact|location|document|post|profile|item|cart, ...}
  final MsgQuote? replyTo;
  final DateTime createdAt;
  DateTime? deliveredAt, readAt;
  List<MsgReaction> reactions;
  /// Local-only: a message that is still being sent.
  final bool pending;
  final String? tmpId;
  Msg({required this.id, required this.senderUid, required this.text, this.imageUrl, this.attachment, this.replyTo, required this.createdAt, this.deliveredAt, this.readAt, this.reactions = const [], this.pending = false, this.tmpId});
  factory Msg.fromJson(Map j) => Msg(
        id: int.tryParse('${j['id']}') ?? 0, senderUid: '${j['senderUid']}', text: '${j['text'] ?? ''}', imageUrl: j['imageUrl'] as String?,
        attachment: j['attachment'] == null ? null : Map<String, dynamic>.from(j['attachment'] as Map),
        replyTo: j['replyTo'] == null ? null : MsgQuote.fromJson(j['replyTo'] as Map), createdAt: _ms(j['createdAt']),
        deliveredAt: _msOpt(j['deliveredAt']), readAt: _msOpt(j['readAt']),
      );
  /// What kind of message this is, for reply quotes.
  String get kind => (attachment?['type'] as String?) ?? (imageUrl != null ? 'image' : 'text');
}

class ChatSummary {
  final String id;
  final Peer peer;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final bool unread;
  ChatSummary({required this.id, required this.peer, this.lastMessage, this.lastMessageAt, this.unread = false});

  factory ChatSummary.fromJson(Map j, String meUid) {
    final info = Map<String, dynamic>.from(j['participantInfo'] as Map);
    final other = ((j['participants'] as List).map((e) => '$e').firstWhere((p) => p != meUid, orElse: () => ''));
    final p = Map<String, dynamic>.from((info[other] as Map?) ?? {});
    return ChatSummary(
      id: '${j['id']}',
      peer: Peer(uid: other, name: '${p['name'] ?? ''}', company: '${p['company'] ?? ''}', handle: '${p['handle'] ?? ''}', userType: '${p['userType'] ?? 'entrepreneur'}', photoUrl: p['photoURL'] as String?,
          verification: (p['verification'] as num?)?.toInt() ?? 0, premium: p['premium'] == true, plan: p['plan'] as String?),
      lastMessage: j['lastMessage'] as String?, lastMessageAt: _msOpt(j['lastMessageAt']), unread: j['unread'] == true,
    );
  }
}

class CallLog {
  final String id, callerUid, calleeUid, status; // status: completed | missed | declined | cancelled
  final bool video;
  final int durationS;
  final DateTime createdAt;
  final Peer? peer;
  CallLog({required this.id, required this.callerUid, required this.calleeUid, required this.status, required this.video, required this.durationS, required this.createdAt, this.peer});
  factory CallLog.fromJson(Map j) => CallLog(
        id: '${j['id']}', callerUid: '${j['callerUid']}', calleeUid: '${j['calleeUid']}', status: '${j['status']}', video: j['video'] == true,
        durationS: (j['durationS'] as num?)?.toInt() ?? 0, createdAt: _ms(j['createdAt']), peer: j['peer'] == null ? null : Peer.fromJson(j['peer'] as Map),
      );
}
