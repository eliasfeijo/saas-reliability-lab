import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginBottomSheet extends StatefulWidget {
  const LoginBottomSheet({super.key});

  @override
  State<LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends State<LoginBottomSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  // void _setAutofillAttributes() {
  //   if (!kIsWeb) return;

  //   final inputs = web.document.querySelectorAll('input');

  //   for (final input in inputs) {
  //     final el = input as web.HTMLInputElement;

  //     if (el.labels?.isEmpty ?? true) continue;

  //     final label = el.labels?.first.textContent?.toLowerCase() ?? '';

  //     if (label.contains('email')) {
  //       el.name = 'username';
  //       el.autocomplete = 'email';
  //     } else if (label.contains('password')) {
  //       el.name = 'current-password';
  //       el.autocomplete = 'current-password';
  //     }
  //   }
  // }

  Future<void> _loginOrSignup() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (mounted && response.user != null) {
        Navigator.pop(context); // close bottom sheet
        return;
      }

      throw AuthException('No user found');
    } on AuthException {
      try {
        const emailRedirectUrl = String.fromEnvironment(
          'EMAIL_REDIRECT_URL',
          defaultValue: 'https://eliasfeijo.github.io/flutter-agenda-pwa/',
        );
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          emailRedirectTo: emailRedirectUrl,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Check your email.')),
        );
      } catch (e) {
        setState(() => _error = e.toString());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Login or Sign Up'),
            TextField(
              controller: _emailController,
              autofocus: true,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _loginOrSignup,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
