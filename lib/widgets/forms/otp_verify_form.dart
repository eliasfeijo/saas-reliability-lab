import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtpVerifyForm extends StatefulWidget {
  const OtpVerifyForm({super.key, this.signUpEmail, this.onVerified});
  final String? signUpEmail;
  final Function? onVerified;

  @override
  State<OtpVerifyForm> createState() => _OtpVerifyFormState();
}

class _OtpVerifyFormState extends State<OtpVerifyForm> {
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  String? _error;

  @override
  void initState() {
    super.initState();
    // Initialize focus nodes and controllers
    for (var c in _otpControllers) {
      c.addListener(() {
        if (c.text.length == 1) {
          final nextIndex = _otpControllers.indexOf(c) + 1;
          if (nextIndex < _otpControllers.length) {
            FocusScope.of(context).requestFocus(_otpFocusNodes[nextIndex]);
          }
        } else if (c.text.isEmpty) {
          final prevIndex = _otpControllers.indexOf(c) - 1;
          if (prevIndex >= 0) {
            FocusScope.of(context).requestFocus(_otpFocusNodes[prevIndex]);
          }
        }
        _checkAndVerifyCode();
      });
    }
  }

  @override
  void dispose() {
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    for (var c in _otpControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _checkAndVerifyCode() {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length == 6 && !_otpControllers.any((c) => c.text.isEmpty)) {
      _verifyOtp();
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: widget.signUpEmail!,
        token: code,
        type: OtpType.signup,
      );
      if (res.user != null && mounted) {
        Navigator.pop(context); // Close bottom sheet
        if (widget.onVerified != null) {
          widget.onVerified!();
        }
      } else {
        throw Exception('Invalid code');
      }
    } catch (e) {
      setState(() => _error = 'Verification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'Enter the OTP sent to\n${widget.signUpEmail}',
            style: Theme.of(context).textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 40,
                child: KeyboardListener(
                  focusNode: FocusNode(), // Needs a listener node
                  onKeyEvent: (KeyEvent event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.backspace &&
                        _otpControllers[index].text.isEmpty) {
                      if (index > 0) {
                        _otpControllers[index - 1].clear();
                        FocusScope.of(
                          context,
                        ).requestFocus(_otpFocusNodes[index - 1]);
                      }
                    }
                  },
                  child: TextField(
                    focusNode: _otpFocusNodes[index],
                    controller: _otpControllers[index],
                    autofocus: index == 0,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.length == 1 &&
                          index < _otpControllers.length - 1) {
                        FocusScope.of(
                          context,
                        ).requestFocus(_otpFocusNodes[index + 1]);
                      } else if (value.isEmpty && index > 0) {
                        FocusScope.of(
                          context,
                        ).requestFocus(_otpFocusNodes[index - 1]);
                      }
                      _checkAndVerifyCode();
                    },
                    onSubmitted: (_) => _checkAndVerifyCode(),
                    onEditingComplete: _checkAndVerifyCode,
                  ),
                ),
              ),
            );
          }),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(_error!, style: TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _verifyOtp, child: const Text('Verify Code')),
      ],
    );
  }
}
