import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/clay.dart';
import '../widgets/icons.dart';
import '../widgets/login_video.dart';
import '../widgets/turnstile.dart';

class LoginScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> user) onDone;
  const LoginScreen({super.key, required this.onDone});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _pw = TextEditingController(), _server = TextEditingController(text: Api.i.base);
  final _pwFocus = FocusNode();
  final _cap = GlobalKey<TurnstileState>();
  String? _token;
  bool _show = false, _busy = false, _serverOpen = false;
  String _err = '';

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _server.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    if (_email.text.isEmpty || _pw.text.isEmpty) return setState(() => _err = 'Enter your email and password.');
    if (_token == null) return setState(() => _err = 'Complete the security check first.');
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      if (_serverOpen && Api.clean(_server.text) != Api.i.base) await Api.i.setBase(_server.text);
      final user = await Api.i.login(_email.text, _pw.text, _token!);
      widget.onDone(user);
    } on ApiError catch (e) {
      _cap.currentState?.reset();
      final code = e.data['code'];
      setState(() {
        _err = code == 'captcha'
            ? 'The security check failed. Please try it again.'
            : code == 'captcha_unavailable'
                ? 'The security check is unavailable right now. Try again in a moment.'
                : e.status == 429
                    ? 'Too many attempts. Try again in ${(((e.data['retry_in'] as num?) ?? 900) / 60).ceil()} min.'
                    : e.status == 401
                        ? 'Email or password is wrong.'
                        : e.message;
        _busy = false;
      });
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: ts(16, C.faint),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: a(C.shadow, 0.22), width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.matchaFlat, width: 1.5)),
      );

  Widget _field(String label, Widget input) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: 2, bottom: 6), child: T(label, s: 12.5, f: 'bold', c: C.mute)),
          input,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final form = Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: EdgeInsets.all(mq.size.width < 380 ? 20 : 26),
      decoration: BoxDecoration(
        color: const Color(0xF0FAFCF4),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: a(Colors.white, 0.7)),
        boxShadow: [BoxShadow(color: a(Colors.black, 0.25), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Sprout(size: 30),
          const SizedBox(width: 8),
          T('AgriSense', s: 22, f: 'black', c: C.matchaInk, ls: -0.4),
        ]),
        const SizedBox(height: 22),
        T('Welcome back', s: 24, f: 'black', c: C.matchaInk, ls: -0.5),
        const Padding(padding: EdgeInsets.only(top: 4, bottom: 22), child: T('Sign in to see how the garden is doing.', s: 14.5, c: C.mute, f: 'reg')),
        _field(
          'Email',
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _pwFocus.requestFocus(),
            style: ts(16, C.ink),
            decoration: _dec('you@example.com'),
          ),
        ),
        _field(
          'Password',
          TextField(
            controller: _pw,
            focusNode: _pwFocus,
            obscureText: !_show,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _go(),
            style: ts(16, C.ink),
            decoration: _dec('Your password',
                suffix: IconButton(
                  onPressed: () => setState(() => _show = !_show),
                  icon: AIcon(_show ? 'eyeoff' : 'eye', size: 20, color: C.mute),
                )),
          ),
        ),
        Turnstile(key: _cap, siteKey: Cfg.turnstileSiteKey, baseUrl: Cfg.turnstileBaseUrl, onToken: (t) {
          if (mounted) setState(() => _token = t);
        }),
        if (_err.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: a(C.bad, 0.09), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const AIcon('alert', size: 17, color: C.bad),
              const SizedBox(width: 8),
              Expanded(child: T(_err, s: 13.5, c: C.bad)),
            ]),
          ),
        GestureDetector(
          onTap: (_busy || _token == null) ? null : _go,
          child: Opacity(
            opacity: _busy ? 0.7 : _token == null ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: C.matcha),
              ),
              child: T(_busy ? 'Signing in…' : _token == null ? "Verifying you're human…" : 'Sign in', s: 16, f: 'bold', c: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _serverOpen = !_serverOpen),
          child: Center(child: T(_serverOpen ? 'Hide server address' : 'Server address', s: 12.5, f: 'bold', c: C.mute)),
        ),
        if (_serverOpen) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: ts(14, C.ink),
            decoration: _dec('https://your-server.onrender.com'),
          ),
        ],
      ]),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF2C3A1E),
      resizeToAvoidBottomInset: true,
      body: Stack(fit: StackFit.expand, children: [
        const LoginVideo(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
              const Color(0x8C18260E),
              const Color(0x5918260E),
              const Color(0xB818260E),
            ]),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, cons) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: cons.maxHeight - 40),
                child: Center(child: form),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
