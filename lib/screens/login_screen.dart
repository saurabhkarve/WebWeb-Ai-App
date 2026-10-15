import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Phone login, same as the web: 10-digit Indian mobile number -> OTP.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ctrl = TextEditingController();
  String? _err;

  Future<void> _submit() async {
    final t = _ctrl.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(t)) {
      setState(() => _err = 'Enter a valid 10-digit mobile number');
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendOtp(t);
    if (!mounted) return;
    toast(context, ok ? 'OTP sent' : (auth.error ?? 'Could not send OTP'), error: !ok);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().loading;
    final p = Pal.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const LogoStack(size: 84),
                const SizedBox(height: 14),
                Text('Your free business page and network.\nPost requirements, share contacts, grow.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 32),
                AppField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboard: TextInputType.phone,
                  hint: 'Mobile number',
                  prefixText: '+91  ',
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  errorText: _err,
                  onChanged: (_) => setState(() => _err = null),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 22),
                SizedBox(width: double.infinity, child: GoldButton(label: 'Send OTP', loading: loading, onPressed: _submit)),
                const SizedBox(height: 18),
                Text("New here? Just enter your number. We'll set up your free page in under a minute.", textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
