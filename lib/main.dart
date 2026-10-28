import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'call_manager.dart';
import 'crash_reporter.dart';
import 'device.dart';
import 'i18n.dart';
import 'notifications.dart';
import 'outbox.dart';
import 'realtime.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'theme.dart';
import 'update_check.dart';
import 'widgets.dart';
import 'widgets/splash_screen.dart';

final navKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // this install's id (sent with push tokens and the live connection), and sign-outs that were offline
  Device.load().then((_) => Device.flushSignOuts());
  if (NotificationService.supported) FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  final auth = AuthProvider();
  CrashReporter.init(auth.api); // errors from here on are reported (Admin > Crashes)
  final realtime = RealtimeService();
  final calls = CallManager(realtime, navKey, auth.api);
  final notifications = NotificationService(auth, realtime, navKey);
  final i18n = I18n()..init();
  auth.beforeLogout = notifications.unregister;
  auth.init();
  notifications.init();
  Outbox.start(auth.api, realtime); // messages written offline go out once the network is back
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: i18n),
      ChangeNotifierProvider(create: (_) => ThemeController()..init()),
      ChangeNotifierProvider.value(value: realtime),
      ChangeNotifierProvider.value(value: calls),
      Provider.value(value: notifications),
    ],
    child: const App(),
  ));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebWeb Ai',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      themeMode: context.watch<ThemeController>().mode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // update prompts (Admin > App updates) sit over every screen, the login too
      builder: (context, child) => UpdateGate(child: _KeyboardDismissOnScroll(child: child ?? const SizedBox())),
      // a language switch rebuilds every screen with the new strings (web: t() re-renders on change)
      home: KeyedSubtree(key: ValueKey(context.watch<I18n>().lang), child: const Gate()),
    );
  }
}

/// Dragging any list downwards while the keyboard is up puts the keyboard away (WhatsApp-style), on every
/// screen. Scrolling inside the text field that has the keyboard does not count.
class _KeyboardDismissOnScroll extends StatelessWidget {
  final Widget child;
  const _KeyboardDismissOnScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final drag = n is ScrollUpdateNotification ? n.dragDetails : (n is OverscrollNotification ? n.dragDetails : null);
        if (drag == null || drag.delta.dy < 3 || n.metrics.axis != Axis.vertical) return false;
        if (MediaQuery.viewInsetsOf(context).bottom <= 0) return false;
        final focus = FocusManager.instance.primaryFocus;
        final field = focus?.context;
        if (focus == null || field == null) return false;
        var inside = false;
        n.context?.visitAncestorElements((e) {
          inside = e == field;
          return !inside;
        });
        if (!inside) focus.unfocus();
        return false;
      },
      child: child,
    );
  }
}

/// Logged out -> login / OTP. Logged in without a profile -> onboarding. Otherwise the 5-tab app.
/// the opening screen stays at least this long once per launch, so it is seen rather than flashed
bool _splashSeen = false;

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  @override
  void initState() {
    super.initState();
    if (!_splashSeen) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        _splashSeen = true;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final rt = context.read<RealtimeService>();
    // Live connection exists only while a logged-in user has a profile.
    final live = auth.isLoggedIn && auth.profile != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (live) {
        rt.connect(auth.token!);
        context.read<NotificationService>().register();
      } else {
        rt.disconnect();
      }
    });
    if (!auth.ready || !_splashSeen) return const SplashScreen();
    if (!auth.isLoggedIn) return const LoginScreen();
    if (!auth.profileLoaded) return const _ProfileLoading();
    if (auth.profile == null) return const OnboardingFlow();
    return const Shell();
  }
}

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: auth.error == null
            ? const LogoLoader()
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(auth.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  GoldButton(
                      label: t('Try again'),
                      onPressed: () {
                        auth.error = null;
                        auth.loadProfile();
                      }),
                  TextButton(onPressed: auth.logout, child: Text(t('Log out'))),
                ]),
              ),
      ),
    );
  }
}
