import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'realtime.dart';

/// A chat message waiting to be sent.
class OutboxItem {
  final String tmp; // the phone's id for the message, also sent as clientId (no double sends)
  final String chatId;
  final String text;
  final String? imageUrl;
  final Map<String, dynamic>? attachment;
  final int? replyToId;
  /// what the reply quote shows while it waits (MsgQuote json)
  final Map<String, dynamic>? replyQuote;
  final DateTime createdAt;

  OutboxItem({
    required this.tmp,
    required this.chatId,
    required this.text,
    this.imageUrl,
    this.attachment,
    this.replyToId,
    this.replyQuote,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'tmp': tmp,
        'chatId': chatId,
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (attachment != null) 'attachment': attachment,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyQuote != null) 'replyQuote': replyQuote,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static OutboxItem fromJson(Map j) => OutboxItem(
        tmp: '${j['tmp']}',
        chatId: '${j['chatId']}',
        text: '${j['text'] ?? ''}',
        imageUrl: j['imageUrl'] as String?,
        attachment: j['attachment'] == null ? null : Map<String, dynamic>.from(j['attachment'] as Map),
        replyToId: (j['replyToId'] as num?)?.toInt(),
        replyQuote: j['replyQuote'] == null ? null : Map<String, dynamic>.from(j['replyQuote'] as Map),
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()),
      );
}

/// What happened to a queued message: sent (with the stored message) or refused by the server.
class OutboxResult {
  final String tmp, chatId;
  final Map<String, dynamic>? message;
  final String? error;
  OutboxResult(this.tmp, this.chatId, {this.message, this.error});
}

/// WhatsApp-style outbox: a message written without network shows with a clock and is sent by itself, in
/// order, as soon as the phone is back online, even after the app was closed. Kept on the phone until the
/// server has it; the clientId makes a resend after a lost reply return the stored message, not a copy.
class Outbox {
  Outbox._();

  static const _key = 'outbox_v1';
  static List<OutboxItem>? _items;
  static Api? _api;
  static bool _flushing = false;
  static Timer? _timer;
  static final _results = StreamController<OutboxResult>.broadcast();

  static Stream<OutboxResult> get results => _results.stream;

  static Future<List<OutboxItem>> _load() async {
    if (_items != null) return _items!;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      _items = raw == null ? [] : (jsonDecode(raw) as List).map((e) => OutboxItem.fromJson(e as Map)).toList();
    } catch (_) {
      _items = [];
    }
    return _items!;
  }

  static Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(_items!.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Starts sending whenever the socket comes back, and every 15 s while something waits.
  static void start(Api api, RealtimeService rt) {
    _api = api;
    rt.onReconnect.listen((_) => flush());
    flush();
  }

  /// Messages of one chat still waiting (shown with a clock in that chat).
  static Future<List<OutboxItem>> pending(String chatId) async => (await _load()).where((e) => e.chatId == chatId).toList();

  static Future<void> add(OutboxItem item) async {
    (await _load()).add(item);
    await _save();
    flush();
  }

  static Future<void> flush() async {
    final api = _api;
    // not signed in yet (app starting): a request now would be refused and sign the person out
    if (api == null || _flushing || api.token() == null) {
      if (api != null && (_items ?? const []).isNotEmpty) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 3), flush);
      }
      return;
    }
    _flushing = true;
    try {
      final items = await _load();
      while (items.isNotEmpty) {
        final it = items.first;
        try {
          final sent = await api.post('/chats/${it.chatId}/messages', {
            'text': it.text,
            'clientId': it.tmp,
            if (it.imageUrl != null) 'imageUrl': it.imageUrl,
            if (it.attachment != null) 'attachment': it.attachment,
            if (it.replyToId != null) 'replyToId': it.replyToId,
          });
          items.removeAt(0);
          await _save();
          _results.add(OutboxResult(it.tmp, it.chatId, message: Map<String, dynamic>.from(sent as Map)));
        } on ApiException catch (e) {
          if (e.isNetwork || e.status >= 500 || e.status == 429) break; // try again later, in order
          // refused for good (blocked, chat gone, invalid): drop it and say so in the chat
          items.removeAt(0);
          await _save();
          _results.add(OutboxResult(it.tmp, it.chatId, error: e.message));
        }
      }
    } finally {
      _flushing = false;
      _timer?.cancel();
      if ((_items ?? const []).isNotEmpty) _timer = Timer(const Duration(seconds: 15), flush);
    }
  }

  /// Sign-out: queued messages of the old account are dropped.
  static Future<void> clear() async {
    _items = [];
    _timer?.cancel();
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
