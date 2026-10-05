import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'home_care_logic.dart';

/// Android and iOS tests and devices get a Share label.
/// share_plus is not a dependency, so Share copies the same public URL.
bool homeCareOfferShareLabel() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

Future<void> copyHomeCareLink(BuildContext context, String url) async {
  try {
    await Clipboard.setData(ClipboardData(text: url));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not copy that link. Select it and copy it instead.'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copied.')),
  );
}

class HomeCareShareActions extends StatelessWidget {
  const HomeCareShareActions({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final url = homeCarePublicUrl(token);
    if (url == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Anyone with this link can sign in and assess the job.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.4,
            color: healynksMuted,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          url,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: healynksInk,
            height: 1.35,
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => copyHomeCareLink(context, url),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy link'),
            ),
            if (homeCareOfferShareLabel())
              TextButton.icon(
                onPressed: () => copyHomeCareLink(context, url),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share'),
              ),
          ],
        ),
      ],
    );
  }
}
