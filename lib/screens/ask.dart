import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../location.dart';
import '../models.dart';
import '../places.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import '../widgets/tour.dart';
import 'post_detail.dart';

const _maxAskImages = 10;
const _draftKey = 'webweb_ask_draft';

/// Template blanks such as [area] or [2]: they must be replaced before an ask goes out.
final _blank = RegExp(r'\[[^\]\n]{1,60}\]');

/// Tip and budget presets per category (web post/new TEMPLATES).
const _tips = <String, (String, List<String>)>{
  'job': ('Role, experience, salary and joining date get the most replies.', ['₹12,000 - ₹18,000 / month', '₹18,000 - ₹25,000 / month', '₹25,000+ / month']),
  'supplier': ('Add quantity and delivery area so suppliers can quote straight away.', ['Best price', 'Bulk rate', 'Per piece quote']),
  'buyer': ('Say what you make and the minimum order you can serve.', ['Bulk orders', 'Retail + wholesale']),
  'logistics': ('Load, route and date let transporters price it quickly.', ['₹5,000 - ₹10,000 / trip', '₹10,000 - ₹20,000 / trip']),
  'funding': ('Turnover, amount and purpose build trust with lenders and investors.', ['₹5 - ₹10 lakh', '₹10 - ₹25 lakh', '₹25 lakh+']),
  'advice': ('Share what you already tried; people give better opinions.', []),
  'mentorship': ('Be specific about what you can help with.', ['Free']),
  'partnership': ('Say what you bring and what you expect from a partner.', ['Profit share', 'Equal investment']),
  'machinery': ('Make, age, condition and price. Photos help a lot.', ['₹50,000 - ₹1 lakh', '₹1 - ₹5 lakh', 'On rent / month']),
  'space': ('Size, area and monthly budget narrow the search fast.', ['₹15,000 - ₹30,000 / month', '₹30,000 - ₹60,000 / month']),
  'training': ('Number of learners and timing help trainers respond.', ['₹5,000 - ₹10,000 / person', '₹10,000+ / person']),
  'jobwork': ('Process, quantity and drawing or sample let job workers quote quickly.', ['Per piece rate', 'Monthly contract']),
  'compliance': ('Say exactly what filing or registration you need and by when.', ['₹2,000 - ₹5,000', '₹5,000 - ₹10,000', 'Monthly retainer']),
  'export': ('Product, country and whether you have an IEC help agents respond.', ['Per shipment fee', 'Commission']),
  'tender': ('Mention registrations (GeM, Udyam) and what you can supply.', []),
  'digital': ('Share your business type and what you want built or run.', ['₹5,000 - ₹15,000', '₹15,000 - ₹50,000', '₹10,000 / month']),
  'repair': ('Make, model and the fault help technicians quote and visit faster.', ['₹2,000 - ₹5,000 / visit', 'Yearly AMC']),
  'other': ('Mention quantity, area and timing to get faster replies.', []),
};

/// Ready-made asks per category (name, title, description). Tap one, then edit the [brackets].
const _samples = <String, List<(String, String, String)>>{
  'job': [
    ('Operator / worker', 'Need 3 [machine] operators in [area]', 'Role: [CNC / VMC / lathe] operator\nExperience: 2+ years\nSalary: ₹[18,000] to ₹[25,000] per month\nTiming: 9 am to 6 pm, 6 days a week\nJoining: immediate'),
    ('Driver / delivery', 'Need [2] delivery drivers with own bikes in [area]', 'Role: delivery driver\nVehicle: own bike with licence\nSalary: ₹[16,000] to ₹[20,000] per month plus fuel\nArea: [Vashi, Turbhe]\nJoining: immediate'),
    ('Office / accounts', 'Need an accountant for GST and Tally in [area]', 'Role: accountant\nExperience: [2] years in GST filing and Tally\nSalary: ₹[15,000] to ₹[20,000] per month\nTiming: [3] days a week or full time\nJoining: within 7 days'),
  ],
  'supplier': [
    ('Raw material', 'Looking for a supplier of [material] in [area]', 'Item and grade: [material, grade]\nQuantity per month: [quantity]\nDelivery location: [area]\nPayment terms: [30 days credit / advance]\nNeeded from: [date]'),
    ('Packaging', 'Need [corrugated boxes] supplier, [3,000] pieces a month', 'Item: [5-ply corrugated boxes]\nSize: [18 x 12 x 10 inch]\nQuantity per month: [3,000] pieces\nDelivery to: [area]\nSend a sample and price per piece'),
  ],
  'buyer': [
    ('Selling my product', 'Looking for buyers of [product] in [area]', 'What we make: [product]\nMinimum order: [quantity]\nCapacity per month: [quantity]\nLocation: [area]\nDelivery: [own vehicle / buyer pickup]'),
    ('Stock clearance', '[Quantity] of [product] in stock, looking for buyers', 'Product: [product, brand]\nStock: [quantity]\nPrice: ₹[rate] per [unit]\nLocation: [area]\nAvailable: immediately'),
  ],
  'logistics': [
    ('Load transport', 'Need transport from [place] to [place] on [date]', 'Load type and weight: [goods, weight]\nPickup: [place]\nDrop: [place]\nDate: [date]\nVehicle type: [tempo / 14 ft / container]'),
    ('Regular runs', 'Need a 1-tonne tempo on monthly contract in [area]', 'Route: [place] to [place]\nRuns: [6] days a week, morning\nLoad: [type of goods]\nBudget: ₹[28,000] per month\nStart: [date]'),
  ],
  'funding': [
    ('Working capital', 'Looking for ₹[10 lakh] working capital loan', 'Business: [what you do], [4] years running\nAmount needed: ₹[10 lakh]\nPurpose: [stock / fuel / salaries]\nTurnover: ₹[amount] per year\nCollateral: [available / not available]'),
    ('Investor', 'Seeking investor for [business] expansion', 'Business: [what you do]\nAmount: ₹[amount]\nUse of funds: [new machine / second unit]\nReturns offered: [profit share / equity]\nLocation: [area]'),
  ],
  'advice': [
    ('Which to choose', 'Which [option] is better for [situation]?', 'Situation: [describe your business need]\nOptions I am considering: [A] and [B]\nWhat I have tried: [short note]\nWhat I want to decide: [decision]'),
    ('How to', 'How do I [do something] for my business?', 'Context: [business, size, area]\nWhat I have tried: [short note]\nWhere I am stuck: [problem]'),
  ],
  'mentorship': [
    ('Offer advice', 'Offering free advice on [topic]', 'Experience: [years] in [field]\nI can help with: [topics]\nBest time to connect: [days and time]\nMode: chat or call'),
    ('Looking for a mentor', 'Looking for a mentor in [field]', 'About me: [business or role]\nWhat I want to learn: [topic]\nTime I can give: [hours per week]'),
  ],
  'partnership': [
    ('Business partner', 'Looking for a partner for [business idea] in [area]', 'Idea: [short description]\nWhat I bring: [skills, money, space]\nWhat I need: [skills, money, contacts]\nModel: [profit share / equal investment]\nLocation: [area]'),
    ('Tie-up', 'Open to a tie-up with [type of business]', 'About us: [business]\nWhat we offer: [services]\nWhat we look for: [type of partner]\nArea: [area]'),
  ],
  'machinery': [
    ('Machine for sale', '[Machine] for sale in [area]', 'Make and model: [make, model]\nAge and condition: [years], [working / needs service]\nPrice: ₹[amount]\nLocation: [area]\nPhotos available on request'),
    ('Need to rent / buy', 'Looking to rent or buy a [machine]', 'Machine: [type, capacity]\nUse: [what for]\nBudget: ₹[amount] or ₹[amount] per month\nLocation: [area]\nNeeded from: [date]'),
  ],
  'space': [
    ('Godown / warehouse', 'Need [2,000] sq ft godown near [area]', 'Size: [2,000] sq ft\nPurpose: storing [goods]\nBudget: ₹[40,000] per month\nFacilities: truck access, ground floor\nFrom: [date], lease of [11] months'),
    ('Office / shop', 'Need a [500] sq ft office or shop in [area]', 'Size: [500] sq ft\nPurpose: [office / shop for ...]\nBudget: ₹[25,000] per month\nFrom: [date]'),
  ],
  'training': [
    ('Staff training', 'Looking for training in [skill] for [number] people', 'Skill: [skill]\nWho is it for: [number] [workers / staff]\nMode: [in person / online]\nPreferred timing: [dates, hours]\nBudget: ₹[amount] per person'),
    ('Offering training', 'Offering [skill] training in [area]', 'Skill: [skill]\nBatch size: [number]\nDuration: [weeks]\nFee: ₹[amount] per person\nStart date: [date]'),
  ],
  'jobwork': [
    ('Need job work done', 'Need [CNC machining] job work, [500] pieces a month', 'Process: [CNC turning / VMC / welding / powder coating]\nPart and material: [part, material]\nQuantity per month: [500] pieces\nDrawing: [available / sample available]\nDelivery: [area], [weekly]'),
    ('Offering job work', '[VMC / CNC] job work capacity available in [area]', 'Machines: [list machines]\nCapacity: [hours / pieces per month]\nMaterials handled: [steel, aluminium]\nTolerance: [±0.05 mm]\nLocation: [area]'),
  ],
  'compliance': [
    ('GST filing', 'Need a CA for monthly GST filing in [area]', 'Business type: [trader / manufacturer / service]\nTurnover: ₹[amount] per year\nHelp needed: [GSTR-1, GSTR-3B, annual return]\nStart: [date]'),
    ('Registration', 'Need help with [Udyam / FSSAI / trademark / Shop Act] registration', 'Registration needed: [Udyam / FSSAI / trademark / Shop Act]\nBusiness: [what you do]\nLocation: [area]\nNeeded by: [date]'),
  ],
  'export': [
    ('First export', 'Need guidance to export [product] to [country]', 'Product: [product, HS code if known]\nQuantity: [per month]\nTarget country: [country]\nIEC: [have / need]\nHelp needed: [documents, freight forwarder, buyers]'),
    ('Import', 'Looking for an agent to import [item] from [country]', 'Item: [item]\nQuantity: [quantity]\nSource country: [country]\nCustoms clearance: [needed]\nBudget: ₹[amount]'),
  ],
  'tender': [
    ('Supply order', 'Looking for government / PSU supply orders for [product]', 'Product: [product]\nRegistrations: [GeM, Udyam, ISO]\nCapacity: [per month]\nLocation: [area]\nLooking for: [tenders, vendor registration help]'),
    ('Sub-contract', 'Need a sub-contractor for [work] under a tender in [area]', 'Work: [scope]\nQuantity / value: [amount]\nTimeline: [weeks]\nLocation: [area]\nRequired: [experience, registrations]'),
  ],
  'digital': [
    ('Website', 'Need a simple website with product catalogue for [business]', 'Business: [what you do]\nPages needed: [home, products, contact]\nWhatsApp / enquiry button: yes\nLaunch by: [date]'),
    ('Marketing', 'Need [Google / Instagram] marketing for [business] in [area]', 'Business: [what you do]\nGoal: [calls, walk-ins, orders]\nMonthly budget: ₹[amount]\nArea: [area]'),
  ],
  'repair': [
    ('Machine repair', 'Need a technician for [machine] repair in [area]', 'Machine and make: [machine, make, model]\nProblem: [what is happening]\nLocation: [area]\nUrgency: [today / this week]'),
    ('AMC', 'Looking for yearly AMC for [AC / CCTV / compressor] in [area]', 'Equipment: [type, number of units]\nLocation: [area]\nVisits needed: [per year]\nBudget: ₹[amount] per year'),
  ],
  'other': [
    ('General ask', 'Looking for [what you need] in [area]', 'What I need: [details]\nQuantity: [number]\nArea: [area]\nNeeded by: [date]'),
  ],
};

/// Keyword rules: a light nudge toward the right category (web HINTS).
final _hints = <(String, RegExp)>[
  ('job', RegExp(r'\b(hire|hiring|vacanc|job|salary|operator|driver|helper|worker|staff|manpower|accountant|salesman|fresher|recruit)', caseSensitive: false)),
  ('logistics', RegExp(r'\b(transport|truck|tempo|courier|cargo|shipping|delivery|pickup|container|freight)', caseSensitive: false)),
  ('funding', RegExp(r'\b(loan|fund|investor|investment|capital|finance|credit|mudra)', caseSensitive: false)),
  ('machinery', RegExp(r'\b(machine|cnc|lathe|press|equipment|compressor|generator|rent)\b', caseSensitive: false)),
  ('space', RegExp(r'\b(office|godown|shop|sq ?ft|warehouse|premises|factory space|lease)', caseSensitive: false)),
  ('training', RegExp(r'\b(training|course|workshop|skill|certificate|learn)', caseSensitive: false)),
  ('partnership', RegExp(r'\b(partner|collaborat|tie-?up|joint venture|jv)\b', caseSensitive: false)),
  ('supplier', RegExp(r'\b(supplier|vendor|raw material|wholesale|quotation|steel|packaging|material)', caseSensitive: false)),
  ('buyer', RegExp(r'\b(buyer|customer|bulk order|distributor|dealer)', caseSensitive: false)),
  ('advice', RegExp(r'\b(advice|suggest|opinion|recommend|which is better|how to|should i)', caseSensitive: false)),
  ('jobwork', RegExp(r'\b(job ?work|contract manufactur|machining|fabrication|powder coat|sub-?contract)', caseSensitive: false)),
  ('compliance', RegExp(r'\b(gst|itr|tax|ca |chartered|udyam|msme|fssai|trademark|license|licence|legal|compliance|roc)\b', caseSensitive: false)),
  ('export', RegExp(r'\b(export|import|iec|dgft|customs|freight forward)', caseSensitive: false)),
  ('tender', RegExp(r'\b(tender|gem|government order|psu|vendor registration)', caseSensitive: false)),
  ('digital', RegExp(r'\b(website|app development|seo|digital marketing|instagram|google ads|logo|branding)', caseSensitive: false)),
  ('repair', RegExp(r'\b(repair|service|amc|maintenance|technician|breakdown)', caseSensitive: false)),
];

String? _detectCategory(String text) {
  if (text.trim().length < 8) return null;
  for (final (cat, re) in _hints) {
    if (re.hasMatch(text)) return cat;
  }
  return null;
}

/// Reach radius steps (web/src/lib/geo.ts RADIUS_STEPS); the last one covers all of India.
const _radii = [5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 3000000];
String _radiusLabel(int m) => m >= 3000000 ? t('Pan-India') : '${m ~/ 1000} km';

/// Section heading in the composer (web: 12px bold uppercase muted).
Widget _caps(Pal p, String s, {WI? icon}) => Row(children: [
      if (icon != null) ...[WIcon(icon, size: 14, color: p.muted, still: true), const SizedBox(width: 6)],
      Text(t(s).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
    ]);

/// Ask tab (web post/new): Ask or Update.
class AskScreen extends StatefulWidget {
  final VoidCallback onPosted;
  /// the Ask tab is on screen (it stays mounted behind the others)
  final bool active;
  const AskScreen({super.key, required this.onPosted, this.active = true});
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(children: [
          for (final e in [(0, WI.ask, 'Ask'), (1, WI.updates, 'Update')])
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = e.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == e.$1 ? p.text : Colors.transparent, width: 2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    WIcon(e.$2, size: 18, strokeWidth: 1.8, color: _tab == e.$1 ? p.text : p.muted),
                    const SizedBox(width: 8),
                    Text(t(e.$3), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _tab == e.$1 ? p.text : p.muted)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      Expanded(child: _tab == 0 ? _AskForm(onPosted: widget.onPosted, active: widget.active) : _UpdateForm(onPosted: widget.onPosted)),
    ]);
  }
}

class _AskForm extends StatefulWidget {
  final VoidCallback onPosted;
  final bool active;
  const _AskForm({required this.onPosted, this.active = true});
  @override
  State<_AskForm> createState() => _AskFormState();
}

class _Photo {
  final String id;
  final XFile file;
  String? url;
  bool failed = false;
  late final Future<String> job;
  _Photo(this.id, this.file);
}

class _AskFormState extends State<_AskForm> {
  String _category = kPostCategories.first.value;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _other = TextEditingController();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  String _location = '';
  String _urgency = '7_days';
  String _budget = '';
  int _budgetKey = 0; // rebuilds the budget fields when the value is set from outside
  ({double lat, double lng, int radiusM})? _geo;
  bool _locating = false;
  String? _locNote;
  int? _reach;
  bool _more = false;
  bool _dismissed = false;
  /// an unfinished ask from last time: offered, never filled in on its own
  Map? _savedDraft;
  bool _busy = false;
  String? _error;
  final List<_Photo> _photos = [];
  (String, String)? _undoTpl;
  // polish
  bool _aiOn = false;
  String _aiEngine = 'basic';
  bool _aiBusy = false;
  String? _aiError;
  Map<String, String>? _aiDraft;
  String _aiField = 'title';
  (String, String)? _aiUndo;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    context.read<AuthProvider>().api.get('/ai/status').then((r) {
      if (mounted) {
        setState(() {
          _aiOn = (r as Map)['available'] == true;
          _aiEngine = r['engine'] == 'ai' ? 'ai' : 'basic';
        });
      }
    }).catchError((_) {});
    _title.addListener(_changed);
    _desc.addListener(_changed);
    _maybeTour();
  }

  @override
  void didUpdateWidget(covariant _AskForm old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _maybeTour();
  }

  /// first visit to Ask: a short walk through the form
  void _maybeTour() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) Tours.maybeShow(context, 'ask', kAskTour);
    });
  }

  void _changed() {
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _restoreDraft() async {
    final profile = context.read<AuthProvider>().profile;
    Map? draft;
    try {
      draft = jsonDecode((await SharedPreferences.getInstance()).getString(_draftKey) ?? 'null') as Map?;
    } catch (_) {}
    if (!mounted) return;
    // the form always opens empty; an unfinished ask is offered with Continue
    if (draft != null && ('${draft['title'] ?? ''}'.isNotEmpty || '${draft['description'] ?? ''}'.isNotEmpty)) _savedDraft = draft;
    if ((profile?.location ?? '').isNotEmpty) {
      final c = findPlace(profile!.location);
      setState(() {
        _location = profile.location;
        if (c?.lat != null) _geo = (lat: c!.lat!, lng: c.lng!, radiusM: _cityRadius(c));
      });
    } else {
      setState(() {});
    }
    _loadReach();
  }

  /// Continue the unfinished ask from last time.
  void _continueDraft() {
    final draft = _savedDraft;
    if (draft == null) return;
    setState(() {
        _category = (draft['category'] as String?) ?? _category;
        _title.text = '${draft['title'] ?? ''}';
        _desc.text = '${draft['description'] ?? ''}';
        _location = '${draft['locationPref'] ?? ''}';
        if ('${draft['urgency'] ?? ''}'.isNotEmpty) _urgency = '${draft['urgency']}';
        _budget = '${draft['budget'] ?? ''}';
        _budgetKey++;
        final g = draft['geo'] as Map?;
        if (g != null) {
          final r = (g['radiusM'] as num).toInt();
          _geo = (lat: (g['lat'] as num).toDouble(), lng: (g['lng'] as num).toDouble(), radiusM: _radii.contains(r) ? r : 100000);
        }
        _savedDraft = null;
    });
    _loadReach();
  }

  Future<void> _saveDraft() async {
    if (_title.text.isEmpty && _desc.text.isEmpty) return;
    try {
      (await SharedPreferences.getInstance()).setString(_draftKey, jsonEncode({
        'category': _category, 'title': _title.text, 'description': _desc.text, 'locationPref': _location, 'urgency': _urgency, 'budget': _budget,
        if (_geo != null) 'geo': {'lat': _geo!.lat, 'lng': _geo!.lng, 'radiusM': _geo!.radiusM},
      }));
    } catch (_) {}
  }

  Future<void> _discardDraft() async {
    try {
      (await SharedPreferences.getInstance()).remove(_draftKey);
    } catch (_) {}
    setState(() {
      _title.clear();
      _desc.clear();
      _budget = '';
      _budgetKey++;
      _urgency = '7_days';
      _savedDraft = null;
    });
  }

  Future<void> _loadReach() async {
    try {
      final d = await context.read<AuthProvider>().api.get('/users/reach', {
        if (_location.isNotEmpty) 'location': _location,
        if (_geo != null) ...{'lat': _geo!.lat, 'lng': _geo!.lng, 'radiusM': _geo!.radiusM},
      }) as Map;
      if (mounted) setState(() => _reach = (d['members'] as num?)?.toInt());
    } catch (_) {
      if (mounted) setState(() => _reach = null);
    }
  }

  /// A city's reach as one of the radius steps (the smallest that covers it).
  int _cityRadius(Place c) => _radii.firstWhere((r) => r >= c.radiusKm * 1000, orElse: () => 100000);

  void _pickNode(PickedCity city) {
    final c = findPlace(city.name);
    setState(() {
      _location = city.name;
      if (c?.lat != null) {
        _geo = (lat: c!.lat!, lng: c.lng!, radiusM: _cityRadius(c));
      } else if (city.lat != null) {
        _geo = (lat: city.lat!, lng: city.lng!, radiusM: _geo?.radiusM ?? 100000); // a town not in the list: where the member is
      } else {
        _geo ??= (lat: 22.5, lng: 79.0, radiusM: 3000000); // no centre known: all of India until a pin is set
      }
    });
    _saveDraft();
    _loadReach();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locNote = null;
    });
    try {
      final h = await currentLocation(context, reason: t('To show your ask to members near you and count how many it will reach.'), source: 'ask');
      if (!mounted) return;
      setState(() {
        _geo = (lat: h.lat, lng: h.lng, radiusM: _geo?.radiusM ?? 100000);
        _location = h.node;
      });
      _loadReach();
      if (h.node.isEmpty && mounted) {
        // a town not in our list: ask its name, keep the pin where they are
        final c = await showCitySheet(context, near: (lat: h.lat, lng: h.lng));
        if (c != null && c.name.isNotEmpty && mounted) {
          setState(() => _location = c.name);
          _saveDraft();
        }
      }
    } on PermissionNotGiven {
      if (mounted) setState(() => _locNote = t('Location is off for WEBWEB. Allow it, or pick an area below.'));
    } catch (e) {
      if (mounted) setState(() => _locNote = '$e'.isEmpty ? t('Could not get your location. Allow location access or pick an area.') : '$e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyTemplate(String title, String desc) {
    setState(() {
      _undoTpl = (_title.text, _desc.text);
      _title.text = t(title);
      _desc.text = t(desc);
    });
    final start = _title.text.indexOf('[');
    final end = _title.text.indexOf(']', start);
    _titleFocus.requestFocus();
    if (start >= 0 && end > start) _title.selection = TextSelection(baseOffset: start, extentOffset: end + 1);
  }

  Future<void> _addPhotos() async {
    final room = _maxAskImages - _photos.length;
    if (room <= 0) return;
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 80, limit: room > 1 ? room : null);
    if (picked.isEmpty || !mounted) return;
    final api = context.read<AuthProvider>().api;
    for (final f in picked.take(room)) {
      final ph = _Photo('${DateTime.now().microsecondsSinceEpoch}${f.name}', f);
      ph.job = (() async => api.uploadImage(await f.readAsBytes(), f.name))();
      setState(() => _photos.add(ph));
      ph.job.then((u) {
        if (mounted) setState(() => ph.url = u);
      }).catchError((_) {
        if (mounted) setState(() => ph.failed = true);
      });
    }
  }

  Future<void> _runPolish(String field) async {
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiDraft = null;
      _aiField = field;
    });
    try {
      final r = await context.read<AuthProvider>().api.post('/ai/polish-ask', {'title': _title.text.trim(), 'description': _desc.text.trim(), 'category': _category}) as Map;
      if (mounted) setState(() => _aiDraft = {'title': '${r['title'] ?? ''}', 'description': '${r['description'] ?? ''}'});
    } catch (e) {
      if (mounted) setState(() => _aiError = '$e'.isEmpty ? t('AI could not polish this right now. Try again.') : '$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _applyPolish() {
    final d = _aiDraft;
    if (d == null) return;
    final ctl = _aiField == 'title' ? _title : _desc;
    setState(() {
      _aiUndo = (_aiField, ctl.text);
      ctl.text = d[_aiField] ?? ctl.text;
      _aiDraft = null;
    });
  }

  Future<void> _publish() async {
    final title = _title.text.trim(), desc = _desc.text.trim();
    setState(() => _error = null);
    if (_blank.hasMatch(title) || _blank.hasMatch(desc)) return setState(() => _error = t('Replace the [brackets] with your details'));
    setState(() => _busy = true);
    try {
      final images = <String>[];
      for (final ph in _photos) {
        images.add(await ph.job);
      }
      if (!mounted) return;
      final r = await context.read<AuthProvider>().api.post('/posts', {
        'title': title,
        'description': desc,
        'category': _category,
        if (_category == 'other' && _other.text.trim().isNotEmpty) 'categoryLabel': _other.text.trim(),
        if (_location.isNotEmpty) 'locationPref': _location,
        if (_budget.isNotEmpty) 'budget': _budget,
        if (_urgency.isNotEmpty) 'urgency': _urgency,
        if (_geo != null) ...{'lat': _geo!.lat, 'lng': _geo!.lng, 'radiusM': _geo!.radiusM},
        'images': images,
      }) as Map;
      try {
        (await SharedPreferences.getInstance()).remove(_draftKey);
      } catch (_) {}
      if (!mounted) return;
      _title.clear();
      _desc.clear();
      _other.clear();
      setState(() {
        _photos.clear();
        _budget = '';
        _budgetKey++;
        _urgency = '7_days';
        _savedDraft = null;
        _undoTpl = null;
      });
      widget.onPosted();
      Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${r['id']}')));
    } catch (_) {
      if (mounted) setState(() => _error = t('Could not publish your post. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    for (final c in [_title, _desc, _other]) {
      c.dispose();
    }
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  Widget _fieldActions(Pal p, String field) {
    final ctl = field == 'title' ? _title : _desc;
    final has = ctl.text.isNotEmpty;
    final canPolish = _aiOn && (_title.text.trim().length >= 3 || _desc.text.trim().length >= 10);
    if (!has && !canPolish) return const SizedBox.shrink();
    // the placeholder names the field; this row only carries its actions
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Spacer(),
        if (has)
          GestureDetector(
            onTap: () {
              ctl.clear();
              setState(() => _undoTpl = null);
              (field == 'title' ? _titleFocus : _descFocus).requestFocus();
            },
            child: Row(children: [WIcon(WI.close, size: 14, color: p.muted), const SizedBox(width: 4), Text(t('Clear'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))]),
          ),
        if (canPolish) ...[
          if (_aiUndo?.$1 == field && !_aiBusy) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() {
                ctl.text = _aiUndo!.$2;
                _aiUndo = null;
              }),
              child: Text(t('Undo'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted, decoration: TextDecoration.underline)),
            ),
          ],
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _aiBusy ? null : () => _runPolish(field),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(gradient: kGoldGradient, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const WIcon(WI.sparkle, size: 14, color: kInk),
                const SizedBox(width: 4),
                Text(_aiBusy && _aiField == field ? t('Polishing…') : t(_aiEngine == 'ai' ? 'Polish with AI' : 'Polish'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget? _suggestion(Pal p, String field) {
    final d = _aiDraft;
    if (d == null || _aiField != field || (d[field] ?? '').isEmpty) return null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kGold.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: kGold)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          WIcon(WI.sparkle, size: 14, color: p.tagText),
          const SizedBox(width: 6),
          Text(t('AI suggestion').toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.tagText)),
        ]),
        const SizedBox(height: 6),
        Text(d[field]!, style: field == 'title' ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w700) : TextStyle(fontSize: 14, color: p.text.withValues(alpha: .8))),
        const SizedBox(height: 10),
        Row(children: [
          GestureDetector(
            onTap: _applyPolish,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(20)),
              child: Text(t('Use this'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.onInk)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(onTap: () => setState(() => _aiDraft = null), child: Text(t('Dismiss'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))),
          const Spacer(),
          Flexible(child: Text(t('Check the details before you post.'), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: p.muted))),
        ]),
      ]),
    );
  }

  InputDecoration _input(Pal p, String hint, {String? error}) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.muted),
      counterText: '',
      filled: true,
      fillColor: p.card,
      errorText: error,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: b(p.border),
      enabledBorder: b(p.border),
      focusedBorder: b(p.text),
      errorBorder: b(p.danger),
      focusedErrorBorder: b(p.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final title = _title.text, desc = _desc.text;
    final tip = _tips[_category];
    final samples = _samples[_category] ?? const [];
    final found = _detectCategory('$title $desc');
    final suggestion = found != null && found != _category ? found : null;
    String? titleIdea;
    if (title.trim().isEmpty && desc.trim().length >= 20) {
      final first = desc.trim().split(RegExp(r'[.\n!?]')).first.trim();
      if (first.length >= 5) titleIdea = first.length > 100 ? first.substring(0, 100) : first;
    }
    final titleOk = title.trim().length >= 5;
    final descOk = desc.trim().length >= 20;
    final otherOk = _category != 'other' || _other.text.trim().length >= 2;
    final titleBlank = _blank.hasMatch(title), descBlank = _blank.hasMatch(desc);
    final ready = titleOk && descOk && otherOk && !titleBlank && !descBlank && !_photos.any((ph) => ph.failed);
    final missing = !titleOk
        ? 'Add a title'
        : !descOk
            ? 'Add a little more detail'
            : titleBlank || descBlank
                ? 'Replace the [brackets] with your details'
                : !otherOk
                    ? 'Say what this ask is about'
                    : '';
    final score = [titleOk, desc.trim().length >= 60, _location.isNotEmpty, _urgency.isNotEmpty, _budget.isNotEmpty, _photos.isNotEmpty].where((x) => x).length;
    final strength = score >= 5 ? 'Strong ask' : (score >= 3 ? 'Good ask' : 'Basic ask');
    final w = MediaQuery.of(context).size.width;

    Widget hScroll(List<Widget> children, {double height = 40}) => SizedBox(
          height: height,
          child: OverflowBox(
            maxWidth: w,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Center(child: children[i]),
            ),
          ),
        );
    Widget detail(WI icon, String value) => Flexible(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            WIcon(icon, size: 16, color: p.muted),
            const SizedBox(width: 4),
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ]),
        );
    Widget pill(String label, bool on, VoidCallback onTap, {double h = 40, double font = 14}) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: h,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? p.ink : p.chip, borderRadius: BorderRadius.circular(h)),
            child: Text(label, style: TextStyle(fontSize: font, fontWeight: FontWeight.w700, color: on ? p.onInk : p.muted)),
          ),
        );

    final form = ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        KeyedSubtree(key: Tours.key('ask-category'), child: hScroll(height: 40, [
          for (final o in kPostCategories)
            GestureDetector(
              onTap: () => setState(() {
                _category = o.value;
                _dismissed = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _category == o.value ? p.ink : p.canvas,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _category == o.value ? Colors.transparent : p.border.withValues(alpha: .7)),
                  boxShadow: _category == o.value ? const [BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1))] : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  WIcon(categoryIcon(o.value), size: 14, color: _category == o.value ? p.onInk : p.muted, still: true),
                  const SizedBox(width: 4),
                  Text(t(kCategoryShort[o.value] ?? o.label), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _category == o.value ? p.onInk : p.muted)),
                ]),
              ),
            ),
        ])),
        if (_category == 'other') ...[
          const SizedBox(height: 6),
          TextField(controller: _other, maxLength: 40, onChanged: (_) => setState(() {}), decoration: _input(p, t('What is this about? e.g. Event stall, Legal help, Insurance'))),
        ],
        if (suggestion != null && !_dismissed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              WIcon(WI.sparkle, size: 16, color: p.link),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${t('Sounds like')} '),
                  TextSpan(text: t(kCategoryShort[suggestion] ?? labelOf(kPostCategories, suggestion)), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]), style: const TextStyle(fontSize: 14)),
              ),
              GestureDetector(onTap: () => setState(() => _category = suggestion), child: Text(t('Use'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link))),
              const SizedBox(width: 10),
              GestureDetector(onTap: () => setState(() => _dismissed = true), child: WIcon(WI.close, size: 16, color: p.muted)),
            ]),
          ),
        ],
        // an unfinished ask from last time, until the member starts a new one
        if (_savedDraft != null && title.isEmpty && desc.isEmpty) ...[
          const SizedBox(height: 12),
          DashedBox(
            radius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${t('Unfinished ask')}: ${'${_savedDraft!['title'] ?? ''}'.isNotEmpty ? '“${_savedDraft!['title']}”' : t('from last time')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(onTap: _continueDraft, child: Text(t('Continue'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link))),
              const SizedBox(width: 12),
              GestureDetector(onTap: _discardDraft, child: Text(t('Discard'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))),
            ]),
          ),
        ],
        // quick starts, only while nothing is written yet (or to undo one)
        if (samples.isNotEmpty && ((title.trim().isEmpty && desc.trim().isEmpty) || _undoTpl != null)) ...[
          const SizedBox(height: 4),
          KeyedSubtree(key: Tours.key('ask-templates'), child: hScroll(height: 36, [
            for (final s in samples)
              GestureDetector(
                onTap: () => _applyTemplate(s.$2, s.$3),
                child: DashedBox(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    WIcon(WI.sparkle, size: 13, color: p.link),
                    const SizedBox(width: 4),
                    Text(t(s.$1), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.link)),
                  ]),
                ),
              ),
            if (_undoTpl != null)
              GestureDetector(
                onTap: () => setState(() {
                  _title.text = _undoTpl!.$1;
                  _desc.text = _undoTpl!.$2;
                  _undoTpl = null;
                }),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(t('Undo'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted))),
              ),
          ])),
        ],
        if (_aiError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_aiError!, style: TextStyle(fontSize: 12, color: p.danger))),
        const SizedBox(height: 12),
        _fieldActions(p, 'title'),
        TextField(
          key: Tours.key('ask-title'),
          controller: _title,
          focusNode: _titleFocus,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _descFocus.requestFocus(),
          style: const TextStyle(fontSize: 16),
          decoration: _input(p, t('e.g. Need 5 CNC operators in Turbhe'), error: titleBlank ? t('Replace the [brackets] with your details') : null),
        ),
        if (title.length > 80) Align(alignment: Alignment.centerRight, child: Text('${title.length}/100', style: TextStyle(fontSize: 12, color: p.muted))),
        if (titleIdea != null)
          GestureDetector(
            onTap: () => _title.text = titleIdea!,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                WIcon(WI.sparkle, size: 16, color: p.link),
                const SizedBox(width: 8),
                Expanded(child: Text('${t('Use as title')}: “$titleIdea”', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
              ]),
            ),
          ),
        _suggestion(p, 'title') ?? const SizedBox.shrink(),
        const SizedBox(height: 12),
        _fieldActions(p, 'description'),
        TextField(
          key: Tours.key('ask-description'),
          controller: _desc,
          focusNode: _descFocus,
          minLines: 3,
          maxLines: 12,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 16),
          decoration: _input(p, t(tip?.$1 ?? 'Describe what you need: quantity, quality, area, timing'), error: descBlank ? t('Replace the [brackets] with your details') : null),
        ),
        _suggestion(p, 'description') ?? const SizedBox.shrink(),
        if (desc.length > 800) Align(alignment: Alignment.centerRight, child: Text('${desc.length}/1000', style: TextStyle(fontSize: 12, color: p.muted))),
        const SizedBox(height: 12),
        hScroll(height: 56, [
          for (final ph in _photos)
            SizedBox(
              width: 56,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Opacity(
                    opacity: ph.url == null && !ph.failed ? .6 : 1,
                    child: FutureBuilder(future: ph.file.readAsBytes(), builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : ColoredBox(color: p.chip)),
                  ),
                  if (ph.url == null && !ph.failed) const Positioned(left: 0, right: 0, bottom: 0, height: 4, child: DecoratedBox(decoration: BoxDecoration(gradient: kGoldGradient))),
                  if (ph.failed)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(color: p.danger, padding: const EdgeInsets.symmetric(vertical: 2), child: Text(t('Failed'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                    ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.remove(ph)),
                      child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: kInk.withValues(alpha: .75), shape: BoxShape.circle), child: const WIcon(WI.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
          if (_photos.length < _maxAskImages)
            GestureDetector(
              onTap: _addPhotos,
              child: DashedBox(
                radius: 8,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      WIcon(WI.imageAdd, size: 20, color: p.muted),
                      const SizedBox(width: 8),
                      Text(_photos.isEmpty ? t('Add photos') : '${_photos.length}/$_maxAskImages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        // optional details behind one tidy row that always shows what is set
        Container(
          key: Tours.key('ask-details'),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _more = !_more),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Semantics(
                      label: t('Location, timing and budget'),
                      child: Row(children: [
                        detail(WI.pin, _location.isEmpty ? t('Anywhere') : t(_location)),
                        const SizedBox(width: 12),
                        detail(WI.clock, _urgency.isEmpty ? t('Any time') : t(labelOf(kUrgencies, _urgency))),
                        const SizedBox(width: 12),
                        detail(WI.rupee, _budget.isEmpty ? t('Any') : _budget),
                      ]),
                    ),
                  ),
                  AnimatedRotation(turns: _more ? .25 : 0, duration: const Duration(milliseconds: 150), child: WIcon(WI.chevronRight, size: 20, color: p.muted)),
                ]),
              ),
            ),
            if (_more)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _caps(p, 'Where'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: CityPill(value: _location, placeholder: 'Choose a city', height: 38, rounded: true, near: _geo == null ? null : (lat: _geo!.lat, lng: _geo!.lng), onChanged: _pickNode)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _locating ? null : _useMyLocation,
                      child: Opacity(
                        opacity: _locating ? .6 : 1,
                        child: DashedBox(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: 38,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              WIcon(WI.locate, size: 16, color: p.link, strokeWidth: 1.9),
                              const SizedBox(width: 6),
                              Text(_locating ? t('Locating…') : t('My location'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.link)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  if (_locNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_locNote!, style: TextStyle(fontSize: 12, color: p.muted))),
                  if (_geo != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text(t('Reach radius').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))),
                      Text(_radiusLabel(_geo!.radiusM), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(activeTrackColor: const Color(0xFFE0AD00), thumbColor: const Color(0xFFE0AD00), inactiveTrackColor: p.border, overlayShape: SliderComponentShape.noOverlay, trackHeight: 4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Slider(
                          value: _radii.indexOf(_geo!.radiusM).clamp(0, _radii.length - 1).toDouble(),
                          min: 0,
                          max: (_radii.length - 1).toDouble(),
                          divisions: _radii.length - 1,
                          onChanged: (v) => setState(() => _geo = (lat: _geo!.lat, lng: _geo!.lng, radiusM: _radii[v.round()])),
                          onChangeEnd: (_) => _loadReach(),
                        ),
                      ),
                    ),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final r in _radii)
                        GestureDetector(
                          onTap: () {
                            setState(() => _geo = (lat: _geo!.lat, lng: _geo!.lng, radiusM: r));
                            _loadReach();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _geo!.radiusM == r ? p.ink : p.chip, borderRadius: BorderRadius.circular(20)),
                            child: Text(_radiusLabel(r), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _geo!.radiusM == r ? p.onInk : p.muted)),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Text(t('Members inside the circle see this ask.'), style: TextStyle(fontSize: 12, color: p.muted)),
                  ],
                  const SizedBox(height: 16),
                  _caps(p, 'When'),
                  const SizedBox(height: 6),
                  hScroll([for (final o in kUrgencies) pill(t(o.label), _urgency == o.value, () => setState(() => _urgency = _urgency == o.value ? '' : o.value))]),
                  const SizedBox(height: 16),
                  _caps(p, 'Budget'),
                  const SizedBox(height: 6),
                  _BudgetRange(
                    key: ValueKey(_budgetKey),
                    value: _budget,
                    presets: tip?.$2 ?? const [],
                    onChanged: (v) {
                      setState(() => _budget = v);
                      _saveDraft();
                    },
                  ),
                ]),
              ),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      ],
    );

    return Column(children: [
      Expanded(child: form),
      // Publish stays within thumb reach, above the island
      Container(
        key: Tours.key('ask-publish'),
        padding: EdgeInsets.fromLTRB(16, 8, 16, islandSpace(context) - 4),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [p.canvas, p.canvas.withValues(alpha: .95), p.canvas.withValues(alpha: 0)], stops: const [0, .7, 1])),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            WIcon(WI.users, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _reach != null ? '${t('Reaches')} $_reach ${t(_reach == 1 ? 'member' : 'members')}${_location.isNotEmpty ? ' ${t('in')} ${t(_location)}' : ''}' : t('Reaches nearby members'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted),
              ),
            ),
            if (ready || title.trim().isNotEmpty || desc.trim().isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(t(ready ? strength : missing), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
            ],
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: GoldButton(label: t('Publish Ask'), wi: WI.askPlus, loading: _busy, onPressed: ready ? _publish : null)),
        ]),
      ),
    ]);
  }
}

/// Budget as From and an optional To plus a unit, with quick presets (web budget-range.tsx).
class _BudgetRange extends StatefulWidget {
  final String value;
  final List<String> presets;
  final ValueChanged<String> onChanged;
  const _BudgetRange({super.key, required this.value, required this.presets, required this.onChanged});
  @override
  State<_BudgetRange> createState() => _BudgetRangeState();
}

const _units = ['month', 'piece', 'trip', 'day'];
const _num = r'₹?\s*[\d.,]+(?:\s*(?:lakh|lac|k|cr|crore))?\+?';
final _range = RegExp('^\\s*($_num)\\s*(?:-|–|to)\\s*($_num)\\s*(?:\\/\\s*([a-z][a-z ]{0,19}))?\\s*\$', caseSensitive: false);
final _single = RegExp('^\\s*($_num)\\s*(?:\\/\\s*([a-z][a-z ]{0,19}))?\\s*\$', caseSensitive: false);
final _upTo = RegExp('^\\s*up to\\s*($_num)\\s*(?:\\/\\s*([a-z][a-z ]{0,19}))?\\s*\$', caseSensitive: false);
String _strip(String v) => v.replaceFirst(RegExp(r'^₹\s*'), '').trim();

(String, String, String) _parseBudget(String v) {
  final up = _upTo.firstMatch(v);
  if (up != null) return ('', _strip(up.group(1)!), (up.group(2) ?? '').trim().toLowerCase());
  final r = _range.firstMatch(v);
  if (r != null) return (_strip(r.group(1)!), _strip(r.group(2)!), (r.group(3) ?? '').trim().toLowerCase());
  final s = _single.firstMatch(v);
  if (s != null) return (_strip(s.group(1)!), '', (s.group(2) ?? '').trim().toLowerCase());
  return (v.trim(), '', '');
}

String _money(String x) => RegExp(r'^\d').hasMatch(x.trim()) ? '₹${x.trim()}' : x.trim();

String _composeBudget(String from, String to, String unit) {
  if (from.trim().isEmpty && to.trim().isEmpty) return '';
  final base = from.trim().isEmpty ? 'Up to ${_money(to)}' : (to.trim().isNotEmpty ? '${_money(from)} - ${_money(to)}' : _money(from));
  return unit.isNotEmpty ? '$base / $unit' : base;
}

class _BudgetRangeState extends State<_BudgetRange> {
  late var _parts = _parseBudget(widget.value);
  late final _from = TextEditingController(text: _parts.$1);
  late final _to = TextEditingController(text: _parts.$2);
  late final _unitCtl = TextEditingController(text: _units.contains(_parts.$3) ? '' : _parts.$3);
  late bool _otherOpen = _parts.$3.isNotEmpty && !_units.contains(_parts.$3);

  void _set({String? from, String? to, String? unit}) {
    _parts = (from ?? _parts.$1, to ?? _parts.$2, unit ?? _parts.$3);
    setState(() {});
    widget.onChanged(_composeBudget(_parts.$1, _parts.$2, _parts.$3));
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _unitCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    Widget money(TextEditingController c, String label, String hint, void Function(String) on) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(label), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            onChanged: (v) {
              on(v);
              setState(() {});
            },
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: p.muted),
              prefixText: RegExp(r'^\d').hasMatch(c.text) || c.text.isEmpty ? '₹ ' : null,
              prefixStyle: TextStyle(color: p.muted, fontSize: 16),
              filled: true,
              fillColor: p.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: b(p.border),
              enabledBorder: b(p.border),
              focusedBorder: b(p.text),
            ),
          ),
        ]);
    Widget chip(String label, bool on, VoidCallback onTap, {double h = 32}) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: h > 32 ? 14 : 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? p.ink : p.chip, borderRadius: BorderRadius.circular(h)),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? p.onInk : p.muted)),
          ),
        );
    final showOther = _otherOpen;
    final composed = _composeBudget(_parts.$1, _parts.$2, _parts.$3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: money(_from, 'From (optional)', '20,000', (v) => _set(from: v))),
        const SizedBox(width: 12),
        Expanded(child: money(_to, 'To (optional)', '30,000', (v) => _set(to: v))),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text(t('Per'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
          for (final u in _units) ...[
            const SizedBox(width: 6),
            chip(t(u), _parts.$3 == u, () {
              _otherOpen = false;
              _set(unit: _parts.$3 == u ? '' : u);
            }),
          ],
          const SizedBox(width: 6),
          chip(t('Other'), showOther, () {
            if (showOther) {
              _otherOpen = false;
              _unitCtl.clear();
              _set(unit: '');
            } else {
              _otherOpen = true;
              if (_units.contains(_parts.$3)) _set(unit: '');
              setState(() {});
            }
          }),
        ]),
      ),
      if (showOther) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _unitCtl,
          autofocus: true,
          maxLength: 20,
          onChanged: (v) => _set(unit: v.replaceAll(RegExp(r'[^a-zA-Z ]'), '').toLowerCase()),
          decoration: InputDecoration(
            hintText: t('Your unit, e.g. hour, kg, sq ft'),
            hintStyle: TextStyle(color: p.muted),
            counterText: '',
            filled: true,
            fillColor: p.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: b(p.border),
            enabledBorder: b(p.border),
            focusedBorder: b(p.text),
          ),
        ),
      ],
      if (widget.presets.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final pr in widget.presets) ...[
              chip(t(pr), composed == _composeBudget(_parseBudget(pr).$1, _parseBudget(pr).$2, _parseBudget(pr).$3), () {
                final x = _parseBudget(pr);
                _from.text = x.$1;
                _to.text = x.$2;
                _otherOpen = x.$3.isNotEmpty && !_units.contains(x.$3);
                _unitCtl.text = _otherOpen ? x.$3 : '';
                _set(from: x.$1, to: x.$2, unit: x.$3);
              }, h: 36),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// Update tab (web UpdateForm): a photo, a caption, or both; disappears from the feed after 24 hours.
class _UpdateForm extends StatefulWidget {
  final VoidCallback onPosted;
  const _UpdateForm({required this.onPosted});
  @override
  State<_UpdateForm> createState() => _UpdateFormState();
}

class _UpdateFormState extends State<_UpdateForm> {
  XFile? _file;
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 75);
    if (f != null) setState(() => _file = f);
  }

  Future<void> _submit() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = _file == null ? null : await api.uploadImage(await _file!.readAsBytes(), _file!.name);
      await api.post('/updates', {if (url != null) 'imageUrl': url, if (_text.text.trim().isNotEmpty) 'text': _text.text.trim()});
      if (!mounted) return;
      _text.clear();
      setState(() => _file = null);
      toast(context, t('Update added'));
      widget.onPosted();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    return ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, islandSpace(context)), children: [
      Text(t('Updates disappear from the feed after 24 hours and stay in your profile archive.'), style: TextStyle(fontSize: 14, color: p.muted)),
      const SizedBox(height: 16),
      if (_file != null)
        GestureDetector(
          onTap: _pick,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              color: kInk,
              child: FutureBuilder(future: _file!.readAsBytes(), builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.contain, width: double.infinity) : const SizedBox(height: 160)),
            ),
          ),
        )
      else
        DashedBox(
          onTap: _pick,
          radius: 8,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              WIcon(WI.imageAdd, size: 32, color: p.muted),
              const SizedBox(height: 8),
              Text(t('Choose a photo (optional)'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.muted)),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      TextField(
        controller: _text,
        minLines: 3,
        maxLines: 6,
        maxLength: 200,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: t('Say something…'),
          hintStyle: TextStyle(color: p.muted),
          counterText: '',
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.all(14),
          border: b(p.border),
          enabledBorder: b(p.border),
          focusedBorder: b(p.text),
        ),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      const SizedBox(height: 16),
      GoldButton(label: t('Add update'), loading: _busy, onPressed: _file != null || _text.text.trim().isNotEmpty ? _submit : null),
    ]);
  }
}
