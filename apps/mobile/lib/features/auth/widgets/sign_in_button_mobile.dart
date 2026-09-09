import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class SignInButtonMobile extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const SignInButtonMobile({
    super.key,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.onSurface,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: tokens.surfaceBorder),
        ),
      ),
      icon: isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
            )
          : Image.network(
              'https://developers.google.com/identity/images/g-logo.png',
              height: 18,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.account_circle, color: tokens.accent),
            ),
      label: const Text(
        'Sign in with Google',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
