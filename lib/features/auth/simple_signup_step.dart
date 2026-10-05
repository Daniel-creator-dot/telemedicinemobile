import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';

/// Question size for the easier signup. At least 22, larger when the toggle is on.
double simpleQuestionSize(bool larger) => larger ? 30 : 24;

/// Body size for the easier signup. At least 18, larger when the toggle is on.
double simpleBodySize(bool larger) => larger ? 22 : 18;

/// Primary action height. At least 56, taller when the toggle is on.
double simpleButtonHeight(bool larger) => larger ? 64 : 56;

/// One question, short body copy, and a tall primary button on a white card.
class SimpleSignupStep extends StatelessWidget {
  const SimpleSignupStep({
    super.key,
    required this.question,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
    this.larger = false,
    this.child,
    this.error,
    this.loading = false,
    this.loadingLabel,
  });

  final String question;
  final String body;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool larger;
  final Widget? child;
  final String? error;
  final bool loading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final questionStyle = GoogleFonts.plusJakartaSans(
      fontSize: simpleQuestionSize(larger),
      fontWeight: FontWeight.w700,
      color: healynksInk,
      height: 1.25,
    );
    final bodyStyle = GoogleFonts.plusJakartaSans(
      fontSize: simpleBodySize(larger),
      fontWeight: FontWeight.w500,
      color: healynksInk,
      height: 1.4,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: healynksLine),
        boxShadow: clinicalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(question, style: questionStyle),
          const SizedBox(height: 12),
          Text(body, style: bodyStyle),
          if (child != null) ...[
            const SizedBox(height: 20),
            child!,
          ],
          if (error != null && error!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              error!.trim(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: simpleBodySize(larger),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF8C3A2F),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SimplePrimaryButton(
            label: buttonLabel,
            loadingLabel: loadingLabel,
            onPressed: onPressed,
            loading: loading,
            height: simpleButtonHeight(larger),
            fontSize: larger ? 20 : 18,
          ),
        ],
      ),
    );
  }
}

class _SimplePrimaryButton extends StatelessWidget {
  const _SimplePrimaryButton({
    required this.label,
    required this.onPressed,
    required this.loading,
    required this.height,
    required this.fontSize,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final double fontSize;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(clinicalButtonRadius);
    return DecoratedBox(
      key: const Key('simple-signup-next'),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: enabled ? clinicalActionGradient : null,
        color: enabled ? null : healynksBlue.withValues(alpha: 0.28),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: Center(
              child: loading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        ),
                        if (loadingLabel != null && loadingLabel!.trim().isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Text(
                            loadingLabel!.trim(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration simpleFieldDecoration(String hint, {required bool larger}) {
  final size = simpleBodySize(larger);
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.plusJakartaSans(fontSize: size, color: healynksMuted, fontWeight: FontWeight.w500),
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: larger ? 20 : 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: healynksInk, width: 1.4),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: healynksBlue, width: 2),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: healynksInk, width: 1.4),
    ),
  );
}
