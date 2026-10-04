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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DigiCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClinicalStatusPill(
              label: rejected ? 'Not approved' : 'Pending review',
              tone: rejected ? ClinicalTone.clay : ClinicalTone.gold,
            ),
            const SizedBox(height: 8),
            Text(
              rejected
                  ? 'Your Healynks profile was not approved. Contact Healynks support if you think this is a mistake.'
                  : 'Your Healynks profile is with the clinic for review. You can keep signing in while that is open.',
              style: GoogleFonts.dmSans(fontSize: 14, color: digiInk, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
