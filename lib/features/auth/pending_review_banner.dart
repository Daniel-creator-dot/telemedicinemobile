import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';

class PendingReviewBanner extends StatelessWidget {
  const PendingReviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: digiForest.withValues(alpha: 0.16)),
      ),
      child: Text(
        'Your Healynks profile is pending review.',
        style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: digiForest),
      ),
    );
  }
}
