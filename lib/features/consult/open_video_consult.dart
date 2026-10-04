import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import 'video_consult_screen.dart';

Future<void> openVideoConsult(
  BuildContext context,
  Appointment appointment, {
  bool isClinician = false,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoConsultScreen(
        appointment: appointment,
        isClinician: isClinician,
      ),
    ),
  );
}
