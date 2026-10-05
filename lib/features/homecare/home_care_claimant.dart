import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/clinical_ui.dart';

/// The nurse or agency who took a home-care job.
/// Only an admin or the referring doctor receives this from the API.
class HomeCareClaimant {
  const HomeCareClaimant({
    required this.name,
    required this.kind,
    this.phone,
    this.agencyName,
    this.region,
    this.town,
    this.practiceArea,
    this.licenseNumber,
    this.facility,
  });

  final String name;
  final String kind;
  final String? phone;
  final String? agencyName;
  final String? region;
  final String? town;
  final String? practiceArea;
  final String? licenseNumber;
  final String? facility;

  bool get isAgency => kind == 'agency';

  /// Nurse or Agency. Empty profile fields are not included.
  String get roleLabel => isAgency ? 'Agency' : 'Nurse';

  List<String> get detailLines {
    return [
      'Role · $roleLabel',
      if ((agencyName ?? '').isNotEmpty) 'Agency · $agencyName',
      if ((region ?? '').isNotEmpty) 'Region · $region',
      if ((town ?? '').isNotEmpty) 'Town · $town',
      if ((practiceArea ?? '').isNotEmpty) 'Practice area · $practiceArea',
      if ((licenseNumber ?? '').isNotEmpty) 'License · $licenseNumber',
      if ((facility ?? '').isNotEmpty) 'Facility · $facility',
    ];
  }

  static HomeCareClaimant? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final name = _text(json['name']);
    final phone = _text(json['phone']);
    final kind = _text(json['kind']);
    if (name == null && phone == null && kind == null) return null;
    return HomeCareClaimant(
      name: name ?? 'Caregiver',
      kind: kind == 'agency' ? 'agency' : 'nurse',
      phone: phone,
      agencyName: _text(json['agency_name']),
      region: _text(json['region']),
      town: _text(json['town']),
      practiceArea: _text(json['practice_area']),
      licenseNumber: _text(json['license_number']),
      facility: _text(json['facility']),
    );
  }
}

String? _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

/// Dials [phone] with a tel: link. Shows a short note when the device cannot place the call.
Future<void> callHomeCareNumber(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  try {
    await launchUrl(uri);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Call $phone from your phone.')),
    );
  }
}

/// The request's contact number, labeled so it is not read as the nurse's phone.
class HomeCarePatientContactLine extends StatelessWidget {
  const HomeCarePatientContactLine({
    super.key,
    required this.phone,
    this.onCall,
  });

  final String phone;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient or family contact',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: healynksMuted,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          phone,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            color: healynksInk,
            height: 1.35,
          ),
        ),
        if (onCall != null)
          TextButton.icon(
            onPressed: onCall,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call this number'),
          ),
      ],
    );
  }
}

/// Nurse details on a claimed job. Sits apart from the patient or family number.
class HomeCareClaimantBlock extends StatelessWidget {
  const HomeCareClaimantBlock({super.key, required this.claimant});

  final HomeCareClaimant claimant;

  @override
  Widget build(BuildContext context) {
    final phone = claimant.phone;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: healynksCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: healynksLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nurse',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: healynksMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            claimant.name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: healynksInk,
              height: 1.3,
            ),
          ),
          if (phone == null) ...[
            const SizedBox(height: 6),
            Text(
              'No phone on this profile.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: healynksMuted,
                height: 1.35,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            SelectableText(
              phone,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: healynksInk,
                height: 1.35,
              ),
            ),
            TextButton.icon(
              onPressed: () => callHomeCareNumber(context, phone),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Call'),
            ),
          ],
          for (final line in claimant.detailLines) ...[
            const SizedBox(height: 4),
            Text(
              line,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: healynksInk,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
