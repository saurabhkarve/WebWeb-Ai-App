import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../theme.dart';
import '../widgets.dart';

/// Web "Enter OTP" step: 6 digits, 59s countdown, Resend enabled after it ends.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _seconds = 59;
  final _ctrl = TextEditingController();
  Timer? _timer;
  int _left = _seconds;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      if (mounted) setState(() => _left--);
    });
  }

  Future<void> _verify() async {
    if (_ctrl.text.length != 6) return toast(context, 'Enter the 6 digit OTP', error: true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(_ctrl.text);
    if (!ok && mounted) {
      toast(context, auth.error ?? 'Error', error: true);
      _ctrl.clear();
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendOtp(auth.phone);
    if (!mounted) return;
    toast(context, ok ? 'OTP Sent' : 'Something Went Wrong', error: !ok);
    if (ok) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = Pal.of(context);
    final mm = (_left ~/ 60).toString().padLeft(2, '0');
    final ss = (_left % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.chevron_left, size: 30), onPressed: auth.backToLogin)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Enter OTP', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('We sent a verification code to +91 ${auth.phone}', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 30),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w800),
                  onSubmitted: (_) => _verify(),
                  decoration: InputDecoration(
                    hintText: '••••••',
                    counterText: '',
                    filled: true,
                    fillColor: p.field,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kGold)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('$mm:$ss', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
                TextButton(onPressed: _left > 0 ? null : _resend, child: const Text('Resend OTP')),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: GoldButton(label: 'Verify', loading: auth.loading, onPressed: _verify)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
