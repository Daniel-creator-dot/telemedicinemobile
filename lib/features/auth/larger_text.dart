import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';

/// Session-only type bump for the easier signup. Does not replace the app theme.
class LargerTextController extends ChangeNotifier {
  bool larger = false;

  void toggle() {
    larger = !larger;
    notifyListeners();
  }
}

class LargerTextScope extends InheritedNotifier<LargerTextController> {
  const LargerTextScope({
    super.key,
    required LargerTextController controller,
    required super.child,
  }) : super(notifier: controller);

  static LargerTextController? _controller(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LargerTextScope>()?.notifier;
  }

  static bool largerOf(BuildContext context) => _controller(context)?.larger ?? false;

  static void toggle(BuildContext context) => _controller(context)?.toggle();
}

/// Visible control for the easier signup. Stays on the canvas, with no gradient.
class LargerTextToggle extends StatelessWidget {
  const LargerTextToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final larger = LargerTextScope.largerOf(context);
    final height = larger ? 64.0 : 56.0;
    return OutlinedButton(
      onPressed: () => LargerTextScope.toggle(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: healynksInk,
        backgroundColor: Colors.white,
        side: const BorderSide(color: healynksInk, width: 1.5),
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalButtonRadius)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: larger ? 18 : 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(larger ? 'Larger text on' : 'Larger text'),
    );
  }
}
