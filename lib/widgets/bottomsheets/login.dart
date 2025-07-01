import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/widgets/forms/otp_verify_form.dart';

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

  // Variables for OTP verification on sign-up
  String? _signUpEmail;

  // @override
  // void initState() {
  //   super.initState();

  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     _showOtpVerifyDialog();
  //   });
  // }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginOrSignup() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (mounted && response.user != null) {
        Navigator.pop(context);
        return;
      }
      throw AuthException('No user found');
    } on AuthException {
      try {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );

        setState(() {
          _signUpEmail = email;
        });

        _showOtpVerifyDialog();
      } catch (e) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _showOtpVerifyDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('OTP Verification')),
        content: OtpVerifyForm(signUpEmail: _signUpEmail),
      ),
    );
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
