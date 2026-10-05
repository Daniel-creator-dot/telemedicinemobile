import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'clinical_ui.dart';

/// Shown on the admin home-care post form, the nurse and agency request
/// card, and the sheet where they take the request.
const healynksHomeCareCommission = 'Healynks keeps a 5% commission.';

class HealynksHomeCareCommissionNote extends StatelessWidget {
  const HealynksHomeCareCommissionNote({super.key, this.compact = false});

  /// Tighter padding for a request card. The sentence stays the same.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: healynksLine),
      ),
      child: Text(
        healynksHomeCareCommission,
        style: GoogleFonts.plusJakartaSans(
          fontSize: compact ? 12.5 : 13.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: healynksInk,
        ),
      ),
    );
  }
}
