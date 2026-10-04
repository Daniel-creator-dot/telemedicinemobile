import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';

class PendingReviewBanner extends StatelessWidget {
  const PendingReviewBanner({super.key, this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final current = status?.trim();
    final rejected = current == 'rejected';
    if (current != 'pending' && !rejected) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: rejected ? const Color(0xFFF3E6DC) : const Color(0xFFE7F0EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: digiForest.withValues(alpha: 0.16)),
      ),
      child: Text(
        rejected
            ? 'Your Healynks profile was not approved. Contact Healynks support.'
            : 'Your Healynks profile is pending review.',
        style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: digiForest),
      ),
    );
  }
}
