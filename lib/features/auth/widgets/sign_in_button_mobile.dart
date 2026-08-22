import 'package:flutter/material.dart';

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
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Image.network(
              'https://developers.google.com/identity/images/g-logo.png',
              height: 18,
              errorWidget: (context, error, stackTrace) =>
                  const Icon(Icons.account_circle, color: Colors.blue),
            ),
      label: const Text(
        'Sign in with Google',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}
