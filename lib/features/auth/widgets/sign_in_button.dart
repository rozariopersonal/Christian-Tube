import 'package:flutter/material.dart';
import 'sign_in_button_mobile.dart';

class SignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const SignInButton({
    super.key,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SignInButtonMobile(
      onPressed: onPressed,
      isLoading: isLoading,
    );
  }
}
