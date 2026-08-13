import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/appointment.dart';

Color doctorStatusColor(String s) {
  switch (s.toLowerCase()) {
    case 'approved':
      return const Color(0xFF4F46E5);
    case 'completed':
      return const Color(0xFF16A34A);
    case 'consulting':
      return const Color(0xFF7C3AED);
    case 'arrived':
      return const Color(0xFF2563EB);
    case 'waiting':
    case 'queued':
      return const Color(0xFFD97706);
    case 'cancelled':
      return const Color(0xFFDC2626);
    case 'missed':
      return const Color(0xFF64748B);
    default:
      return const Color(0xFFF59E0B);
  }
}

class DoctorStatusBadge extends StatelessWidget {
  const DoctorStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = doctorStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.roboto(
          color: c,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class DoctorActionChip extends StatelessWidget {
  const DoctorActionChip({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.roboto(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoctorVisitActions extends StatelessWidget {
  const DoctorVisitActions({
    super.key,
    required this.appointment,
    required this.onJoinVideo,
    required this.onOpenSoap,
    required this.onOpenChat,
    required this.onOpenRx,
    required this.onEndVisit,
    this.compact = false,
  });

  final Appointment appointment;
  final VoidCallback onJoinVideo;
  final VoidCallback onOpenSoap;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRx;
  final VoidCallback onEndVisit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (appointment.isVideoConsult)
        DoctorActionChip(
          label: appointment.hasMeetingLink ? 'Video' : 'Start room',
          color: const Color(0xFF4F46E5),
          icon: Icons.videocam_rounded,
          onTap: onJoinVideo,
        ),
      DoctorActionChip(
        label: 'SOAP',
        color: const Color(0xFF7C3AED),
        icon: Icons.edit_note_rounded,
        onTap: onOpenSoap,
      ),
      DoctorActionChip(
        label: 'Rx',
        color: const Color(0xFFF59E0B),
        icon: Icons.medication_rounded,
        onTap: onOpenRx,
      ),
      DoctorActionChip(
        label: 'Chat',
        color: const Color(0xFF00D2C4),
        icon: Icons.chat_bubble_outline_rounded,
        onTap: onOpenChat,
      ),
      DoctorActionChip(
        label: 'End visit',
        color: const Color(0xFF16A34A),
        icon: Icons.check_circle_outline,
        onTap: onEndVisit,
      ),
    ];

    if (compact) {
      return Wrap(spacing: 6, runSpacing: 6, children: chips);
    }
    return Row(
      children: chips
          .map((w) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: w)))
          .toList(),
    );
  }
}

List<Appointment> activeDoctorQueue(List<Appointment> appointments) {
  return appointments.where((a) {
    final s = a.status.toLowerCase();
    if (['completed', 'cancelled', 'rejected', 'missed'].contains(s)) return false;
    if (['approved', 'arrived', 'waiting', 'consulting', 'queued'].contains(s)) return true;
    return a.isVideoConsult && ['pending', 'triage'].contains(s);
  }).toList()
    ..sort((a, b) {
      int rank(String s) {
        switch (s.toLowerCase()) {
          case 'consulting':
            return 0;
          case 'arrived':
            return 1;
          case 'queued':
            return 2;
          case 'approved':
            return 3;
          default:
            return 4;
        }
      }
      final r = rank(a.status).compareTo(rank(b.status));
      if (r != 0) return r;
      return (a.queueNumber ?? 99).compareTo(b.queueNumber ?? 99);
    });
}
