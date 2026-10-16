/// Base URL of the WebWeb API.
/// Local development (phone over USB): `adb reverse tcp:4000 tcp:4000`, then the default below works.
/// Production build:  flutter build appbundle --dart-define=API_URL=https://biznetapi.webweb.ai
const _override = String.fromEnvironment('API_URL');

String get apiUrl => (_override.isNotEmpty ? _override : 'http://localhost:4000').replaceFirst(RegExp(r'/$'), '');

/// WebSocket endpoint of the same API (chat events, presence, call signalling).
String get wsUrl => '${apiUrl.replaceFirst(RegExp(r'^http'), 'ws')}/app/ws';

/// The website (public pages, share links, and static images such as /demo/... that live on the site).
const _site = String.fromEnvironment('SITE_URL');
String get siteUrl => (_site.isNotEmpty ? _site : 'https://webweb.ai').replaceFirst(RegExp(r'/$'), '');
