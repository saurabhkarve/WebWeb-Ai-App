import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_provider.dart';
import '../ask_types.dart';
import '../card_colors.dart';
import '../widgets/ask_deck.dart';
import 'dart:io' show File;
import '../i18n.dart';
import '../location.dart';
import '../models.dart';
import '../places.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/city_picker.dart';
import '../widgets/mention_suggest.dart';
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
  'consultant': ('Say the goal, your business size and the deliverable so consultants can quote a clear fee.', ['₹10,000 - ₹25,000', '₹25,000 - ₹1 lakh', 'Monthly retainer']),
  'export': ('Product, country and whether you have an IEC help agents respond.', ['Per shipment fee', 'Commission']),
  'tender': ('Mention registrations (GeM, Udyam) and what you can supply.', []),
  'digital': ('Share your business type and what you want built or run.', ['₹5,000 - ₹15,000', '₹15,000 - ₹50,000', '₹10,000 / month']),
  'repair': ('Make, model and the fault help technicians quote and visit faster.', ['₹2,000 - ₹5,000 / visit', 'Yearly AMC']),
  'daily': ('Say how often and from which date, and give your area or society name.', ['₹1,000 - ₹3,000 / month', '₹3,000 - ₹8,000 / month']),
  'events': ('Date, number of guests and venue help vendors quote quickly.', ['₹300 - ₹600 / plate', '₹10,000 - ₹50,000', '₹50,000 - ₹2 lakh']),
  'rental': ('Dates, location and whether you need a driver or operator help owners quote faster.', ['₹2,000 - ₹5,000 / day', '₹30,000 - ₹80,000 / month']),
  'wellness': ('Mention timing and whether you want a home visit or to visit a clinic.', ['₹500 - ₹1,500 / session', '₹3,000 - ₹8,000 / month']),
  'printing': ('Size, quantity and a sample or design file get you accurate rates.', ['₹5,000 - ₹20,000', '₹20,000 - ₹1 lakh']),
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
  'consultant': [
    ('Business growth', 'Need a business consultant to grow [business] in [area]', 'Business: [what you do, years running]\nTurnover: ₹[amount] a year\nHelp needed: [sales, costing, systems, expansion]\nEngagement: [one-time plan / monthly]\nStart by: [date]'),
    ('ISO / certification', 'Need an ISO [9001] certification consultant for my [factory]', 'Business: [product, number of staff]\nCertification: [ISO 9001 / 14001 / 45001, ZED, CE]\nLocation: [area]\nTarget date: [month]'),
    ('Project report / subsidy', 'Need a project report (DPR) for a [₹ amount] loan / subsidy', 'Project: [new unit / expansion]\nLoan or scheme: [bank loan, PMEGP, CMEGP, state subsidy]\nProject cost: ₹[amount]\nNeeded by: [date]'),
    ('Financial advisor', 'Looking for a financial advisor for [investments / insurance]', 'Goal: [retirement, child education, business surplus]\nAmount: ₹[amount]\nPreference: [mutual funds, insurance, FD]\nMeeting: [in person / call]'),
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
  'daily': [
    ('Milk delivery', 'Need daily milk delivery at [society / area]', 'Quantity: [litres per day]\nType: [cow / buffalo / packet]\nLocation: [society, area]\nStart from: [date]'),
    ('Housekeeping', 'Need housekeeping or cleaning service for [home / office] in [area]', 'Place: [home / office, size]\nFrequency: [daily / weekly]\nLocation: [area]\nStart from: [date]'),
    ('Tiffin', 'Looking for a tiffin service in [area]', 'Meals: [lunch / dinner]\nPeople: [number]\nPreference: [veg / non-veg]\nLocation: [area]'),
  ],
  'events': [
    ('Caterer', 'Need a caterer for [event] in [area]', 'Event and date: [event, date]\nGuests: [number]\nMenu: [veg / non-veg, cuisine]\nVenue: [area]'),
    ('Decorator or photographer', 'Looking for a [decorator / photographer] for [event] on [date]', 'Event and date: [event, date]\nVenue: [area]\nWhat I need: [details]\nBudget: ₹[amount]'),
  ],
  'rental': [
    ('Vehicle on hire', 'Need a [tempo / bus / cab] on hire for [days] in [area]', 'Vehicle: [type, capacity]\nDates: [from, to]\nRoute or area: [details]\nWith driver: [yes / no]'),
    ('Equipment on rent', 'Need [crane / JCB / generator / scaffolding] on rent in [area]', 'Equipment: [type, capacity]\nDays: [number]\nSite: [area]\nOperator needed: [yes / no]'),
  ],
  'wellness': [
    ('Physio or yoga', 'Looking for a [physiotherapist / yoga trainer] near [area]', 'For: [self / family]\nNeed: [details]\nTiming: [morning / evening]\nHome visit: [yes / no]'),
    ('Diagnostic or health camp', 'Need [diagnostic lab / health check-up camp] for [staff / society] in [area]', 'People: [number]\nTests: [details]\nLocation: [area]\nDate: [date]'),
  ],
  'printing': [
    ('Flex or signage', 'Need [flex / signboard] made for my shop in [area]', 'Size: [width x height]\nMaterial: [flex / acrylic / LED]\nQuantity: [number]\nNeeded by: [date]'),
    ('Boxes and labels', 'Need [number] [boxes / labels / brochures] printed', 'Item: [type, size]\nQuantity: [number]\nPaper or material: [details]\nNeeded by: [date]'),
  ],
  'other': [
    ('General ask', 'Looking for [what you need] in [area]', 'What I need: [details]\nQuantity: [number]\nArea: [area]\nNeeded by: [date]'),
  ],
};

/// Keyword rules: a light nudge toward the right category (web HINTS).
final _hints = <(String, RegExp)>[
  ('job', RegExp(r'\b(hire|hiring|vacanc|job|salary|operator|driver|helper|worker|staff|manpower|accountant|salesman|fresher|recruit)', caseSensitive: false)),
  ('daily', RegExp(r'\b(milk|dairy|newspaper|water cans?|water jars?|tiffin|laundry|housekeeping|maid|cleaning|security guard|gardener|door ?step|home delivery|pest control)', caseSensitive: false)),
  ('events', RegExp(r'\b(wedding|caterer|catering|decorat|event planner|party|dj|sound system|photograph|mandap|birthday)', caseSensitive: false)),
  ('wellness', RegExp(r'\b(clinic|doctor|physio|dentist|diagnostic|lab test|yoga|gym|fitness|diet|counsell?ing|therapy|massage)', caseSensitive: false)),
  ('printing', RegExp(r'\b(print|printing|flex|signage|visiting cards?|brochure|sticker|label|banner|standee)', caseSensitive: false)),
  ('rental', RegExp(r'\b(cab|bus|tempo|truck|crane|jcb|generator|scaffolding|vehicle|excavator|forklift)\b.{0,40}\b(rent|rental|hire|on hire)\b|\b(rent|rental|hire)\b.{0,40}\b(cab|bus|tempo|truck|crane|jcb|generator|scaffolding|vehicle|excavator|forklift)\b', caseSensitive: false)),
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
  ('consultant', RegExp(r'\b(consultant|consultancy|advisor|adviser|advisory|iso ?\d*|project report|dpr|subsidy|pmegp|business plan|financial plann)', caseSensitive: false)),
  ('export', RegExp(r'\b(export|import|iec|dgft|customs|freight forward)', caseSensitive: false)),
  ('tender', RegExp(r'\b(tender|gem|government order|psu|vendor registration)', caseSensitive: false)),
  ('digital', RegExp(r'\b(website|app development|seo|digital marketing|instagram|google ads|logo|branding)', caseSensitive: false)),
  ('repair', RegExp(r'\b(repair|amc|maintenance|servicing|technician|breakdown)', caseSensitive: false)),
];

String? _detectCategory(String text) {
  if (text.trim().length < 8) return null;
  for (final (cat, re) in _hints) {
    if (re.hasMatch(text)) return cat;
  }
  return null;
}

/// The types whose first example is offered before a type is known: the asks members post most.
const _starterCategories = ['job', 'supplier', 'buyer', 'logistics', 'space', 'jobwork', 'repair', 'daily', 'events', 'rental', 'machinery', 'compliance', 'consultant', 'digital'];

/// Reach radius steps (web/src/lib/geo.ts RADIUS_STEPS); the last one covers all of India.
const _radii = [5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 3000000];
String _radiusLabel(int m) => m >= 3000000 ? t('Pan-India') : '${m ~/ 1000} km';

/// Section heading in the composer (web: 12px bold uppercase muted).
Widget _caps(Pal p, String s, {WI? icon}) => Row(children: [
      if (icon != null) ...[WIcon(icon, size: 14, color: p.muted, still: true), const SizedBox(width: 6)],
      Text(t(s).toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
    ]);

/// Ask tab (web post/new): the ask, laid out like its row on Connect.
class AskScreen extends StatelessWidget {
  final VoidCallback onPosted;
  /// the Ask tab is on screen (it stays mounted behind the others)
  final bool active;
  /// one of your asks to change: the same card, filled in; saving pops with true
  final Post? edit;
  /// the Ask tab's back button (the island steps aside on Ask); the edit page has its own
  final VoidCallback? onBack;
  const AskScreen({super.key, required this.onPosted, this.active = true, this.edit, this.onBack});
  @override
  Widget build(BuildContext context) => _AskForm(onPosted: onPosted, active: active, edit: edit, onBack: onBack);
}

class _AskForm extends StatefulWidget {
  final VoidCallback onPosted;
  final bool active;
  final Post? edit;
  final VoidCallback? onBack;
  const _AskForm({required this.onPosted, this.active = true, this.edit, this.onBack});
  @override
  State<_AskForm> createState() => _AskFormState();
}

class _Photo {
  final String id;
  /// null for a photo the ask already has (editing)
  final XFile? file;
  String? url;
  bool failed = false;
  late final Future<String> job;
  _Photo(this.id, this.file);
  _Photo.saved(this.id, String u) : file = null {
    url = u;
    job = Future.value(u);
  }
}

class _AskFormState extends State<_AskForm> {
  /// empty until the words suggest a type or the member picks one
  String _category = '';
  /// the type follows the words until the member picks one
  bool _typeChosen = false;
  /// the chip whose choices are open under the ask
  String? _open;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _other = TextEditingController();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  String _location = '';
  String _urgency = '7_days';
  String _budget = '';
  String _color = randomCardColor(); // the card's colour: random until the member picks one
  int _budgetKey = 0; // rebuilds the budget fields when the value is set from outside
  ({double lat, double lng, int radiusM})? _geo;
  bool _locating = false;
  String? _locNote;
  int? _reach;
  /// an unfinished ask from last time: offered, never filled in on its own
  Map? _savedDraft;
  bool _busy = false;
  String? _error;
  final List<_Photo> _photos = [];
  /// before an example was used: title, details, type, whether the type was chosen
  (String, String, String, bool)? _undoTpl;
  // Ask AI
  bool _aiOn = false;
  bool _aiBusy = false;
  int _aiSpin = 0; // spins the pill's star on each Ask AI
  String? _aiError;
  Map<String, String>? _aiDraft;
  /// before an AI suggestion was used: title, details
  (String, String)? _aiUndo;
  Timer? _draftTimer;
  bool _hadText = false;
  /// the local AI's reading of the category (web: aiCategory), asked once the title is written and details typed
  Timer? _aiCatTimer;
  String? _aiCat;
  String? _aiType;
  String _askType = ''; // what the ask wants from members (kAskTypes)
  List<String> _pollOpts = ['', ''];
  /// editing: the stored pin is only sent again when the member moves it (the one we get back is rounded)
  bool _geoMoved = false;
  bool get _editing => widget.edit != null;
  /// tour targets are global keys: only the Ask tab carries them, never the editor opened over it
  GlobalKey? _tk(String target) => _editing ? null : Tours.key(target);

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _fillFromEdit(widget.edit!);
    } else {
      _restoreDraft();
    }
    context.read<AuthProvider>().api.get('/ai/status').then((r) {
      if (mounted) {
        setState(() => _aiOn = (r as Map)['available'] == true);
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
    if (!widget.active || _editing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) Tours.maybeShow(context, 'ask2', kAskTour);
    });
  }

  void _changed() {
    // until the member picks a category, it follows the words: a word match at once, then the local AI's
    // reading once the title is written and the details are being typed (any language and phrasing)
    if (!_typeChosen) {
      final title = _title.text.trim();
      final found = (title.length >= 5 ? _aiCat : null) ?? _detectCategory('${_title.text} ${_desc.text}');
      final type = (title.length >= 5 ? _aiType : null) ?? (found != null ? typeOfCategory(found) : null);
      if (type != null) {
        _askType = type;
        _category = categoryForType(type, found);
      } else if (found != null) {
        _category = found;
      }
      _aiCatTimer?.cancel();
      // the title is enough: the local AI reads what kind of ask it is from it
      if (title.length >= 5) {
        _aiCatTimer = Timer(const Duration(milliseconds: 700), () => _askAiCategory(title, _desc.text.trim()));
      }
    }
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _askAiCategory(String title, String description) async {
    try {
      final r = await context.read<AuthProvider>().api.post('/ai/category', {'title': title, 'description': description}) as Map;
      final c = r['category'] as String?;
      final ty = r['type'] as String?;
      // a newer edit or the member's own pick wins
      if (!mounted || (c == null && ty == null) || _typeChosen || _title.text.trim() != title || _desc.text.trim() != description) return;
      setState(() {
        _aiCat = c;
        _aiType = ty;
        if (ty != null) {
          _askType = ty;
          _category = categoryForType(ty, c);
        } else if (c != null) {
          _category = c;
        }
      });
    } catch (_) {}
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

  /// Editing: the card starts as the ask is now.
  void _fillFromEdit(Post e) {
    _category = e.category ?? 'other';
    _typeChosen = true;
    _askType = e.askType ?? typeOfCategory(e.category);
    _pollOpts = e.pollOptions.length >= 2 ? [...e.pollOptions] : ['', ''];
    _title.text = e.title ?? '';
    _desc.text = e.description ?? '';
    _other.text = e.categoryLabel ?? '';
    _location = e.locationPref ?? '';
    _urgency = e.urgency ?? '';
    _budget = e.budget ?? '';
    _color = cardColorOf(e);
    final c = findPlace(_location);
    final lat = e.lat ?? c?.lat, lng = e.lng ?? c?.lng;
    if (lat != null && lng != null) _geo = (lat: lat, lng: lng, radiusM: e.radiusM?.toInt() ?? (c == null ? 100000 : _cityRadius(c)));
    for (final u in e.images) {
      _photos.add(_Photo.saved(u, u));
    }
    _loadReach();
  }

  /// Continue the unfinished ask from last time.
  void _continueDraft() {
    final draft = _savedDraft;
    if (draft == null) return;
    setState(() {
        _category = (draft['category'] as String?) ?? _category;
        _typeChosen = _category.isNotEmpty;
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
    if (_editing) return;
    if (_title.text.isEmpty && _desc.text.isEmpty) {
      // everything typed was deleted: nothing to continue next time
      if (_hadText) {
        try {
          (await SharedPreferences.getInstance()).remove(_draftKey);
        } catch (_) {}
      }
      return;
    }
    _hadText = true;
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

  /// A city's reach as one of the radius steps (the smallest that covers it, at least 25 km).
  int _cityRadius(Place c) => _radii.firstWhere((r) => r >= math.max(c.radiusKm * 1000, 25000), orElse: () => 100000);

  void _pickNode(PickedCity city) {
    final c = findPlace(city.name);
    _geoMoved = true;
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
      _geoMoved = true;
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

  void _applyTemplate(String category, String title, String desc) {
    setState(() {
      _undoTpl = (_title.text, _desc.text, _category, _typeChosen);
      _aiUndo = null;
      _category = category;
      _askType = typeOfCategory(category);
      _typeChosen = true;
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

  Future<void> _askAi() async {
    setState(() {
      _aiBusy = true;
      _aiSpin++;
      _aiError = null;
      _aiDraft = null;
    });
    try {
      final r = await context.read<AuthProvider>().api.post('/ai/polish-ask', {'title': _title.text.trim(), 'description': _desc.text.trim(), if (_category.isNotEmpty) 'category': _category}) as Map;
      // kept: an Indian language (never given to AI) or AI would have translated it; only spacing was tidied
      if (mounted) setState(() => _aiDraft = {'title': '${r['title'] ?? ''}', 'description': '${r['description'] ?? ''}', if (r['kept'] == true) 'kept': '1'});
    } catch (e) {
      if (mounted) setState(() => _aiError = '$e'.isEmpty ? t('AI could not help with this right now. Try again.') : '$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _applyAi() {
    final d = _aiDraft;
    if (d == null) return;
    setState(() {
      _aiUndo = (_title.text, _desc.text);
      _undoTpl = null;
      if ((d['title'] ?? '').isNotEmpty) _title.text = d['title']!;
      if ((d['description'] ?? '').isNotEmpty) _desc.text = d['description']!;
      _aiDraft = null;
    });
  }

  /// the ask as members will see it, rebuilt from the form
  Post _draftPost() {
    final me = context.read<AuthProvider>().profile;
    return Post(
      id: 'preview', kind: 'requirement', authorUid: me?.uid ?? '', authorName: me?.name ?? '', authorCompany: me?.company ?? '', authorHandle: me?.handle ?? '',
      title: _title.text.trim(), description: _desc.text, category: _category.isEmpty ? 'other' : _category,
      askType: _askType.isEmpty ? null : _askType, pollOptions: _askType == 'poll' ? _pollOpts.where((o) => o.trim().isNotEmpty).toList() : const [],
      categoryLabel: _other.text.trim().isEmpty ? null : _other.text.trim(), cardColor: _color,
      locationPref: _location.isEmpty ? null : _location, budget: _budget.isEmpty ? null : _budget, urgency: _urgency.isEmpty ? null : _urgency,
      radiusM: _geo?.radiusM, createdAt: DateTime.now(),
    );
  }

  /// a tap on a card of the preview goes to the part of the form that makes it
  void _editCard(DeckKind k) {
    switch (k) {
      case DeckKind.headline:
        _titleFocus.requestFocus();
      case DeckKind.details:
        _descFocus.requestFocus();
      case DeckKind.photos:
        _addPhotos();
      case DeckKind.glance:
        setState(() => _open = 'where');
      case DeckKind.act:
      case DeckKind.poll:
        break;
    }
  }

  Future<void> _publish() async {
    final title = _title.text.trim(), desc = _desc.text.trim();
    setState(() => _error = null);
    if (_blank.hasMatch(title) || _blank.hasMatch(desc)) return setState(() => _error = t('Replace the [brackets] with your details'));
    if (_category.isEmpty) return setState(() => _open = 'type');
    setState(() => _busy = true);
    try {
      final images = <String>[];
      for (final ph in _photos) {
        images.add(await ph.job);
      }
      if (!mounted) return;
      if (_editing) {
        await context.read<AuthProvider>().api.patch('/posts/${widget.edit!.id}', {
          'title': title,
          'description': desc,
          'category': _category,
          'askType': _askType,
          if (_askType == 'poll') 'pollOptions': _pollOpts.map((o) => o.trim()).where((o) => o.isNotEmpty).toList(),
          'categoryLabel': _category == 'other' ? _other.text.trim() : '',
          'locationPref': _location,
          'budget': _budget,
          'urgency': _urgency,
          'cardColor': _color,
          if (_geo != null) ...{'radiusM': _geo!.radiusM, if (_geoMoved) ...{'lat': _geo!.lat, 'lng': _geo!.lng}},
          'images': images,
        });
        if (mounted) Navigator.pop(context, true);
        return;
      }
      final r = await context.read<AuthProvider>().api.post('/posts', {
        'title': title,
        'description': desc,
        'category': _category,
        if (_askType.isNotEmpty) 'askType': _askType,
        if (_askType == 'poll') 'pollOptions': _pollOpts.map((o) => o.trim()).where((o) => o.isNotEmpty).toList(),
        if (_category == 'other' && _other.text.trim().isNotEmpty) 'categoryLabel': _other.text.trim(),
        if (_location.isNotEmpty) 'locationPref': _location,
        if (_budget.isNotEmpty) 'budget': _budget,
        if (_urgency.isNotEmpty) 'urgency': _urgency,
        'cardColor': _color,
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
        _color = randomCardColor();
        _savedDraft = null;
        _undoTpl = null;
        _aiUndo = null;
        _category = '';
        _askType = '';
        _pollOpts = ['', ''];
        _typeChosen = false;
        _open = null;
      });
      widget.onPosted();
      Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: '${r['id']}')));
    } catch (_) {
      if (mounted) setState(() => _error = t(_editing ? 'Could not save your changes. Please try again.' : 'Could not publish your post. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _aiCatTimer?.cancel();
    for (final c in [_title, _desc, _other]) {
      c.dispose();
    }
    _titleFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  /// An example as a card: category icon and the AI pill, its name, then the sample title with its [blanks] marked.
  Widget _exampleCard(Pal p, (String, String, String, String) s) {
    final sample = t(s.$3);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _blank.allMatches(sample)) {
      if (m.start > at) spans.add(TextSpan(text: sample.substring(at, m.start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(4)),
          child: Text(m.group(0)!.substring(1, m.group(0)!.length - 1), style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: p.text)),
        ),
      ));
      at = m.end;
    }
    if (at < sample.length) spans.add(TextSpan(text: sample.substring(at)));
    return GestureDetector(
      onTap: () => _applyTemplate(s.$1, s.$3, s.$4),
      child: Container(
        width: 176,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border.withValues(alpha: .7))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kGold.withValues(alpha: .18), shape: BoxShape.circle),
              child: WIcon(categoryIcon(s.$1), size: 16, color: p.tagText, still: true),
            ),
            const Spacer(),
            const AiPill(font: 8),
          ]),
          const SizedBox(height: 8),
          Text(t(s.$2), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text.rich(TextSpan(children: spans), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: p.muted)),
        ]),
      ),
    );
  }

  /// Ask AI's suggestion for the title and details, shown before anything changes.
  Widget? _aiCard(Pal p) {
    final d = _aiDraft;
    if (d == null) return null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kGold.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: kGold)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const AiPill(font: 9),
          const SizedBox(width: 6),
          Text(t(d['kept'] != null ? 'Tidied' : 'AI suggestion').replaceAll('AI', '').trim().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.tagText)),
        ]),
        if (d['kept'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(t('Your words are kept as you wrote them, in your language. Only spacing was tidied.'), style: TextStyle(fontSize: 12, color: p.muted)),
          ),
        if ((d['title'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(d['title']!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        if ((d['description'] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d['description']!, style: TextStyle(fontSize: 14, height: 1.5, color: p.text.withValues(alpha: .8)))),
        const SizedBox(height: 10),
        Row(children: [
          GestureDetector(
            onTap: _applyAi,
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
      hintStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w500),
      counterText: '',
      filled: true,
      fillColor: p.card,
      errorText: error,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    final me = context.watch<AuthProvider>().profile;
    final title = _title.text, desc = _desc.text;
    final tip = _tips[_category];
    final empty = title.trim().isEmpty && desc.trim().isEmpty;
    // examples: the chosen type's, or one of each common type while none is known
    final examples = _category.isNotEmpty && _samples[_category] != null
        ? [for (final s in _samples[_category]!) (_category, s.$1, s.$2, s.$3)]
        : [for (final c in _starterCategories) if (_samples[c] != null) (c, kCategoryShort[c] ?? c, _samples[c]!.first.$2, _samples[c]!.first.$3)];
    String? titleIdea;
    if (title.trim().isEmpty && desc.trim().length >= 20) {
      final first = desc.trim().split(RegExp(r'[.\n!?]')).first.trim();
      if (first.length >= 5) titleIdea = first.length > 100 ? first.substring(0, 100) : first;
    }
    final titleOk = title.trim().length >= 5;
    final descOk = desc.trim().length >= 20;
    final pollOk = _askType != 'poll' || _pollOpts.where((o) => o.trim().isNotEmpty).length >= 2;
    final typeOk = _category.isNotEmpty && (_category != 'other' || _other.text.trim().length >= 2) && pollOk;
    final titleBlank = _blank.hasMatch(title), descBlank = _blank.hasMatch(desc);
    final ready = titleOk && descOk && typeOk && !titleBlank && !descBlank && !_photos.any((ph) => ph.failed);
    final missing = !titleOk
        ? 'Add a title'
        : !descOk
            ? 'Add a little more detail'
            : titleBlank || descBlank
                ? 'Replace the [brackets] with your details'
                : _category.isEmpty
                    ? 'Choose a type'
                    : !pollOk
                        ? 'Add at least 2 options to vote on'
                        : !typeOk
                        ? 'Say what this ask is about'
                        : '';
    final score = [titleOk, desc.trim().length >= 60, _location.isNotEmpty, _urgency.isNotEmpty, _budget.isNotEmpty, _photos.isNotEmpty].where((x) => x).length;
    final strength = score >= 5 ? 'Strong ask' : (score >= 3 ? 'Good ask' : 'Basic ask');
    // Ask AI needs a few words of title to work from
    final canAskAi = title.trim().length >= 3;
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
    Widget pill(String label, bool on, VoidCallback onTap, {double h = 36, double font = 14}) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: h,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? p.ink : p.chip, borderRadius: BorderRadius.circular(h)),
            child: Text(label, style: TextStyle(fontSize: font, fontWeight: FontWeight.w700, color: on ? p.onInk : p.muted)),
          ),
        );
    // an essential of the ask as a chip, as on Connect, that opens its choices; unset ones are dashed
    Widget chip(String key, WI icon, String label, bool set, {bool auto = false}) {
      final open = _open == key;
      final inner = Row(mainAxisSize: MainAxisSize.min, children: [
        WIcon(icon, size: 14, color: p.muted, still: true),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: set || open ? p.text.withValues(alpha: .8) : p.muted))),
        if (auto) ...[const SizedBox(width: 4), const AiPill(font: 8)],
        const SizedBox(width: 2),
        AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 150), child: WIcon(WI.chevronDown, size: 14, color: p.muted)),
      ]);
      void tap() => setState(() => _open = open ? null : key);
      if (!set && !open) return DashedBox(radius: 20, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), onTap: tap, child: inner);
      return GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(20), border: Border.all(color: open ? p.text.withValues(alpha: .4) : Colors.transparent)),
          child: inner,
        ),
      );
    }

    final typePills = KeyedSubtree(
      key: _tk('ask-category'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in kAskTypes)
              GestureDetector(
                onTap: () => setState(() {
                  _askType = o.value;
                  _category = categoryForType(o.value, _category);
                  if (o.value == 'poll' && _pollOpts.where((x) => x.trim().isNotEmpty).length < 2) _pollOpts = ['', ''];
                  _typeChosen = true;
                }),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _askType == o.value ? p.ink : p.canvas,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _askType == o.value ? Colors.transparent : p.border.withValues(alpha: .7)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    WIcon(categoryIcon(o.icon), size: 14, color: _askType == o.value ? p.onInk : p.muted, still: true),
                    const SizedBox(width: 4),
                    Text(t(o.short), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _askType == o.value ? p.onInk : p.muted)),
                  ]),
                ),
              ),
          ]),
          if (askTypeDef(_askType) != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t(askTypeDef(_askType)!.label)}: ${t(askTypeDef(_askType)!.hint)}${_category.isNotEmpty && !_typeChosen ? ' · ${t('Picked from your words. Tap to change.')}' : ''}', style: TextStyle(fontSize: 12, color: p.muted))),
        ]),
    );

    Widget? panel;
    switch (_open) {
      case 'where':
        panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: CityPill(value: _location, placeholder: 'Choose a city', height: 38, rounded: true, near: _geo == null ? null : (lat: _geo!.lat, lng: _geo!.lng), onChanged: _pickNode)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _locating ? null : _useMyLocation,
              child: Opacity(
                opacity: _locating ? .6 : 1,
                child: DashedBox(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
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
            Text(t('Members inside the circle see this ask.'), style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ]);
      case 'when':
        panel = Wrap(spacing: 6, runSpacing: 6, children: [for (final o in kUrgencies) pill(t(o.label), _urgency == o.value, () => setState(() {
                    _urgency = _urgency == o.value ? '' : o.value;
                    _open = null;
                  }))]);
      case 'budget':
        panel = _BudgetRange(
          key: ValueKey(_budgetKey),
          value: _budget,
          presets: tip?.$2 ?? const [],
          onChanged: (v) {
            setState(() => _budget = v);
            _saveDraft();
          },
        );
    }

    final shownName = me == null ? '' : (me.isEntrepreneur && me.company.isNotEmpty ? me.company : me.name);
    final form = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        // an unfinished ask from last time, until the member starts a new one
        if (_savedDraft != null && empty && !_editing) ...[
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
          const SizedBox(height: 12),
        ],
        // the ask laid out like its row on Connect: photo, name and time, then the title, details and chips as fields
        KeyedSubtree(
          key: _tk('ask-card'),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (me != null) ...[
                  // back (the island steps aside on Ask) and the photo share the name line, so the fields get the full width
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.onBack != null)
                      Semantics(
                        button: true,
                        label: t('Back'),
                        child: InkResponse(
                          onTap: widget.onBack,
                          radius: 18,
                          child: Transform.translate(
                            offset: const Offset(-8, 0),
                            child: SizedBox(width: 28, height: 38, child: Center(child: WIcon(WI.back, size: 22, color: p.text))),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Avatar(name: shownName, photoUrl: me.photoUrl, size: 38, type: me.userType, badge: 16, uid: me.uid),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                          if (me.verification > 0 || me.premium || me.plan != null) ...[const SizedBox(width: 4), VerifiedBadge(level: me.verification, premium: me.premium, plan: me.plan)],
                          const SizedBox(width: 6),
                          Text(t('just now'), style: TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                        Text(me.isEntrepreneur ? me.name : me.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
                      ]),
                    ),
                    // Ask AI, top right: on once the title has a few words
                    if (_aiOn)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Semantics(
                          button: true,
                          enabled: canAskAi && !_aiBusy,
                          child: GestureDetector(
                            onTap: canAskAi && !_aiBusy ? _askAi : () => toast(context, t('Write a title first')),
                            // "Ask" + the logo's AI pill, on a quiet gold-edged pill
                            child: Opacity(
                              opacity: canAskAi ? 1 : .5,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
                                decoration: BoxDecoration(
                                  color: p.card,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFC9AE24).withValues(alpha: .5)),
                                ),
                                child: _aiBusy
                                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                                        Text(t('Thinking…'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text)),
                                        const SizedBox(width: 5),
                                        AiPill(font: 10, spin: _aiSpin),
                                      ])
                                    : withAiPill(t('Ask AI'), TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.text), font: 10, spin: _aiSpin),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
                typePills,
                if (_askType == 'poll') ...[
                  const SizedBox(height: 10),
                  Text(t('Options to vote on'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                  for (var i = 0; i < _pollOpts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle), child: Text('ABCD'[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.muted))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('opt$i-${_pollOpts.length}'),
                            initialValue: _pollOpts[i],
                            maxLength: 60,
                            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                            onChanged: (v) => setState(() => _pollOpts[i] = v),
                            decoration: _input(p, t('Option {n}', {'n': '${i + 1}'})),
                          ),
                        ),
                        if (_pollOpts.length > 2) IconButton(onPressed: () => setState(() => _pollOpts.removeAt(i)), icon: WIcon(WI.close, size: 16, color: p.muted)),
                      ]),
                    ),
                  if (_pollOpts.length < 4)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GestureDetector(onTap: () => setState(() => _pollOpts.add('')), child: Text('+ ${t('Add an option')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link))),
                    ),
                ],
                if (_category == 'other') ...[
                  const SizedBox(height: 8),
                  TextField(controller: _other, maxLength: 40, onChanged: (_) => setState(() {}), decoration: _input(p, t('What is this about? e.g. Event stall, Legal help, Insurance'))),
                ],
                const SizedBox(height: 8),
                TextField(
                  key: _tk('ask-title'),
                  controller: _title,
                  focusNode: _titleFocus,
                  maxLength: 100,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _descFocus.requestFocus(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
                  decoration: _input(p, t('Title: e.g. Need 5 CNC operators in Turbhe')),
                ),
                MentionSuggest(controller: _title, focus: _titleFocus),
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
                const SizedBox(height: 8),
                TextField(
                  key: _tk('ask-description'),
                  controller: _desc,
                  focusNode: _descFocus,
                  minLines: 3,
                  maxLines: 12,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                  decoration: _input(p, t(tip?.$1 ?? 'Describe what you need: quantity, quality, area, timing')),
                ),
                MentionSuggest(controller: _desc, focus: _descFocus),
                // hashtags in the title or description become links to every ask that carries them
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(t('Add #tags like #plumber or #Vashi, or @ a member, so the right people find it.'), style: TextStyle(fontSize: 12, color: p.muted))),
                    if (title.length > 80 || desc.length > 240)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(desc.length > 240 ? '${desc.length}/300' : '${title.length}/100', style: TextStyle(fontSize: 12, color: p.muted)),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final ph in _photos)
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(fit: StackFit.expand, children: [
                          Opacity(
                            opacity: ph.url == null && !ph.failed ? .6 : 1,
                            child: ph.file == null
                                ? Image.network(ph.url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: p.chip))
                                : FutureBuilder(future: ph.file!.readAsBytes(), builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : ColoredBox(color: p.chip)),
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
                    DashedBox(
                      radius: 8,
                      padding: EdgeInsets.zero,
                      onTap: _addPhotos,
                      child: SizedBox(
                        height: _photos.isEmpty ? 40 : 72,
                        width: _photos.isEmpty ? null : 72,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                            WIcon(WI.imageAdd, size: 20, color: p.muted),
                            const SizedBox(width: 8),
                            Text(_photos.isEmpty ? t('Add photos') : '${_photos.length}/$_maxAskImages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
                          ]),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                // the essentials as chips, as on Connect; each opens its choices
                // the card's colour, as members will see it on Connect
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Text(t('Card colour'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted)),
                    const SizedBox(width: 10),
                    for (final e in kCardColors.entries)
                      Semantics(
                        button: true,
                        selected: _color == e.key,
                        label: e.key,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _color = e.key),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: e.value,
                                shape: BoxShape.circle,
                                border: Border.all(color: _color == e.key ? p.text : Colors.transparent, width: 2),
                              ),
                              child: _color == e.key ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: _tk('ask-details'),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    // where and how far, one chip: "Vashi · 25 km"
                    chip('where', WI.pin, '${_location.isEmpty ? t('Where') : t(_location)}${_geo != null ? ' · ${_radiusLabel(_geo!.radiusM)}' : ''}', _location.isNotEmpty || _geo != null),
                    chip('budget', WI.rupee, _budget.isEmpty ? t('Budget') : _budget, _budget.isNotEmpty),
                    chip('when', WI.clock, _urgency.isEmpty ? t('When') : t(labelOf(kUrgencies, _urgency)), _urgency.isNotEmpty),
                  ]),
                ),
                if (panel != null && _open != 'type')
                  GestureDetector(
                    // taps inside the choices never close them (a tap elsewhere on the page does)
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      panel,
                      if (_open == 'where' || _open == 'budget') ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(onTap: () => setState(() => _open = null), child: Text(t('Done'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.link))),
                        ),
                      ],
                    ]),
                  ),
                  ),
              ]),
            ),
          ]),
        ),
        _aiCard(p) ?? const SizedBox.shrink(),
        // live preview: the deck of cards members swipe on Connect; tap one to edit that part
        const SizedBox(height: 14),
        Container(
          key: _tk('ask-preview'),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          decoration: BoxDecoration(color: p.chip.withValues(alpha: .4), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('👀 ${t('How members will see your ask')}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(t('Swipe the cards. Tap one to edit it.'), style: TextStyle(fontSize: 11, color: p.muted)),
            const SizedBox(height: 8),
            AskDeck(
              preview: true,
              post: _draftPost(),
              images: [
                for (final ph in _photos.where((x) => !x.failed))
                  if (ph.file != null) FileImage(File(ph.file!.path)) as ImageProvider else NetworkImage(ph.url!),
              ],
              reachLabel: _geo == null ? null : _radiusLabel(_geo!.radiusM),
              onCardTap: _editCard,
            ),
          ]),
        ),
        if (_aiError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_aiError!, style: TextStyle(fontSize: 12, color: p.danger))),
        if ((_aiUndo != null && !_aiBusy) || _undoTpl != null || (!empty && !_editing)) ...[
          const SizedBox(height: 12),
          Row(children: [
            if ((_aiUndo != null && !_aiBusy) || _undoTpl != null) ...[
              GestureDetector(
                onTap: () => setState(() {
                  if (_aiUndo != null) {
                    _title.text = _aiUndo!.$1;
                    _desc.text = _aiUndo!.$2;
                    _aiUndo = null;
                  } else if (_undoTpl != null) {
                    _typeChosen = _undoTpl!.$4;
                    _category = _undoTpl!.$3;
                    _title.text = _undoTpl!.$1;
                    _desc.text = _undoTpl!.$2;
                    _undoTpl = null;
                  }
                }),
                child: Text(t('Undo'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted, decoration: TextDecoration.underline)),
              ),
            ],
            const Spacer(),
            if (!empty && !_editing)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _undoTpl = null;
                    _aiDraft = null;
                    if (!_typeChosen) _category = '';
                  });
                  _title.clear();
                  _desc.clear();
                  _titleFocus.requestFocus();
                },
                child: Row(children: [WIcon(WI.close, size: 14, color: p.muted), const SizedBox(width: 4), Text(t('Clear'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted))]),
              ),
          ]),
        ],
        // examples: a starting point while the ask is empty, never filled in on their own
        if (empty && !_editing) ...[
          const SizedBox(height: 16),
          _caps(p, 'Or start from an example'),
          const SizedBox(height: 2),
          Text(t('Tap one, then change the details to yours.'), style: TextStyle(fontSize: 12, color: p.muted)),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: _tk('ask-templates'),
            // edge to edge, swiped sideways
            child: hScroll(height: 124, [for (final e in examples) _exampleCard(p, e)]),
          ),
        ],
        const SizedBox(height: 12),
        Text(t('Write in your own language: हिंदी, मराठी, ગુજરાતી, English or any other. It is posted as you write it.'), style: TextStyle(fontSize: 12, color: p.muted)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 14, color: p.danger))),
      ],
    );

    return Column(children: [
      // a tap anywhere outside an open chip's choices closes them
      Expanded(child: _open == null ? form : GestureDetector(onTap: () => setState(() => _open = null), child: form)),
      // Publish in one bar on the bottom edge (the island steps aside on Ask): reach and strength, then the button
      Container(
        key: _tk('ask-publish'),
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
        decoration: BoxDecoration(color: p.canvas.withValues(alpha: .97), border: Border(top: BorderSide(color: p.border.withValues(alpha: .7)))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                WIcon(WI.users, size: 14, color: p.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _reach != null ? '${t('Reaches')} $_reach ${t(_reach == 1 ? 'member' : 'members')}${_location.isNotEmpty ? ' ${t('in')} ${t(_location)}' : ''}' : t('Reaches nearby members'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.muted),
                  ),
                ),
              ]),
              if (ready || title.trim().isNotEmpty || desc.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(t(ready ? strength : missing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ready ? const Color(0xFF059669) : p.muted)),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          GoldButton(label: t(_editing ? 'Save' : 'Publish'), wi: WI.askPlus, height: 44, loading: _busy, onPressed: ready ? _publish : null),
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
