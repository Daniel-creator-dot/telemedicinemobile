import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'home_care_repository.dart';

/// Stays on screen after Post request or Refer to home care succeeds.
const homeCareRequestSent =
    'Request sent. Nurses and home care agencies can take it.';

/// Shared so the command centre and the home care board show the same confirmation.
class HomeCareSentNotice extends ChangeNotifier {
  HomeCareSentNotice._();

  static final HomeCareSentNotice instance = HomeCareSentNotice._();

  bool _visible = false;
  HomeCareRequest? _latest;

  bool get visible => _visible;

  /// The request that was just posted, so every open list can put it on top.
  HomeCareRequest? get latest => _latest;

  void markSent(HomeCareRequest request) {
    _latest = request;
    _visible = true;
    notifyListeners();
  }

  void dismiss() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  /// Drops the confirmation when the person logs out.
  void reset() {
    final changed = _visible || _latest != null;
    _visible = false;
    _latest = null;
    if (changed) notifyListeners();
  }
}

class HomeCareRequestSentBanner extends StatelessWidget {
  const HomeCareRequestSentBanner({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: DigiCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.check_circle_outline,
                color: Color(0xFF0C7A62),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    homeCareRequestSent,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: healynksInk,
                      height: 1.4,
                    ),
                  ),
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
