import 'dart:async';

import 'package:flutter/material.dart';
import 'poll_vote.dart' show OptionMark, OptionState;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_provider.dart';
import '../card_colors.dart';
import '../i18n.dart';
import '../links.dart';
import '../models.dart';
import '../screens/edit_profile.dart';
import '../screens/find.dart';
import '../screens/leads.dart';
import '../screens/p2.dart' show kCategoryEmoji, showAlertSheet;
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../screens/talk.dart' show ChatThread, openChat;
import '../theme.dart';
import '../widgets.dart';
import 'post_card.dart';
import 'reaction_picker.dart';
import 'refer_sheet.dart';
import 'swipe_deck.dart';

/// A WEBWEB house card between asks on Connect (web house-card.tsx, API feed-cards.ts). Always from a house account
/// with the WEBWEB badge (and AI when the model wrote it), never dressed as an ask; each one has something to do in it:
/// answer, pick, enquire, mark interested, or one gold button. Shown, tap and hide go back to tune the mix. Under it the
/// same five controls as every card: React · Reply · Refer · Views · Share (the real post's, or the personal card's own).

/// Each house account's face: an emoji on its coloured circle.
const _face = <String, (String, Color, Color)>{
  'webwebai': ('✨', Color(0xFFFFD84A), Color(0xFFC99400)),
  'webwebbazaar': ('📊', Color(0xFF5EEAD4), Color(0xFF0D9488)),
  'webwebtenders': ('📄', Color(0xFF93C5FD), Color(0xFF2563EB)),
  'webwebtips': ('💡', Color(0xFFFDE68A), Color(0xFFF59E0B)),
  'webwebnews': ('📰', Color(0xFFD1D5DB), Color(0xFF4B5563)),
  'webwebquiz': ('🧠', Color(0xFFF0ABFC), Color(0xFFA21CAF)),
  'webwebsourcing': ('🛒', Color(0xFFFDBA74), Color(0xFFEA580C)),
  'webwebevents': ('📅', Color(0xFFC4B5FD), Color(0xFF7C3AED)),
  'webwebjobs': ('👷', Color(0xFF86EFAC), Color(0xFF16A34A)),
  'webwebspotlight': ('🏆', Color(0xFFFDA4AF), Color(0xFFE11D48)),
  'webwebfacts': ('📊', Color(0xFFFDE68A), Color(0xFFC99400)),
  'webwebdirectory': ('🔧', Color(0xFFA5B4FC), Color(0xFF4338CA)),
};

/// The line under the account's name.
const _sub = <String, String>{
  'missed_leads': 'Leads waiting for you',
  'improve_ask': 'About your ask',
  'pulse': 'Demand near you this week',
  'buy_select': 'Quick question',
  'items': 'From businesses near you',
  'profile': 'Your page',
  'spotlight': 'Doing well near you',
  'ask_ai': 'Ask in your own words',
  'tender': 'Open tender',
  'scheme': 'Government scheme',
  'news': 'Business news',
  'tip': 'Tip for your business',
  'event': 'Event near you',
  'job': 'Jobs and hiring',
  'quiz': 'Quiz',
  'poll': 'Poll',
};

// ---------- the API ----------

/// WEBWEB AI's account (GET /feed/cards also says who it is).
String? houseAssistantUid;

/// The WEBWEB house cards for this member's feed, best first.
Future<List<HouseCard>> loadHouseCards(Api api) async {
  final d = await api.get('/feed/cards', {'lang': currentLang}) as Map;
  houseAssistantUid = d['assistantUid'] as String?;
  return [for (final c in (d['cards'] as List? ?? const [])) HouseCard.fromJson(c as Map)];
}

/// WEBWEB Facts: real posts with a figure and its source; the feed puts one after every 10th ask.
Future<List<Post>> loadFactPosts(Api api, {int limit = 6}) async =>
    [for (final p in (await api.get('/posts/facts', {'lang': currentLang, 'limit': limit}) as List)) Post.fromJson(p as Map)];

Future<HouseCard> _answer(Api api, String key, Map<String, dynamic> a) async =>
    HouseCard.fromJson(await api.post('/feed/cards/${Uri.encodeComponent(key)}/answer', {...a, 'lang': currentLang}) as Map);

final _events = <Map<String, String>>[];
final _shownOnce = <String>{};
Timer? _eventTimer;

/// shown / tap / hide / fewer / react, sent in a batch a few seconds later (a card counts as shown once per app run).
void _cardEvent(Api api, HouseCard card, String event) {
  if (event == 'shown' && !_shownOnce.add(card.key)) return;
  _events.add({'key': card.key, 'type': card.type, 'event': event});
  _eventTimer ??= Timer(Duration(milliseconds: event == 'shown' ? 4000 : 800), () {
    final batch = _events.take(50).toList();
    _events.clear();
    _eventTimer = null;
    api.post('/feed/cards/events', {'events': batch}).catchError((_) => null);
  });
}

String _wa(String text, [String? url]) => 'https://wa.me/?text=${Uri.encodeComponent(url == null ? text : '$text\n$url')}';
Future<void> _launch(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);

String? _daysLeft(String? deadline) {
  if (deadline == null || deadline.isEmpty) return null;
  final end = DateTime.tryParse('${deadline}T23:59:59+05:30');
  if (end == null) return null;
  final d = (end.difference(DateTime.now()).inHours / 24).ceil();
  if (d < 0) return null;
  return d == 0 ? t('Closes today') : t(d == 1 ? '1 day left' : '{n} days left', {'n': d});
}

// ---------- the card ----------

class HouseCardView extends StatefulWidget {
  final HouseCard card;
  final VoidCallback onGone;
  const HouseCardView({super.key, required this.card, required this.onGone});
  @override
  State<HouseCardView> createState() => _HouseCardViewState();
}

/// Each house account's card colour, as the cards of an ask wear theirs (web house-card.tsx TONE).
const _tone = {
  'webwebai': 'gold',
  'webwebbazaar': 'teal',
  'webwebtenders': 'sky',
  'webwebtips': 'orange',
  'webwebnews': 'slate',
  'webwebquiz': 'violet',
  'webwebsourcing': 'orange',
  'webwebevents': 'violet',
  'webwebjobs': 'emerald',
  'webwebspotlight': 'rose',
};

class _HouseCardViewState extends State<HouseCardView> {
  late HouseCard card = widget.card;
  Api get _api => context.read<AuthProvider>().api;

  @override
  void initState() {
    super.initState();
    // built on screen (the feed builds just ahead of it): counts as shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardEvent(_api, card, 'shown');
    });
  }

  void _tap() => _cardEvent(_api, card, 'tap');

  Future<void> _menu() async {
    final p = Pal.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.canvas,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(t('Show fewer like this')), onTap: () => Navigator.pop(ctx, 'fewer')),
          ListTile(title: Text(t('Hide this card')), onTap: () => Navigator.pop(ctx, 'hide')),
          ListTile(title: Text(t('Turn off WEBWEB cards'), style: TextStyle(color: p.danger)), onTap: () => Navigator.pop(ctx, 'off')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(t('Cards from WEBWEB help you find work and buyers. They are never asks from members.'), style: TextStyle(fontSize: 12, color: p.muted)),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'off') _api.post('/feed/cards/prefs', {'type': '*', 'off': true}).catchError((_) => null);
    _cardEvent(_api, card, choice == 'fewer' ? 'fewer' : 'hide');
    widget.onGone();
  }

  /// Reply on a card with a post behind it: a chat with the house account (it answers with AI), the post attached.
  Future<void> _replyPost(Post post) => openChat(
        context,
        Peer(uid: card.account.uid, name: card.account.name, handle: card.account.handle),
        attachment: {
          'type': 'post',
          'postId': post.id,
          'kind': 'update',
          'title': _cut(card.title ?? post.title ?? post.description ?? 'Update', 100),
          'by': card.account.name,
          'path': Uri.parse(post.webUrl).path,
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final face = _face[card.account.handle] ?? _face['webwebai']!;
    final post = card.post;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      foregroundDecoration: HairlineBelow(kGold.withValues(alpha: .6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(handle: card.account.handle))),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [face.$2, face.$3]),
                border: Border.all(color: kGold.withValues(alpha: .4), width: 2),
              ),
              child: Text(face.$1, style: const TextStyle(fontSize: 18, height: 1)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(card.account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: p.dark ? const Color(0xFF2E2E2E) : kInk, borderRadius: BorderRadius.circular(6)),
                  child: const Text('WEBWEB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: Color(0xFFFFD84A))),
                ),
                if (card.ai) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: kGold.withValues(alpha: .6))),
                    child: Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.tagText)),
                  ),
                ],
              ]),
              Text(t(_sub[card.type] ?? 'For you'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          Semantics(
            button: true,
            label: t('More'),
            child: InkResponse(onTap: _menu, radius: 18, child: SizedBox(width: 32, height: 32, child: Center(child: Icon(Icons.more_vert, size: 18, color: p.muted)))),
          ),
        ]),
        const SizedBox(height: 12),
        // the posts that read come as a swipeable deck of small cards, as an ask does; the others are one tinted card
        // (a row of items needs none: its item cards are the cards)
        if (_readTypes.contains(card.type)) _HouseDeck(card, (c) => setState(() => card = c), _tap) else if (_deckTypes.contains(card.type)) _PersonalDeck(card, (c) => setState(() => card = c), _tap) else if (card.type == 'items') _body() else Builder(builder: (_) {
          final tint = kCardColors[_tone[card.account.handle] ?? 'gold']!;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: .28), tint.withValues(alpha: 0)], stops: const [0, .8]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tint.withValues(alpha: .4)),
            ),
            child: _body(),
          );
        }),
        if ((card.sourceUrl ?? '').isNotEmpty && card.type != 'quiz' && !_deckTypes.contains(card.type))
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _tap();
                openExternal(context, card.sourceUrl!);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(WI.link, size: 13, color: p.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${t('Source')}: ${(card.sourceName ?? '').isNotEmpty ? card.sourceName : hostOf(card.sourceUrl!)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                  ),
                ]),
              ),
            ),
          ),
        SizedBox(height: _deckTypes.contains(card.type) ? 6 : 20),
        if (post != null) PostActions(post: post, spotlight: true, onReply: () => _replyPost(post), onChanged: () => setState(() {})) else _CardActions(card: card, tap: _tap),
      ]),
    );
  }

  Widget _body() {
    void set(HouseCard c) => setState(() => card = c);
    return switch (card.type) {
      'missed_leads' => _MissedLeads(card, _tap),
      'improve_ask' => _ImproveAsk(card, _tap),
      'pulse' => _Pulse(card, _tap),
      'buy_select' => _BuySelect(card, _tap),
      'items' => _ItemsCard(card, _tap),
      'profile' => _ProfileStep(card, _tap),
      'spotlight' => _Spotlight(card, _tap),
      'ask_ai' => _AskAi(card, _tap),
      'quiz' || 'poll' => _Quiz(card, set, _tap),
      'tip' => _Tip(card, set, _tap),
      'news' => _News(card, set, _tap),
      _ => _Notice(card, set, _tap),
    };
  }
}

String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Bottom hairline that fades out at both ends (the feed's row divider).
class HairlineBelow extends Decoration {
  final Color color;
  const HairlineBelow(this.color);
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _HairlinePainter(color);
}

class _HairlinePainter extends BoxPainter {
  final Color color;
  _HairlinePainter(this.color);
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final rect = Rect.fromLTWH(offset.dx, offset.dy + size.height - 1, size.width, 1);
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color, color.withValues(alpha: 0)], stops: const [0, .12, .88, 1]).createShader(rect),
    );
  }
}

// ---------- building blocks ----------

/// The gold button, or the soft one. No emoji in a button: an icon where it helps.
class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool soft, active, expand;
  final WI? icon;
  const _Btn(this.label, {this.onTap, this.soft = false, this.active = false, this.expand = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ink = soft ? p.text : kInk;
    final b = Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: soft ? null : kGoldGradient,
          color: soft ? (active ? kGold.withValues(alpha: .2) : p.chip.withValues(alpha: .6)) : null,
          borderRadius: BorderRadius.circular(12),
          border: soft ? Border.all(color: active ? kGold : p.border) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[WIcon(icon!, size: 16, color: ink), if (label.isNotEmpty) const SizedBox(width: 6)],
          if (label.isNotEmpty) Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink))),
        ]),
      ),
    );
    final w = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: b);
    return expand ? Expanded(child: w) : w;
  }
}

Widget _title(String text, {double size = 19}) => Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, height: 1.3));
Widget _hint(BuildContext context, String text) => Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: TextStyle(fontSize: 14, color: Pal.of(context).muted)));

void _push(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

// ---------- bodies ----------

class _MissedLeads extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _MissedLeads(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final leads = [for (final l in (card.data['leads'] as List? ?? const [])) l as Map];
    final n = (card.data['total'] as num?)?.toInt() ?? leads.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('🔥 ${t(n == 1 ? '1 lead near you has no replies yet' : '{n} leads near you have no replies yet', {'n': n})}'),
      _hint(context, t('Be the first: the first few replies get the most attention.')),
      const SizedBox(height: 12),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
        child: Column(children: [
          for (var i = 0; i < leads.length; i++)
            InkWell(
              onTap: () {
                tap();
                _push(context, PostDetailScreen(postId: '${leads[i]['id']}', openReply: true));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.border))),
                child: Row(children: [
                  Text(kCategoryEmoji[leads[i]['category']] ?? '✨', style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${leads[i]['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                        [leads[i]['location'], leads[i]['budget']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ').ifEmpty(t(kCategoryShort[leads[i]['category']] ?? 'Ask')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(t('Reply'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.tagText)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _Btn(t('See all leads'), expand: true, onTap: () {
          tap();
          _push(context, const LeadsScreen());
        }),
        const SizedBox(width: 8),
        _Btn(t('Alerts'), soft: true, onTap: () {
          tap();
          showAlertSheet(context);
        }),
      ]),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _ImproveAsk extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _ImproveAsk(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final post = (card.data['post'] as Map?) ?? const {};
    final id = '${post['id']}';
    final hint = '${card.data['hint']}';
    void open() {
      tap();
      _push(context, PostDetailScreen(postId: id));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('⏳ ${t('Your ask has no replies yet')}'),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(color: p.chip.withValues(alpha: .5), borderRadius: BorderRadius.circular(16), border: const Border(left: BorderSide(color: kGold, width: 4))),
          child: Text('${post['title'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '💡 ${t(hint == 'budget' ? 'Asks with a budget get about twice the replies. Add one?' : hint == 'photo' ? 'A photo shows what you need at a glance. Add one?' : 'Share it in your WhatsApp groups: people there can reply here.')}',
        style: const TextStyle(fontSize: 14),
      ),
      const SizedBox(height: 12),
      Row(children: [
        hint == 'share'
            ? _Btn(t('Share on WhatsApp'), expand: true, onTap: () {
                tap();
                _launch(_wa('${post['title'] ?? ''}', 'https://webweb.ai/post/$id'));
              })
            : _Btn(t(hint == 'budget' ? 'Add a budget' : 'Add a photo'), expand: true, onTap: open),
        const SizedBox(width: 8),
        _Btn(t('Open'), soft: true, onTap: open),
      ]),
    ]);
  }
}

class _Pulse extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _Pulse(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rows = [for (final r in (card.data['rows'] as List? ?? const [])) r as Map];
    final max = rows.fold<num>(1, (m, r) => (r['n'] as num? ?? 0) > m ? r['n'] as num : m);
    final place = '${card.data['place'] ?? ''}';
    const green = Color(0xFF059669);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('📊 ${t('What {place} is asking for this week', {'place': place})}'),
      _hint(context, t('{n} asks this week. Tap one to see them.', {'n': card.data['total'] ?? 0})),
      const SizedBox(height: 12),
      for (final r in rows)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tap();
            _push(context, FindScreen(standalone: true, initialScope: 'asks', initialLocation: place, initialQuery: t(kCategoryShort[r['category']] ?? 'Other')));
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              Row(children: [
                SizedBox(width: 24, child: Text(kCategoryEmoji[r['category']] ?? '✨', textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                Expanded(child: Text(t(kCategoryShort[r['category']] ?? 'Other'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                if ((r['open'] as num? ?? 0) > 0) Text(t('{n} open', {'n': r['open']}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: green)),
                SizedBox(width: 32, child: Text('${r['n']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                if (r['change'] != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (r['change'] as num) >= 0 ? green.withValues(alpha: .15) : p.chip,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      (r['change'] as num) >= 0 ? '▲${r['change']}%' : '▼${(r['change'] as num).abs()}%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: (r['change'] as num) >= 0 ? green : p.muted),
                    ),
                  ),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 8,
                    color: p.chip,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(widthFactor: ((r['n'] as num? ?? 0) / max).clamp(0, 1).toDouble(), child: Container(decoration: const BoxDecoration(gradient: kGoldGradient))),
                  ),
                ),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 4),
      Text('💡 ${t('Do any of these? Add them to your services and the asks come to you.')}', style: TextStyle(fontSize: 12, color: p.muted)),
    ]);
  }
}

class _BuySelect extends StatefulWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _BuySelect(this.card, this.tap);
  @override
  State<_BuySelect> createState() => _BuySelectState();
}

class _BuySelectState extends State<_BuySelect> {
  final _picked = <String>[];
  bool _busy = false;
  List<SourcingItem>? _items;

  Future<void> _save() async {
    setState(() => _busy = true);
    widget.tap();
    try {
      final d = await context.read<AuthProvider>().api.post('/feed/cards/buy', {'items': _picked}) as Map;
      if (mounted) setState(() => _items = [for (final i in (d['items'] as List? ?? const [])) SourcingItem.fromJson(i as Map)]);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = _items;
    if (items != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title("🙌 ${t("Thanks! Here's who sells them near you")}"),
        items.isNotEmpty ? _ItemRow(items, widget.tap) : _hint(context, t("No one near you lists these yet. We'll show them here as they join.")),
      ]);
    }
    final options = [for (final o in (widget.card.data['options'] as List? ?? const [])) o as Map];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('🛒 ${t('Which of these do you buy for your business?')}'),
      _hint(context, t("Pick all that apply. We'll show you items from businesses near you.")),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options)
          GestureDetector(
            onTap: () => setState(() => _picked.contains(o['key']) ? _picked.remove(o['key']) : _picked.add('${o['key']}')),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _picked.contains(o['key']) ? kGold.withValues(alpha: .25) : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _picked.contains(o['key']) ? kGold : p.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_picked.contains(o['key'])) ...[WIcon(WI.tick, size: 16, color: p.text), const SizedBox(width: 6)],
                Text(t('${o['label']}'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _Btn(
          _busy ? '…' : t(_picked.isNotEmpty ? 'Show me suppliers ({n})' : 'Pick at least one', {'n': _picked.length}),
          expand: true,
          onTap: _picked.isEmpty || _busy ? null : _save,
        ),
      ]),
    ]);
  }
}

class _ItemsCard extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _ItemsCard(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final picks = (card.data['picks'] as List?) ?? const [];
    final items = [for (final i in (card.data['items'] as List? ?? const [])) SourcingItem.fromJson(i as Map)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('🛍️ ${t(picks.isNotEmpty ? 'For what you buy, from businesses near you' : 'Popular items from businesses near you')}'),
      _ItemRow(items, tap),
    ]);
  }
}

/// Items from several businesses side by side, each with Enquire.
class _ItemRow extends StatelessWidget {
  final List<SourcingItem> items;
  final VoidCallback tap;
  const _ItemRow(this.items, this.tap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final it in items) Padding(padding: const EdgeInsets.only(right: 12), child: _ItemTile(it, tap)),
            ]),
          ),
        ),
      );
}

class _ItemTile extends StatefulWidget {
  final SourcingItem it;
  final VoidCallback tap;
  const _ItemTile(this.it, this.tap);
  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  String _state = 'idle'; // idle | busy | sent
  SourcingItem get it => widget.it;

  Map<String, dynamic> get _about => {
        'type': 'item', 'name': _cut(it.name, 80), 'kind': it.kind, 'itemId': it.id, 'handle': it.owner.handle,
        if (it.price != null) 'price': _cut(it.price!, 40), if (it.imageUrl != null) 'imageUrl': it.imageUrl,
        if (it.slug != null) 'path': it.pathFor(it.owner.handle),
      };

  /// Enquire: the enquiry goes out at once, and the button says so. The chat icon opens the chat with the item attached.
  Future<void> _send(bool open) async {
    final api = context.read<AuthProvider>().api;
    setState(() => _state = 'busy');
    widget.tap();
    try {
      final chatId = (await api.post('/chats', {'userId': it.owner.uid}) as Map)['id'] as String;
      api.post('/products/${it.id}/enquire', {}).catchError((_) => null);
      if (open) {
        setState(() => _state = 'idle');
        if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: it.owner, pending: _about)));
        return;
      }
      await api.post('/chats/$chatId/messages', {
        'text': '${t('Hi, I am interested in')} "${it.name}"${it.price != null ? ' (${it.price})' : ''}. ${t('Please share the price and availability.')}',
        'attachment': _about,
      });
      if (mounted) setState(() => _state = 'sent');
    } catch (_) {
      if (mounted) setState(() => _state = 'idle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const emerald = Color(0xFF059669);
    void openProfile() {
      widget.tap();
      _push(context, ProfileScreen(handle: it.owner.handle));
    }

    return Container(
      width: 168,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: openProfile,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(
                color: p.chip,
                child: (it.imageUrl ?? '').isNotEmpty
                    ? Image.network(mediaUrl(it.imageUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                    : Center(child: WIcon(it.kind == 'service' ? WI.service : WI.box, size: 36, color: p.muted)),
              ),
              if ((it.price ?? '').isNotEmpty)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: p.canvas.withValues(alpha: .9), borderRadius: BorderRadius.circular(10)),
                    child: Text(it.price!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(onTap: openProfile, child: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.3))),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: openProfile,
                child: Row(children: [
                  Flexible(child: Text(it.owner.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted))),
                  const SizedBox(width: 3),
                  VerifiedBadge(level: it.verification, size: 11),
                ]),
              ),
              if ((it.location ?? '').isNotEmpty)
                Row(children: [
                  WIcon(WI.pin, size: 11, color: p.muted),
                  const SizedBox(width: 2),
                  Flexible(child: Text(t(it.location!), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.muted))),
                ]),
              const Spacer(),
              const SizedBox(height: 8),
              if (_state == 'sent')
                Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: emerald.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const WIcon(WI.tick, size: 14, color: emerald),
                    const SizedBox(width: 4),
                    Text(t('Enquiry sent'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald)),
                  ]),
                )
              else
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _state == 'busy' ? null : () => _send(false),
                      child: Opacity(
                        opacity: _state == 'busy' ? .6 : 1,
                        child: Container(
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(12)),
                          child: Text(t('Enquire'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    button: true,
                    label: t('Write a message'),
                    child: GestureDetector(
                      onTap: _state == 'busy' ? null : () => _send(true),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.chip.withValues(alpha: .6), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                        child: WIcon(WI.talk, size: 18, color: p.muted),
                      ),
                    ),
                  ),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ProfileStep extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _ProfileStep(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final pct = (card.data['percent'] as num?)?.toInt() ?? 0;
    final label = t('${card.data['label'] ?? ''}');
    return Row(children: [
      SizedBox(
        width: 72,
        height: 72,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(value: pct / 100, strokeWidth: 7, backgroundColor: p.chip, color: const Color(0xFFE0A800), strokeCap: StrokeCap.round),
          ),
          Text('$pct%', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('🚀 ${t('Your page is {n}% done', {'n': pct})}', size: 17),
          _hint(context, t('Next: {item}. Complete pages get more replies and leads.', {'item': label})),
          const SizedBox(height: 10),
          _Btn(t('Add {item}', {'item': label.toLowerCase()}), onTap: () async {
            tap();
            final auth = context.read<AuthProvider>();
            if (auth.profile == null) return;
            if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: auth.profile!))) == true) auth.loadProfile();
          }),
        ]),
      ),
    ]);
  }
}

class _Spotlight extends StatelessWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _Spotlight(this.card, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final u = (card.data['user'] as Map?) ?? const {};
    final peer = Peer.fromJson(u);
    final won = (card.data['won'] as num?)?.toInt() ?? 0;
    final replies = (card.data['replies'] as num?)?.toInt() ?? 0;
    final rose = p.dark ? const Color(0xFFFDA4AF) : const Color(0xFFBE123C);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFFF43F5E).withValues(alpha: .1), kGold.withValues(alpha: .15)]),
        ),
        child: Row(children: [
          Avatar(name: peer.shownName, photoUrl: peer.photoUrl, size: 56, type: peer.userType, uid: peer.uid),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(peer.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                const SizedBox(width: 4),
                VerifiedBadge(level: (u['verification'] as num?)?.toInt() ?? 1, size: 15),
              ]),
              Text([u['category'], u['location']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              const SizedBox(height: 4),
              Text(
                card.data['reason'] == 'won'
                    ? '🏆 ${t(won == 1 ? 'Won 1 job this week' : 'Won {n} jobs this week', {'n': won})}'
                    : '⚡ ${t('Replied to {n} asks this week', {'n': replies})}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: rose),
              ),
            ]),
          ),
        ]),
      ),
      if ((u['bio'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${u['bio']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted))),
      const SizedBox(height: 12),
      Row(children: [
        _Btn(t('View profile'), expand: true, onTap: () {
          tap();
          _push(context, ProfileScreen(handle: peer.handle));
        }),
        const SizedBox(width: 8),
        _Btn(t('Say hello'), soft: true, expand: true, onTap: () {
          tap();
          openChat(context, peer);
        }),
      ]),
    ]);
  }
}

const _askIdeas = ['I need a CA for GST filing', 'Packaging boxes supplier near me', 'Hire a delivery boy for 2 months'];

class _AskAi extends StatefulWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _AskAi(this.card, this.tap);
  @override
  State<_AskAi> createState() => _AskAiState();
}

class _AskAiState extends State<_AskAi> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    widget.tap();
    final api = context.read<AuthProvider>().api;
    final a = widget.card.account;
    try {
      final chatId = (await api.post('/chats', {'userId': a.uid}) as Map)['id'] as String;
      await api.post('/chats/$chatId/messages', {'text': text});
      _text.clear();
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: Peer(uid: a.uid, name: a.name, handle: a.handle))));
    } catch (_) {
      if (mounted) toast(context, t('Could not open the chat'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('💬 ${t('What do you need today?')}'),
      _hint(context, t("Tell me in your own words, in any language. I'll find who fits and post an ask for you if you like.")),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            maxLength: 300,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              hintText: t('e.g. 2 welders for a week in Turbhe'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Btn(_busy ? '…' : t('Ask'), onTap: _busy || _text.text.trim().isEmpty ? null : _send),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final i in _askIdeas)
          GestureDetector(
            onTap: () => setState(() => _text.text = t(i)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
              child: Text(t(i), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    ]);
  }
}

/// Quiz (the right answer shows after answering, with why) and poll (what others said).
class _Quiz extends StatefulWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _Quiz(this.card, this.set, this.tap);
  @override
  State<_Quiz> createState() => _QuizState();
}

class _QuizState extends State<_Quiz> {
  bool _busy = false;

  Future<void> _pick(int i) async {
    setState(() => _busy = true);
    widget.tap();
    try {
      widget.set(await _answer(context.read<AuthProvider>().api, widget.card.key, {'option': i}));
    } catch (_) {
      if (mounted) toast(context, t('Something went wrong. Please try again.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final card = widget.card;
    final options = [for (final o in (card.data['options'] as List? ?? const [])) '$o'];
    final mine = (card.mine?['option'] as num?)?.toInt();
    final answered = mine != null;
    final counts = [for (final c in (card.results?['counts'] as List? ?? const [])) (c as num).toInt()];
    final n = (card.results?['n'] as num?)?.toInt() ?? 0;
    final right = (card.data['answer'] as num?)?.toInt();
    final quiz = card.type == 'quiz';
    const green = Color(0xFF059669);
    const red = Color(0xFFEF4444);
    final correctPct = quiz && n > 0 && right != null && right < counts.length ? (counts[right] / n * 100).round() : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('${quiz ? '🧠' : '🗳️'} ${card.title ?? ''}'),
      if ((card.body ?? '').isNotEmpty) _hint(context, card.body!),
      const SizedBox(height: 12),
      if (!answered)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t(quiz ? 'Choose one answer' : 'Choose one option'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
        ),
      for (var i = 0; i < options.length; i++) ...[
        Builder(builder: (_) {
          final pct = n > 0 && i < counts.length ? (counts[i] / n * 100).round() : 0;
          final isRight = quiz && answered && i == right;
          final wrongPick = quiz && answered && i == mine && i != right;
          final edge = isRight ? green : (wrongPick ? red : (!quiz && answered && i == mine ? kGold : p.border));
          return GestureDetector(
            onTap: answered || _busy ? null : () => _pick(i),
            child: Container(
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: edge)),
              child: Stack(children: [
                if (answered)
                  FractionallySizedBox(
                    widthFactor: pct / 100,
                    child: Container(color: isRight ? green.withValues(alpha: .2) : (wrongPick ? red.withValues(alpha: .15) : kGold.withValues(alpha: .25))),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    OptionMark(!answered ? OptionState.open : wrongPick ? OptionState.wrong : isRight ? OptionState.right : i == mine ? OptionState.mine : OptionState.other),
                    const SizedBox(width: 10),
                    Expanded(child: Text(options[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: i == mine ? FontWeight.w700 : FontWeight.w600))),
                    if (answered && i == mine) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(99)), child: Text(t('Your pick').toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                    if (answered) Text('$pct%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
      if (answered && quiz)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: mine == right ? green.withValues(alpha: .1) : kGold.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine == right ? '🎉 ${t('Right!')}' : '💡 ${t('Good try!')}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if ((card.data['explain'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${card.data['explain']}', style: const TextStyle(fontSize: 14))),
            if ((card.sourceUrl ?? '').isNotEmpty)
              GestureDetector(
                onTap: () => openExternal(context, card.sourceUrl!),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${t('Source')}: ${(card.sourceName ?? '').isNotEmpty ? card.sourceName : hostOf(card.sourceUrl!)}', style: TextStyle(fontSize: 12, color: p.muted)),
                ),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          answered
              ? (correctPct != null ? t('{n} answered · {p}% got it right', {'n': n, 'p': correctPct}) : t(n == 1 ? '1 answer so far' : '{n} answers so far', {'n': n}))
              : t(quiz ? "Tap an answer to see if you're right and how others did." : 'Tap to vote and see what others said.'),
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
      ),
    ]);
  }
}

/// A how-to in steps, one at a time.
class _Tip extends StatefulWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _Tip(this.card, this.set, this.tap);
  @override
  State<_Tip> createState() => _TipState();
}

class _TipState extends State<_Tip> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final card = widget.card;
    final steps = [for (final s in (card.data['steps'] as List? ?? const [])) '$s'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('💡 ${card.title ?? ''}'),
      if ((card.body ?? '').isNotEmpty) _hint(context, card.body!),
      if (steps.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kGold.withValues(alpha: .05), borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (var k = 0; k < steps.length; k++) ...[
                if (k > 0) const SizedBox(width: 6),
                Expanded(child: Container(height: 6, decoration: BoxDecoration(color: k <= _i ? kGold : p.chip, borderRadius: BorderRadius.circular(3)))),
              ],
            ]),
            const SizedBox(height: 10),
            Text(t('Step {n} of {m}', {'n': _i + 1, 'm': steps.length}).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.25, color: p.muted)),
            const SizedBox(height: 4),
            Text(steps[_i], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35)),
            const SizedBox(height: 12),
            Row(children: [
              _Btn('', icon: WI.back, soft: true, onTap: _i == 0 ? null : () => setState(() => _i--)),
              const SizedBox(width: 8),
              _i < steps.length - 1
                  ? _Btn(t('Next step'), expand: true, onTap: () {
                      setState(() => _i++);
                      widget.tap();
                    })
                  : _Btn(t('Share on WhatsApp'), icon: WI.share, expand: true, onTap: () {
                      widget.tap();
                      _launch(_wa(card.title ?? '', card.sourceUrl));
                    }),
            ]),
          ]),
        ),
      _Useful(card, widget.set, widget.tap),
    ]);
  }
}

class _News extends StatelessWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _News(this.card, this.set, this.tap);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(card.title ?? ''),
        if ((card.body ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(card.body!, style: TextStyle(fontSize: 15, height: 1.5, color: Pal.of(context).text.withValues(alpha: .8)))),
        if ((card.sourceUrl ?? '').isNotEmpty || card.post == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              if ((card.sourceUrl ?? '').isNotEmpty)
                _Btn(t('Read more'), soft: true, onTap: () {
                  tap();
                  openExternal(context, card.sourceUrl!);
                }),
              if (card.post == null) ...[
                const SizedBox(width: 8),
                _Btn('WhatsApp', soft: true, onTap: () {
                  tap();
                  _launch(_wa(card.title ?? '', card.sourceUrl));
                }),
              ],
            ]),
          ),
        _Useful(card, set, tap),
      ]);
}

class _Useful extends StatelessWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _Useful(this.card, this.set, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mine = card.mine?['useful'] as bool?;
    final up = (card.results?['up'] as num?)?.toInt() ?? 0;
    Future<void> vote(bool v) async {
      tap();
      try {
        set(await _answer(context.read<AuthProvider>().api, card.key, {'useful': v}));
      } catch (_) {}
    }

    Widget chip(Widget child, bool on, VoidCallback onTap, String label) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: on ? kGold.withValues(alpha: .2) : null, borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? kGold : p.border)),
              child: child,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Text(t('Was this useful?'), style: TextStyle(fontSize: 14, color: p.muted)),
        const SizedBox(width: 8),
        chip(Row(mainAxisSize: MainAxisSize.min, children: [WIcon(WI.thumbsUp, size: 16, color: p.text), if (up > 0) ...[const SizedBox(width: 4), Text('$up', style: const TextStyle(fontWeight: FontWeight.w600))]]), mine == true, () => vote(true), t('Useful')),
        const SizedBox(width: 8),
        chip(WIcon(WI.thumbsDown, size: 16, color: p.text), mine == false, () => vote(false), t('No')),
      ]),
    );
  }
}

/// Tender, scheme, event or job: the facts, Interested, and the official page.
class _Notice extends StatelessWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _Notice(this.card, this.set, this.tap);
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = card.data;
    final left = _daysLeft(d['deadline'] as String?);
    final interested = card.mine?['interested'] == true;
    final count = (card.results?['interested'] as num?)?.toInt() ?? 0;
    final emoji = switch (card.type) { 'tender' => '📄', 'scheme' => '🏛️', 'event' => '📅', _ => '👷' };
    Widget fact(WI icon, String text) => Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(icon, size: 13, color: p.text),
            const SizedBox(width: 4),
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        );
    final venue = (d['venue'] ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title('$emoji ${card.title ?? ''}'),
      if ((card.body ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(card.body!, style: TextStyle(fontSize: 15, height: 1.5, color: p.text.withValues(alpha: .8)))),
      if (left != null || (d['startsAt'] ?? '').toString().isNotEmpty || venue.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (left != null) fact(WI.clock, left),
            if ((d['startsAt'] ?? '').toString().isNotEmpty) fact(WI.clock, '${d['startsAt']}'),
            if (venue.isNotEmpty) fact(WI.pin, venue),
          ]),
        ),
      if ((d['who'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('✅ ${t('Who can apply')}: ${d['who']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      const SizedBox(height: 12),
      Row(children: [
        _Btn(
          '${t(interested ? 'Interested' : "I'm interested")}${count > 0 ? ' · $count' : ''}',
          icon: interested ? WI.tick : null,
          soft: interested,
          active: interested,
          expand: true,
          onTap: () async {
            tap();
            try {
              set(await _answer(context.read<AuthProvider>().api, card.key, {'interested': !interested}));
            } catch (_) {}
          },
        ),
        if ((card.sourceUrl ?? '').isNotEmpty) ...[
          const SizedBox(width: 8),
          _Btn(t(card.type == 'tender' ? 'Open tender' : 'Open'), soft: true, onTap: () {
            tap();
            openExternal(context, card.sourceUrl!);
          }),
        ],
        if (card.type == 'event' && venue.isNotEmpty) ...[
          const SizedBox(width: 8),
          Semantics(
            label: t('Directions'),
            child: _Btn('', icon: WI.pin, soft: true, onTap: () {
              tap();
              _launch('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(venue)}');
            }),
          ),
        ] else if (card.post == null) ...[
          const SizedBox(width: 8),
          Semantics(
            label: t('Share on WhatsApp'),
            child: _Btn('', icon: WI.share, soft: true, onTap: () {
              tap();
              _launch(_wa(card.title ?? '', card.sourceUrl));
            }),
          ),
        ],
      ]),
    ]);
  }
}

// ---------- the five controls on a personal card ----------

/// A personal card (built for this member: missed leads, demand near you, suppliers ...) has no post behind it, so it
/// gets the same five as every card, made for it: React (a liking signal for the mix, kept on this phone), Reply (a chat
/// with the house account that starts with what the card is about), Refer (pass it on over WhatsApp), Views (it is
/// yours alone: 1, a tap goes nowhere, as on posts) and Share.
class _CardActions extends StatefulWidget {
  final HouseCard card;
  final VoidCallback tap;
  const _CardActions({required this.card, required this.tap});
  @override
  State<_CardActions> createState() => _CardActionsState();
}

class _CardActionsState extends State<_CardActions> {
  String? _mine;
  String get _store => 'hc-react:${widget.card.key}';
  String get _text => widget.card.title ?? t(_sub[widget.card.type] ?? 'For you');
  static const _link = 'https://webweb.ai';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _mine = sp.getString(_store));
    });
  }

  Future<void> _react(String? next) async {
    setState(() => _mine = next);
    final sp = await SharedPreferences.getInstance();
    next == null ? sp.remove(_store) : sp.setString(_store, next);
    if (next != null && mounted) _cardEvent(context.read<AuthProvider>().api, widget.card, 'react');
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    Widget pill({required Widget icon, required String label, Color? color, Color? fill, Color? edge, VoidCallback? onTap}) {
      final c0 = color ?? p.muted;
      final title = Text(t(label), maxLines: 1, style: TextStyle(fontSize: wide ? 11.5 : 10, height: 1, fontWeight: FontWeight.w700, color: c0));
      final radius = BorderRadius.circular(wide ? 18 : 12);
      final c = Container(
        constraints: BoxConstraints(minWidth: wide ? 0 : 56, minHeight: wide ? 32 : 0),
        padding: wide ? const EdgeInsets.symmetric(horizontal: 10) : const EdgeInsets.fromLTRB(10, 6, 10, 4),
        decoration: BoxDecoration(color: fill ?? p.card, borderRadius: radius, border: wide ? Border.all(color: edge ?? p.border) : null),
        child: wide
            ? Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [icon, const SizedBox(width: 6), title])
            : Column(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 18, child: icon), const SizedBox(height: 4), title]),
      );
      return Semantics(button: true, label: t(label), excludeSemantics: true, child: onTap == null ? c : InkWell(onTap: onTap, borderRadius: radius, child: c));
    }

    final kids = <Widget>[
      ReactionPicker(
        quick: true,
        value: _mine,
        onChange: _react,
        trigger: (open) => pill(
          label: 'React',
          fill: open ? const Color(0xFFF43F5E).withValues(alpha: .1) : null,
          icon: _mine != null ? SizedBox(width: 18, height: 18, child: Center(child: ReactionGlyph(_mine!, size: 15))) : WIcon(WI.thumbsUp, size: 18, color: p.muted),
          color: _mine != null ? p.text : p.muted,
        ),
      ),
      pill(
        label: 'Reply',
        icon: WIcon(WI.talk, size: 18, color: p.muted),
        onTap: () {
          widget.tap();
          final a = widget.card.account;
          // the house account answers (AI, api/src/house-chat.ts)
          openChat(context, Peer(uid: a.uid, name: a.name, handle: a.handle), draft: '${t('About')} "$_text": ');
        },
      ),
      pill(
        label: 'Refer',
        icon: WIcon(WI.refer, size: 18, color: p.tagText),
        color: p.tagText,
        edge: kGold.withValues(alpha: .45),
        fill: kGold.withValues(alpha: .1),
        // the note and contacts to the house account in a chat, as Reply (refer_sheet.dart)
        onTap: () async {
          widget.tap();
          final a = widget.card.account;
          final r = await showReferToChat(context, uid: a.uid, name: a.name, about: _text.isNotEmpty ? _text : (widget.card.title ?? ''));
          if (r != null && context.mounted) toast(context, t(r.referred > 0 ? 'Referral sent' : 'Response sent'));
        },
      ),
      Semantics(label: t('1 view'), excludeSemantics: true, child: pill(label: 'Views', icon: WIcon(WI.views, size: 18, color: p.muted))),
      pill(
        label: 'Share',
        icon: WIcon(WI.share, size: 18, color: p.muted),
        onTap: () {
          widget.tap();
          SharePlus.instance.share(ShareParams(text: '$_text\n$_link', subject: _text)).catchError((_) => ShareResult.unavailable);
        },
      ),
    ];
    return FitRow(children: kids);
  }
}

// ---------- the deck: news, tips, tenders, schemes, events and jobs as swipeable cards ----------

const _readTypes = {'news', 'tip', 'tender', 'scheme', 'event', 'job'};
const _deckTypes = {..._readTypes, 'missed_leads', 'improve_ask', 'pulse', 'buy_select', 'profile', 'spotlight', 'ask_ai', 'quiz', 'poll'};
const _kindEmoji = {'news': '📰', 'tip': '💡', 'tender': '📄', 'scheme': '🏛️', 'event': '📅', 'job': '👷'};

/// the first words of a text, ended at a word
String _clip(String text, int max) {
  final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length <= max) return s;
  final cut = s.substring(0, max);
  final at = cut.lastIndexOf(' ');
  return '${cut.substring(0, at > max - 20 ? at : max)}…';
}

class _HouseDeck extends StatefulWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _HouseDeck(this.card, this.set, this.tap);
  @override
  State<_HouseDeck> createState() => _HouseDeckState();
}

class _HouseDeckState extends State<_HouseDeck> {
  final _ctl = DeckController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _go(int i) => _ctl.go(i);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final card = widget.card;
    final tap = widget.tap;
    final d = card.data;
    final tint = kCardColors[_tone[card.account.handle] ?? 'gold']!;
    final deckH = deckHeight(context);
    final emoji = _kindEmoji[card.type] ?? '✨';
    final kind = t(_sub[card.type] ?? 'For you');
    final left = _daysLeft(d['deadline'] as String?);
    final interested = card.mine?['interested'] == true;
    final count = (card.results?['interested'] as num?)?.toInt() ?? 0;
    final mineUseful = card.mine?['useful'] as bool?;
    final up = (card.results?['up'] as num?)?.toInt() ?? 0;
    final steps = [for (final x in ((d['steps'] as List?) ?? const [])) '$x'].take(6).toList();
    final notice = card.type != 'news' && card.type != 'tip';
    final venue = (d['venue'] ?? '').toString();
    final hasSource = (card.sourceUrl ?? '').isNotEmpty;
    final facts = <(String, String, String)>[
      if (left != null) ('⏳', t('Deadline'), left),
      if ((d['startsAt'] ?? '').toString().isNotEmpty) ('🗓️', t('Starts'), '${d['startsAt']}'),
      if (venue.isNotEmpty) ('📍', t('Where'), venue),
      if ((d['who'] ?? '').toString().isNotEmpty) ('✅', t('Who can apply'), '${d['who']}'),
    ];

    Future<void> vote(bool v) async {
      tap();
      try {
        widget.set(await _answer(context.read<AuthProvider>().api, card.key, {'useful': v}));
      } catch (_) {}
    }

    Future<void> toggleInterested() async {
      tap();
      try {
        widget.set(await _answer(context.read<AuthProvider>().api, card.key, {'interested': !interested}));
      } catch (_) {}
    }

    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .6));
    Widget head(String text) => Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: deckH * .095, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3));
    Widget chip(String e, String text) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(e, style: const TextStyle(fontSize: 12)), const SizedBox(width: 4), Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]),
        );
    Widget thumb(Widget child, bool on, VoidCallback onTap, String semantics) => Semantics(
          button: true,
          label: semantics,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: on ? kGold.withValues(alpha: .2) : p.card.withValues(alpha: .7), borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? kGold : p.border)),
              child: child,
            ),
          ),
        );

    // the cards of this post, each with one thing on it
    final cards = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head(card.title ?? ''),
        if (notice && left != null) Align(alignment: Alignment.centerLeft, child: chip('⏳', left)),
        if (card.type == 'tip' && steps.isNotEmpty) Align(alignment: Alignment.centerLeft, child: chip('🪜', t('{n} steps', {'n': steps.length}))),
        const Spacer(),
        if (notice)
          _Btn('${t(interested ? 'Interested' : "I'm interested")}${count > 0 ? ' · $count' : ''}', icon: interested ? WI.tick : null, soft: interested, active: interested, onTap: toggleInterested)
        else if (card.type == 'tip' && steps.isNotEmpty)
          _Btn('${t('See the steps')} →', onTap: () => _go((card.body ?? '').isNotEmpty ? 2 : 1))
        else if (hasSource)
          _Btn(t('Read more'), onTap: () {
            tap();
            openExternal(context, card.sourceUrl!);
          })
        else
          _Btn('📤 ${t('Share on WhatsApp')}', onTap: () {
            tap();
            _launch(_wa(card.title ?? ''));
          }),
      ]),
      if ((card.body ?? '').isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t(card.type == 'tip' ? 'Why it helps' : 'In short'), style: label),
          const SizedBox(height: 8),
          Text(_clip(card.body!, 200), maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 1.45)),
          const Spacer(),
          if (hasSource)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                tap();
                openExternal(context, card.sourceUrl!);
              },
              child: Text('🔗 ${t('Source')}: ${(card.sourceName ?? '').isNotEmpty ? card.sourceName : hostOf(card.sourceUrl!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.tagText)),
            ),
        ]),
      if (card.type == 'tip')
        for (var k = 0; k < steps.length; k++)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Step {n} of {m}', {'n': k + 1, 'm': steps.length}), style: label),
            const SizedBox(height: 8),
            Text(steps[k], maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: deckH * .08, fontWeight: FontWeight.w700, height: 1.3)),
            const Spacer(),
            Row(children: [
              for (var j = 0; j < steps.length; j++) Expanded(child: Container(height: 6, margin: EdgeInsets.only(right: j == steps.length - 1 ? 0 : 6), decoration: BoxDecoration(color: j <= k ? kGold : p.text.withValues(alpha: .1), borderRadius: BorderRadius.circular(3)))),
            ]),
          ]),
      if (notice && facts.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('At a glance'), style: label),
          const SizedBox(height: 8),
          Expanded(
            child: GridView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 76),
              children: [
                for (final f in facts.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: p.card.withValues(alpha: .7), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border.withValues(alpha: .6))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${f.$1} ${f.$2}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.muted)),
                      const SizedBox(height: 4),
                      Text(f.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.15)),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      // the last card: what to do with it
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('What next'), style: label),
        const SizedBox(height: 12),
        if (notice && hasSource) ...[
          _Btn(t(card.type == 'tender' ? 'Open tender' : 'Open the official page'), onTap: () {
            tap();
            openExternal(context, card.sourceUrl!);
          }),
          const SizedBox(height: 8),
        ],
        if (card.type == 'event' && venue.isNotEmpty) ...[
          _Btn(t('Directions'), icon: WI.pin, soft: true, onTap: () {
            tap();
            _launch('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(venue)}');
          }),
          const SizedBox(height: 8),
        ],
        if (!notice && hasSource) ...[
          _Btn(t('Read more'), onTap: () {
            tap();
            openExternal(context, card.sourceUrl!);
          }),
          const SizedBox(height: 8),
        ],
        if (card.post == null)
          _Btn('📤 ${t('Share on WhatsApp')}', soft: true, onTap: () {
            tap();
            _launch(_wa(card.title ?? '', card.sourceUrl));
          }),
        const Spacer(),
        Row(children: [
          Flexible(child: Text(t('Was this useful?'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted))),
          const SizedBox(width: 8),
          thumb(Row(mainAxisSize: MainAxisSize.min, children: [WIcon(WI.thumbsUp, size: 16, color: p.text), if (up > 0) ...[const SizedBox(width: 4), Text('$up', style: const TextStyle(fontWeight: FontWeight.w600))]]), mineUseful == true, () => vote(true), t('Useful')),
          const SizedBox(width: 8),
          thumb(WIcon(WI.thumbsDown, size: 16, color: p.text), mineUseful == false, () => vote(false), t('No')),
        ]),
      ]),
    ];

    return SwipeDeck(cards: cards, tint: tint, label: '$emoji $kind', controller: _ctl);
  }
}

// ---------- the personal cards as decks: leads, your ask, demand, a question, your page, a member, ask AI, quiz, poll ----------

class _PersonalDeck extends StatefulWidget {
  final HouseCard card;
  final ValueChanged<HouseCard> set;
  final VoidCallback tap;
  const _PersonalDeck(this.card, this.set, this.tap);
  @override
  State<_PersonalDeck> createState() => _PersonalDeckState();
}

class _PersonalDeckState extends State<_PersonalDeck> {
  final _ctl = DeckController();
  final _text = TextEditingController();
  final _picked = <String>[];
  bool _busy = false;
  List<SourcingItem>? _items;

  @override
  void dispose() {
    _ctl.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _saveBuy() async {
    setState(() => _busy = true);
    widget.tap();
    try {
      final d = await context.read<AuthProvider>().api.post('/feed/cards/buy', {'items': _picked}) as Map;
      if (!mounted) return;
      setState(() => _items = [for (final i in (d['items'] as List? ?? const [])) SourcingItem.fromJson(i as Map)]);
      Future.delayed(const Duration(milliseconds: 60), () => _ctl.go(2));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendAsk() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    widget.tap();
    final api = context.read<AuthProvider>().api;
    final a = widget.card.account;
    try {
      final chatId = (await api.post('/chats', {'userId': a.uid}) as Map)['id'] as String;
      await api.post('/chats/$chatId/messages', {'text': text});
      _text.clear();
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThread(chatId: chatId, peer: Peer(uid: a.uid, name: a.name, handle: a.handle))));
    } catch (_) {
      if (mounted) toast(context, t('Could not open the chat'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(int i) async {
    setState(() => _busy = true);
    widget.tap();
    try {
      widget.set(await _answer(context.read<AuthProvider>().api, widget.card.key, {'option': i}));
    } catch (_) {
      if (mounted) toast(context, t('Something went wrong. Please try again.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final card = widget.card;
    final tap = widget.tap;
    final d = card.data;
    final tint = kCardColors[_tone[card.account.handle] ?? 'gold']!;
    final deckH = deckHeight(context);
    final label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: .6));
    Widget head(String text) => Text(text, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: deckH * .095, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -.3));
    Widget big(String text, {int lines = 4}) => Text(text, maxLines: lines, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: deckH * .08, fontWeight: FontWeight.w700, height: 1.3));
    Widget col(List<Widget> kids) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
    Widget next(String text) => _Btn('${t(text)} →', soft: true, onTap: () => _ctl.go(1));
    final cards = <Widget>[];
    var emoji = '✨';

    switch (card.type) {
      case 'missed_leads':
        emoji = '🔥';
        final leads = [for (final l in (d['leads'] as List? ?? const []).take(3)) l as Map];
        final n = (d['total'] as num?)?.toInt() ?? leads.length;
        cards.add(col([
          head('🔥 ${t(n == 1 ? '1 lead near you has no replies yet' : '{n} leads near you have no replies yet', {'n': n})}'),
          const SizedBox(height: 8),
          Text(t('Be the first: the first few replies get the most attention.'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
          const Spacer(),
          Row(children: [
            _Btn(t('See all leads'), expand: true, onTap: () {
              tap();
              _push(context, const LeadsScreen());
            }),
            if (leads.isNotEmpty) ...[const SizedBox(width: 8), Flexible(child: next('Reply'))],
          ]),
        ]));
        for (final l in leads) {
          cards.add(col([
            Text('${kCategoryEmoji[l['category']] ?? '✨'} ${t(kCategoryShort[l['category']] ?? 'Ask')}', style: label),
            const SizedBox(height: 8),
            big('${l['title'] ?? ''}', lines: 3),
            if ([l['location'], l['budget']].any((x) => (x ?? '').toString().isNotEmpty))
              Padding(padding: const EdgeInsets.only(top: 6), child: Text([l['location'], l['budget']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted))),
            const Spacer(),
            _Btn(t('Reply'), onTap: () {
              tap();
              _push(context, PostDetailScreen(postId: '${l['id']}', openReply: true));
            }),
          ]));
        }
        cards.add(col([
          Text(t('What next'), style: label),
          const SizedBox(height: 12),
          _Btn(t('See all leads'), onTap: () {
            tap();
            _push(context, const LeadsScreen());
          }),
          const SizedBox(height: 8),
          _Btn(t('Alerts'), soft: true, onTap: () {
            tap();
            showAlertSheet(context);
          }),
        ]));
      case 'improve_ask':
        emoji = '⏳';
        final post = (d['post'] as Map?) ?? const {};
        final id = '${post['id']}';
        final hint = '${d['hint']}';
        void open() {
          tap();
          _push(context, PostDetailScreen(postId: id));
        }

        cards.add(col([
          head('⏳ ${t('Your ask has no replies yet')}'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: open,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: p.card.withValues(alpha: .6), borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: kGold, width: 4))),
              child: Text('${post['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const Spacer(),
          Row(children: [Flexible(child: next('What can help')), const SizedBox(width: 8), _Btn(t('Open'), soft: true, onTap: open)]),
        ]));
        cards.add(col([
          Text('💡 ${t('A tip')}', style: label),
          const SizedBox(height: 8),
          big(t(hint == 'budget' ? 'Asks with a budget get about twice the replies. Add one?' : hint == 'photo' ? 'A photo shows what you need at a glance. Add one?' : 'Share it in your WhatsApp groups: people there can reply here.')),
          const Spacer(),
          hint == 'share'
              ? _Btn(t('Share on WhatsApp'), onTap: () {
                  tap();
                  _launch(_wa('${post['title'] ?? ''}', 'https://webweb.ai/post/$id'));
                })
              : _Btn(t(hint == 'budget' ? 'Add a budget' : 'Add a photo'), onTap: open),
        ]));
      case 'pulse':
        emoji = '📊';
        final rows = [for (final r in (d['rows'] as List? ?? const [])) r as Map];
        final max = rows.fold<num>(1, (m, r) => (r['n'] as num? ?? 0) > m ? r['n'] as num : m);
        final place = '${d['place'] ?? ''}';
        const green = Color(0xFF059669);
        cards.add(col([
          head('📊 ${t('What {place} is asking for this week', {'place': place})}'),
          const SizedBox(height: 8),
          Text(t('{n} asks this week. Tap one to see them.', {'n': d['total'] ?? 0}), style: TextStyle(fontSize: 14, color: p.muted)),
          const Spacer(),
          if (rows.isNotEmpty) next('See the list'),
        ]));
        for (var i = 0; i < rows.length; i += 3) {
          cards.add(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final r in rows.skip(i).take(3))
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  tap();
                  _push(context, FindScreen(standalone: true, initialScope: 'asks', initialLocation: place, initialQuery: t(kCategoryShort[r['category']] ?? 'Other')));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Row(children: [
                      SizedBox(width: 24, child: Text(kCategoryEmoji[r['category']] ?? '✨', textAlign: TextAlign.center)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t(kCategoryShort[r['category']] ?? 'Other'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      Text('${r['n']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (r['change'] != null) ...[
                        const SizedBox(width: 6),
                        Text((r['change'] as num) >= 0 ? '▲${r['change']}%' : '▼${(r['change'] as num).abs()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: (r['change'] as num) >= 0 ? green : p.muted)),
                      ],
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 8,
                          color: p.card.withValues(alpha: .7),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(widthFactor: ((r['n'] as num? ?? 0) / max).clamp(0, 1).toDouble(), child: Container(decoration: const BoxDecoration(gradient: kGoldGradient))),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ]));
        }
        cards.add(col([
          Text('💡 ${t('What next')}', style: label),
          const SizedBox(height: 8),
          Text(t('Do any of these? Add them to your services and the asks come to you.'), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3)),
          const Spacer(),
          _Btn(t('Add to my services'), onTap: () async {
            tap();
            final auth = context.read<AuthProvider>();
            if (auth.profile == null) return;
            if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: auth.profile!))) == true) auth.loadProfile();
          }),
        ]));
      case 'buy_select':
        emoji = '🛒';
        final options = [for (final o in (d['options'] as List? ?? const [])) o as Map];
        cards.add(col([
          head('🛒 ${t('Which of these do you buy for your business?')}'),
          const SizedBox(height: 8),
          Text(t("Pick all that apply. We'll show you items from businesses near you."), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
          const Spacer(),
          _Btn('${t('Pick all that apply')} →', onTap: () => _ctl.go(1)),
        ]));
        cards.add(col([
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in options)
                  GestureDetector(
                    onTap: () => setState(() => _picked.contains(o['key']) ? _picked.remove(o['key']) : _picked.add('${o['key']}')),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _picked.contains(o['key']) ? kGold.withValues(alpha: .25) : p.card.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _picked.contains(o['key']) ? kGold : p.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_picked.contains(o['key'])) ...[WIcon(WI.tick, size: 16, color: p.text), const SizedBox(width: 6)],
                        Text(t('${o['label']}'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _Btn(_busy ? '…' : t(_picked.isNotEmpty ? 'Show me suppliers ({n})' : 'Pick at least one', {'n': _picked.length}), onTap: _picked.isEmpty || _busy ? null : _saveBuy),
        ]));
        final items = _items;
        if (items != null) {
          cards.add(col([
            Text('🙌 ${t("Thanks! Here's who sells them near you")}', style: label),
            Expanded(child: SingleChildScrollView(child: items.isNotEmpty ? _ItemRow(items, tap) : _hint(context, t("No one near you lists these yet. We'll show them here as they join.")))),
          ]));
        }
      case 'profile':
        emoji = '🚀';
        final pct = (d['percent'] as num?)?.toInt() ?? 0;
        final item = t('${d['label'] ?? ''}');
        cards.add(Row(children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: 68, height: 68, child: CircularProgressIndicator(value: pct / 100, strokeWidth: 7, backgroundColor: p.card.withValues(alpha: .7), color: const Color(0xFFE0A800), strokeCap: StrokeCap.round)),
              Text('$pct%', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('🚀 ${t('Your page is {n}% done', {'n': pct})}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 10),
            next("What's next"),
          ])),
        ]));
        cards.add(col([
          Text(t('What next'), style: label),
          const SizedBox(height: 8),
          Text(t('Next: {item}. Complete pages get more replies and leads.', {'item': item}), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3)),
          const Spacer(),
          _Btn(t('Add {item}', {'item': item.toLowerCase()}), onTap: () async {
            tap();
            final auth = context.read<AuthProvider>();
            if (auth.profile == null) return;
            if (await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: auth.profile!))) == true) auth.loadProfile();
          }),
        ]));
      case 'spotlight':
        emoji = '🏆';
        final u = (d['user'] as Map?) ?? const {};
        final peer = Peer.fromJson(u);
        final won = (d['won'] as num?)?.toInt() ?? 0;
        final replies = (d['replies'] as num?)?.toInt() ?? 0;
        final rose = p.dark ? const Color(0xFFFDA4AF) : const Color(0xFFBE123C);
        final bio = (u['bio'] ?? '').toString();
        cards.add(col([
          Row(children: [
            Avatar(name: peer.shownName, photoUrl: peer.photoUrl, size: 56, type: peer.userType, uid: peer.uid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(peer.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 4),
                  VerifiedBadge(level: (u['verification'] as num?)?.toInt() ?? 1, size: 15),
                ]),
                Text([u['category'], u['location']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            d['reason'] == 'won' ? '🏆 ${t(won == 1 ? 'Won 1 job this week' : 'Won {n} jobs this week', {'n': won})}' : '⚡ ${t('Replied to {n} asks this week', {'n': replies})}',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: rose, height: 1.25),
          ),
          const Spacer(),
          Row(children: [
            _Btn(t('View profile'), expand: true, onTap: () {
              tap();
              _push(context, ProfileScreen(handle: peer.handle));
            }),
            if (bio.isNotEmpty) ...[const SizedBox(width: 8), Flexible(child: next('About'))],
          ]),
        ]));
        if (bio.isNotEmpty) {
          cards.add(col([
            Text(t('About'), style: label),
            const SizedBox(height: 8),
            Text(bio, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.4)),
            const Spacer(),
            _Btn(t('Say hello'), soft: true, onTap: () {
              tap();
              openChat(context, peer);
            }),
          ]));
        }
      case 'ask_ai':
        emoji = '💬';
        cards.add(col([
          head('💬 ${t('What do you need today?')}'),
          const SizedBox(height: 8),
          Text(t("Tell me in your own words, in any language. I'll find who fits and post an ask for you if you like."), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
          const Spacer(),
          _Btn('${t('Ask')} →', onTap: () => _ctl.go(1)),
        ]));
        cards.add(col([
          Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                maxLength: 300,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendAsk(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: t('e.g. 2 welders for a week in Turbhe'),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _Btn(_busy ? '…' : t('Ask'), onTap: _busy || _text.text.trim().isEmpty ? null : _sendAsk),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final i in _askIdeas)
                  GestureDetector(
                    onTap: () => setState(() => _text.text = t(i)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: p.card.withValues(alpha: .6), borderRadius: BorderRadius.circular(20), border: Border.all(color: p.border)),
                      child: Text(t(i), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ),
          ),
        ]));
      default:
        // quiz and poll: the question, then the options, then how it went
        final quiz = card.type == 'quiz';
        emoji = quiz ? '🧠' : '🗳️';
        final options = [for (final o in (d['options'] as List? ?? const [])) '$o'];
        final mine = (card.mine?['option'] as num?)?.toInt();
        final answered = mine != null;
        final counts = [for (final c in (card.results?['counts'] as List? ?? const [])) (c as num).toInt()];
        final n = (card.results?['n'] as num?)?.toInt() ?? 0;
        final right = (d['answer'] as num?)?.toInt();
        const green = Color(0xFF059669);
        const red = Color(0xFFEF4444);
        final correctPct = quiz && n > 0 && right != null && right < counts.length ? (counts[right] / n * 100).round() : null;
        cards.add(col([
          head('$emoji ${card.title ?? ''}'),
          if ((card.body ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(card.body!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted))),
          const Spacer(),
          _Btn('${t(answered ? 'See how others did' : quiz ? 'Choose one answer' : 'Choose one option')} →', onTap: () => _ctl.go(1)),
        ]));
        cards.add(col([
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              for (var i = 0; i < options.length; i++)
                Builder(builder: (_) {
                  final pct = n > 0 && i < counts.length ? (counts[i] / n * 100).round() : 0;
                  final isRight = quiz && answered && i == right;
                  final wrongPick = quiz && answered && i == mine && i != right;
                  final edge = isRight ? green : (wrongPick ? red : (!quiz && answered && i == mine ? kGold : p.border));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: answered || _busy ? null : () => _pick(i),
                      child: Container(
                        height: 40,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(color: p.card.withValues(alpha: .6), borderRadius: BorderRadius.circular(12), border: Border.all(color: edge)),
                        child: Stack(children: [
                          if (answered) FractionallySizedBox(widthFactor: pct / 100, child: Container(color: isRight ? green.withValues(alpha: .2) : (wrongPick ? red.withValues(alpha: .15) : kGold.withValues(alpha: .25)))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(children: [
                              OptionMark(!answered ? OptionState.open : wrongPick ? OptionState.wrong : isRight ? OptionState.right : i == mine ? OptionState.mine : OptionState.other),
                              const SizedBox(width: 10),
                              Expanded(child: Text(options[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: i == mine ? FontWeight.w700 : FontWeight.w600))),
                              if (answered) Text('$pct%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  );
                }),
            ]),
          ),
          Text(
            answered ? (correctPct != null ? t('{n} answered · {p}% got it right', {'n': n, 'p': correctPct}) : t(n == 1 ? '1 answer so far' : '{n} answers so far', {'n': n})) : t(quiz ? "Tap an answer to see if you're right and how others did." : 'Tap to vote and see what others said.'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
        ]));
        if (answered && quiz) {
          cards.add(col([
            Text(mine == right ? '🎉 ${t('Right!')}' : '💡 ${t('Good try!')}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if ((d['explain'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${d['explain']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.4))),
            const Spacer(),
            if ((card.sourceUrl ?? '').isNotEmpty)
              GestureDetector(
                onTap: () => openExternal(context, card.sourceUrl!),
                child: Text('🔗 ${t('Source')}: ${(card.sourceName ?? '').isNotEmpty ? card.sourceName : hostOf(card.sourceUrl!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.tagText)),
              ),
          ]));
        }
    }
    return SwipeDeck(cards: cards, tint: tint, label: '$emoji ${t(_sub[card.type] ?? 'For you')}', controller: _ctl);
  }
}
