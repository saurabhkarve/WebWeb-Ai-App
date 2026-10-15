import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_provider.dart';
import 'call_manager.dart';
import 'notifications.dart';
import 'realtime.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding.dart';
import 'screens/otp_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';
import 'widgets.dart';

final navKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (NotificationService.supported) FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  final auth = AuthProvider();
  final realtime = RealtimeService();
  final calls = CallManager(realtime, navKey);
  final notifications = NotificationService(auth, realtime, navKey);
  auth.beforeLogout = notifications.unregister;
  auth.init();
  notifications.init();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
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
      home: const Gate(),
    );
  }
}

/// Logged out -> login / OTP. Logged in without a profile -> onboarding. Otherwise the 5-tab app.
class Gate extends StatelessWidget {
  const Gate({super.key});

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
    if (!auth.ready) return const _Splash();
    if (!auth.isLoggedIn) return auth.otpSent ? const OtpScreen() : const LoginScreen();
    if (!auth.profileLoaded) return const _ProfileLoading();
    if (auth.profile == null) return const OnboardingFlow();
    return const Shell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(body: PageLoader(size: 84));
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
                  GoldButton(label: 'Retry', onPressed: () {
                    auth.error = null;
                    auth.loadProfile();
                  }),
                  TextButton(onPressed: auth.logout, child: const Text('Log out')),
                ]),
              ),
      ),
    );
  }
}
