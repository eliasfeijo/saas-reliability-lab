import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/widgets/forms/otp_verify_form.dart';

enum _AuthAction { login, signUp }

class LoginBottomSheet extends StatefulWidget {
  const LoginBottomSheet({super.key});

  @override
  State<LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends State<LoginBottomSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  _AuthAction? _activeAction;
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

  String _formatAuthError(Object error) {
    if (error is AuthException) {
      return error.message;
    }

    final message = error.toString();
    const prefix = 'Exception: ';
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }

    return message;
  }

  Future<bool> _validateCredentials() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Email and password are required.';
      });
      return false;
    }

    return true;
  }

  Future<void> _login() async {
    if (!await _validateCredentials()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _loading = true;
      _activeAction = _AuthAction.login;
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _activeAction = null;
        _error = _formatAuthError(error);
      });
    }
  }

  Future<void> _signUp() async {
    if (!await _validateCredentials()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _loading = true;
      _activeAction = _AuthAction.signUp;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      if (!mounted) return;
      setState(() {
        _signUpEmail = email;
        _loading = false;
        _activeAction = null;
        _error = null;
      });

      await _showOtpVerifyDialog();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _activeAction = null;
        _error = _formatAuthError(error);
      });
    }
  }

  Future<void> _showOtpVerifyDialog() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Center(child: Text('OTP Verification')),
        content: OtpVerifyForm(
          signUpEmail: _signUpEmail,
          onVerified: () {
            Navigator.of(dialogContext).pop();
            Navigator.of(context).pop();
          },
        ),
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
              onPressed: _loading ? null : _login,
              child: _loading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _activeAction == _AuthAction.signUp
                              ? 'Creating account...'
                              : 'Logging in...',
                        ),
                      ],
                    )
                  : const Text('Log In'),
            ),
            TextButton(
              onPressed: _loading ? null : _signUp,
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
