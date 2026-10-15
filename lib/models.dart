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

/// Navi Mumbai nodes.
const kLocations = [
  Option('Vashi', 'Vashi'), Option('Rabale', 'Rabale'), Option('Turbhe', 'Turbhe'), Option('Mahape', 'Mahape'),
  Option('Pawane', 'Pawane'), Option('Belapur', 'Belapur'), Option('Kharghar', 'Kharghar'), Option('Panvel', 'Panvel'),
  Option('Kalamboli', 'Kalamboli'), Option('Other', 'Other'),
];

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
  Option('other', 'Other'),
];

const kCategoryShort = {
  'job': 'Jobs / Manpower', 'supplier': 'Supplier / Vendor', 'buyer': 'Buyer / Customer', 'logistics': 'Logistics',
  'funding': 'Funding', 'advice': 'Advice', 'mentorship': 'Mentorship', 'partnership': 'Partnership',
  'machinery': 'Machinery', 'space': 'Space / Godown', 'training': 'Training', 'other': 'Other',
};

const kUrgencies = [Option('immediate', 'Immediate'), Option('7_days', 'Within 7 days'), Option('30_days', 'Within 30 days'), Option('flexible', 'Flexible')];

String labelOf(List<Option> options, String? value) {
  if (value == null) return '';
  for (final o in options) {
    if (o.value == value) return o.label;
  }
  return value;
}

const kReactions = ['heart', 'thumbs', 'namaskar'];
const kReactionEmoji = {'heart': '❤️', 'thumbs': '👍', 'namaskar': '🙏'};

// ===================== profile =====================

class Profile {
  final String uid, handle, name, company, userType, category, location;
  final String? photoUrl, bio, experience, education, contactMasked;
  final List<String> services, skills;
  final int contributions;
  final int? statPosts, statShared;
  final DateTime createdAt;

  const Profile({
    required this.uid, required this.handle, required this.name, required this.company, required this.userType,
    required this.category, required this.location, this.photoUrl, this.bio, this.experience, this.education,
    this.contactMasked, this.services = const [], this.skills = const [], this.contributions = 0,
    this.statPosts, this.statShared, required this.createdAt,
  });

  bool get isEntrepreneur => userType == 'entrepreneur';
  bool get isJobSeeker => userType == 'job_seeker';

  factory Profile.fromJson(Map j) {
    final stats = j['stats'] as Map?;
    return Profile(
      uid: '${j['uid']}', handle: '${j['handle'] ?? ''}', name: '${j['name'] ?? ''}', company: '${j['company'] ?? ''}',
      userType: '${j['userType'] ?? 'entrepreneur'}', category: '${j['category'] ?? ''}', location: '${j['location'] ?? ''}',
      photoUrl: j['photoURL'] as String?, bio: j['bio'] as String?, experience: j['experience'] as String?,
      education: j['education'] as String?, contactMasked: j['contactMasked'] as String?,
      services: _strings(j['services']), skills: _strings(j['skills']),
      contributions: (j['contributions'] as num?)?.toInt() ?? (stats?['contributions'] as num?)?.toInt() ?? 0,
      statPosts: (stats?['posts'] as num?)?.toInt(), statShared: (stats?['shared'] as num?)?.toInt(),
      createdAt: _ms(j['createdAt']),
    );
  }
}

// ===================== posts =====================

class ResponseLog {
  final String uid, name, handle, kind; // kind: contact | media | info
  final String? photoUrl, reaction;
  final int? rating;
  final DateTime createdAt;
  ResponseLog({required this.uid, required this.name, required this.handle, required this.kind, this.photoUrl, this.reaction, this.rating, required this.createdAt});
  factory ResponseLog.fromJson(Map j) => ResponseLog(
        uid: '${j['uid']}', name: '${j['name']}', handle: '${j['handle'] ?? ''}', kind: '${j['kind']}', photoUrl: j['photoURL'] as String?,
        reaction: j['reaction'] as String?, rating: (j['rating'] as num?)?.toInt(), createdAt: _ms(j['createdAt']),
      );
}

class Post {
  final String id, kind, authorUid, authorName, authorCompany, authorHandle; // kind: requirement | update
  final String? authorPhotoUrl, title, description, category, locationPref, budget, urgency, matchReason;
  final List<String> images;
  final int sharesCount;
  final bool authorHasUpdate;
  final DateTime createdAt;
  final List<ResponseLog> recentResponses;
  // viewer state (changes locally for optimistic updates)
  int reactionsCount, repostsCount, referralsCount;
  bool reacted, reposted, bookmarked;
  String? myReaction;

  Post({
    required this.id, required this.kind, required this.authorUid, required this.authorName, required this.authorCompany,
    required this.authorHandle, this.authorPhotoUrl, this.title, this.description, this.category, this.locationPref, this.budget,
    this.urgency, this.matchReason, this.images = const [], this.sharesCount = 0, this.authorHasUpdate = false, required this.createdAt,
    this.recentResponses = const [], this.reactionsCount = 0, this.repostsCount = 0, this.referralsCount = 0,
    this.reacted = false, this.reposted = false, this.bookmarked = false, this.myReaction,
  });

  bool get isRequirement => kind == 'requirement';

  factory Post.fromJson(Map j) => Post(
        id: '${j['id']}', kind: '${j['kind']}', authorUid: '${j['authorUid']}', authorName: '${j['authorName']}',
        authorCompany: '${j['authorCompany'] ?? ''}', authorHandle: '${j['authorHandle'] ?? ''}', authorPhotoUrl: j['authorPhotoURL'] as String?,
        title: j['title'] as String?, description: j['description'] as String?, category: j['category'] as String?,
        locationPref: j['locationPref'] as String?, budget: j['budget'] as String?, urgency: j['urgency'] as String?,
        matchReason: j['matchReason'] as String?, images: _strings(j['images']), sharesCount: (j['sharesCount'] as num?)?.toInt() ?? 0,
        authorHasUpdate: j['authorHasUpdate'] == true, createdAt: _ms(j['createdAt']),
        recentResponses: ((j['recentResponses'] as List?) ?? const []).map((e) => ResponseLog.fromJson(e as Map)).toList(),
        reactionsCount: (j['reactionsCount'] as num?)?.toInt() ?? 0, repostsCount: (j['repostsCount'] as num?)?.toInt() ?? 0,
        referralsCount: (j['referralsCount'] as num?)?.toInt() ?? 0, reacted: j['reacted'] == true, reposted: j['reposted'] == true,
        bookmarked: j['bookmarked'] == true, myReaction: j['myReaction'] as String? ?? (j['reacted'] == true ? 'heart' : null),
      );
}

/// What the viewer already did on someone's ask (GET /posts/:id/share/me).
class MyResponse {
  final bool shared;
  final String? kind, askStatus, ownerReaction;
  final int? rating;
  const MyResponse({required this.shared, this.kind, this.askStatus, this.ownerReaction, this.rating});
  factory MyResponse.fromJson(Map j) => MyResponse(
        shared: j['shared'] == true, kind: j['kind'] as String?, askStatus: j['askStatus'] as String?,
        ownerReaction: j['ownerReaction'] as String?, rating: (j['rating'] as num?)?.toInt(),
      );
}

/// Owner's view of one response (content only after the responder approved).
class ContactShare {
  final String sharerUid, sharerName, sharerCompany, kind;
  final String? sharerHandle, sharerPhotoUrl, askStatus, ownerReaction, payload;
  final int? rating;
  final bool revealed;
  final DateTime createdAt;
  ContactShare({
    required this.sharerUid, required this.sharerName, required this.sharerCompany, required this.kind, this.sharerHandle,
    this.sharerPhotoUrl, this.askStatus, this.ownerReaction, this.payload, this.rating, required this.revealed, required this.createdAt,
  });
  factory ContactShare.fromJson(Map j) => ContactShare(
        sharerUid: '${j['sharerUid']}', sharerName: '${j['sharerName']}', sharerCompany: '${j['sharerCompany'] ?? ''}', kind: '${j['kind']}',
        sharerHandle: j['sharerHandle'] as String?, sharerPhotoUrl: j['sharerPhotoURL'] as String?, askStatus: j['askStatus'] as String?,
        ownerReaction: j['ownerReaction'] as String?, payload: j['payload'] as String?, rating: (j['rating'] as num?)?.toInt(),
        revealed: j['revealed'] == true, createdAt: _ms(j['createdAt']),
      );
}

/// A third party's contact referred on an ask (owner sees all; a referrer sees their own).
class Referral {
  final String id, name, phone;
  final String? note, referrerName, referrerHandle;
  final DateTime createdAt;
  Referral({required this.id, required this.name, required this.phone, this.note, this.referrerName, this.referrerHandle, required this.createdAt});
  factory Referral.fromJson(Map j) => Referral(
        id: '${j['id']}', name: '${j['name']}', phone: '${j['phone']}', note: j['note'] as String?,
        referrerName: j['referrerName'] as String?, referrerHandle: j['referrerHandle'] as String?, createdAt: _ms(j['createdAt']),
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
class Deal {
  final String postId, postTitle, ownerName, ownerCompany, ownerHandle, kind;
  final int? rating;
  final String? reaction;
  final DateTime createdAt;
  Deal({required this.postId, required this.postTitle, required this.ownerName, required this.ownerCompany, required this.ownerHandle, required this.kind, this.rating, this.reaction, required this.createdAt});
  factory Deal.fromJson(Map j) => Deal(
        postId: '${j['postId']}', postTitle: '${j['postTitle']}', ownerName: '${j['ownerName']}', ownerCompany: '${j['ownerCompany'] ?? ''}',
        ownerHandle: '${j['ownerHandle'] ?? ''}', kind: '${j['kind']}', rating: (j['rating'] as num?)?.toInt(), reaction: j['reaction'] as String?,
        createdAt: _ms(j['createdAt']),
      );
}

// ===================== catalog & stories =====================

class Product {
  final String id, name, kind; // kind: product | service
  final bool available;
  final String? price, description, imageUrl;
  Product({required this.id, required this.name, required this.kind, this.available = true, this.price, this.description, this.imageUrl});
  factory Product.fromJson(Map j) => Product(
        id: '${j['id']}', name: '${j['name']}', kind: '${j['kind'] ?? 'product'}', available: j['available'] != false,
        price: j['price'] as String?, description: j['description'] as String?, imageUrl: j['imageUrl'] as String?,
      );
}

class StoryItem {
  final String id;
  final String? imageUrl, text;
  final DateTime createdAt;
  StoryItem({required this.id, this.imageUrl, this.text, required this.createdAt});
  factory StoryItem.fromJson(Map j) => StoryItem(id: '${j['id']}', imageUrl: j['imageUrl'] as String?, text: j['text'] as String?, createdAt: _ms(j['createdAt']));
}

class StoryGroup {
  final String uid, name, handle;
  final String? photoUrl;
  final List<StoryItem> items;
  StoryGroup({required this.uid, required this.name, required this.handle, this.photoUrl, required this.items});
  factory StoryGroup.fromJson(Map j) => StoryGroup(
        uid: '${j['uid']}', name: '${j['name']}', handle: '${j['handle'] ?? ''}', photoUrl: j['photoURL'] as String?,
        items: ((j['items'] as List?) ?? const []).map((e) => StoryItem.fromJson(e as Map)).toList(),
      );
}

// ===================== people, chats, calls =====================

/// Someone you can talk to (a chat peer, a search hit, a call peer).
class Peer {
  final String uid, name, company, handle, userType;
  final String? photoUrl;
  const Peer({required this.uid, required this.name, this.company = '', this.handle = '', this.userType = 'entrepreneur', this.photoUrl});
  factory Peer.fromJson(Map j) => Peer(
        uid: '${j['uid']}', name: '${j['name'] ?? ''}', company: '${j['company'] ?? ''}', handle: '${j['handle'] ?? ''}',
        userType: '${j['userType'] ?? 'entrepreneur'}', photoUrl: j['photoURL'] as String?,
      );
  factory Peer.fromProfile(Profile p) => Peer(uid: p.uid, name: p.name, company: p.company, handle: p.handle, userType: p.userType, photoUrl: p.photoUrl);
}

class Msg {
  final int id;
  final String senderUid, text;
  final String? imageUrl;
  final Map<String, dynamic>? attachment; // {type: contact|location|document, ...}
  final DateTime createdAt;
  DateTime? deliveredAt, readAt;
  /// Local-only: a message that is still being sent.
  final bool pending;
  final String? tmpId;
  Msg({required this.id, required this.senderUid, required this.text, this.imageUrl, this.attachment, required this.createdAt, this.deliveredAt, this.readAt, this.pending = false, this.tmpId});
  factory Msg.fromJson(Map j) => Msg(
        id: int.tryParse('${j['id']}') ?? 0, senderUid: '${j['senderUid']}', text: '${j['text'] ?? ''}', imageUrl: j['imageUrl'] as String?,
        attachment: j['attachment'] == null ? null : Map<String, dynamic>.from(j['attachment'] as Map), createdAt: _ms(j['createdAt']),
        deliveredAt: _msOpt(j['deliveredAt']), readAt: _msOpt(j['readAt']),
      );
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
      peer: Peer(uid: other, name: '${p['name'] ?? ''}', company: '${p['company'] ?? ''}', handle: '${p['handle'] ?? ''}', photoUrl: p['photoURL'] as String?),
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
