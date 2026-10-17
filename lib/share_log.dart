import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';

/// Opens the phone's share sheet and records the share (POST /app/share) unless it was dismissed.
/// entity: post | update | profile | item; ref: its id (a profile's handle).
Future<void> shareAndLog(Api api, {required String entity, required String ref, required String text, String? subject}) async {
  final r = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  if (r.status == ShareResultStatus.dismissed) return;
  logShare(api, entity, ref);
}

/// Records a share without waiting; a failure never affects the share itself.
void logShare(Api api, String entity, String ref, {String channel = 'native'}) {
  if (ref.isEmpty) return;
  api.post('/app/share', {
    'entity': entity,
    'ref': ref,
    'channel': channel,
    'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
  }).catchError((_) => null);
}
