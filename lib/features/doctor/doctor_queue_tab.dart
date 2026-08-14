import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/appointment.dart';
import '../admin/admin_chrome.dart';
import 'doctor_workspace.dart';

class DoctorQueueTab extends StatelessWidget {
  const DoctorQueueTab({
    super.key,
    required this.appointments,
    required this.onJoinVideo,
    required this.onOpenSoap,
    required this.onOpenChat,
    required this.onOpenRx,
    required this.onUpdateStatus,
  });

  final List<Appointment> appointments;
  final void Function(Appointment) onJoinVideo;
  final void Function(Appointment) onOpenSoap;
  final void Function(Appointment) onOpenChat;
  final void Function(Appointment) onOpenRx;
  final void Function(Appointment, String) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final queue = activeDoctorQueue(appointments);
    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFCBD5E1), size: 48),
            const SizedBox(height: 12),
            Text('No patients in queue', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text('The next arrival will appear here', style: GoogleFonts.roboto(color: const Color(0xFFCBD5E1), fontSize: 12)),
          ],
        ),
      );
    }

    final next = queue.first;
    final rest = queue.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NextPatientCockpit(
          appointment: next,
          waiting: rest.length,
          onJoinVideo: () => onJoinVideo(next),
          onOpenSoap: () => onOpenSoap(next),
          onOpenChat: () => onOpenChat(next),
          onOpenRx: () => onOpenRx(next),
          onEndVisit: () => onUpdateStatus(next, 'completed'),
          onStart: () => onUpdateStatus(next, next.status.toLowerCase() == 'arrived' ? 'consulting' : 'arrived'),
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 16),
        Text('Waiting (${rest.length})', style: adminSans(weight: FontWeight.w800, size: 14)),
        const SizedBox(height: 8),
        if (rest.isEmpty)
          Text('No one else is waiting.', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 13)),
        ...rest.asMap().entries.map((e) => _QueueRow(
              index: e.key + 2,
              apt: e.value,
              onJoinVideo: () => onJoinVideo(e.value),
              onOpenSoap: () => onOpenSoap(e.value),
              onOpenChat: () => onOpenChat(e.value),
              onOpenRx: () => onOpenRx(e.value),
              onEndVisit: () => onUpdateStatus(e.value, 'completed'),
            )),
      ],
    );
  }
}

class _NextPatientCockpit extends StatelessWidget {
  const _NextPatientCockpit({
    required this.appointment,
    required this.waiting,
    required this.onJoinVideo,
    required this.onOpenSoap,
    required this.onOpenChat,
    required this.onOpenRx,
    required this.onEndVisit,
    required this.onStart,
  });

  final Appointment appointment;
  final int waiting;
  final VoidCallback onJoinVideo;
  final VoidCallback onOpenSoap;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRx;
  final VoidCallback onEndVisit;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AdminGlass(
      glow: AdminPalette.cyan,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT PATIENT', style: adminSans(color: AdminPalette.cyan, size: 11, weight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(appointment.fullName, style: adminSerif(size: 24, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [
              appointment.consultType ?? appointment.service ?? 'Consultation',
              appointment.preferredTime,
              if (appointment.queueNumber != null) '#${appointment.queueNumber}',
            ].join(' · '),
            style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13),
          ),
          if ((appointment.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(appointment.notes!, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.roboto(color: Colors.white60, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              DoctorStatusBadge(status: appointment.status),
              const SizedBox(width: 8),
              Text('$waiting waiting behind', style: GoogleFonts.roboto(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          DoctorVisitActions(
            appointment: appointment,
            onJoinVideo: onJoinVideo,
            onOpenSoap: onOpenSoap,
            onOpenChat: onOpenChat,
            onOpenRx: onOpenRx,
            onEndVisit: onEndVisit,
            compact: true,
          ),
          if (appointment.status.toLowerCase() != 'consulting') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                child: Text(appointment.status.toLowerCase() == 'arrived' ? 'Start consultation' : 'Mark arrived'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    required this.apt,
    required this.onJoinVideo,
    required this.onOpenSoap,
    required this.onOpenChat,
    required this.onOpenRx,
    required this.onEndVisit,
  });

  final int index;
  final Appointment apt;
  final VoidCallback onJoinVideo;
  final VoidCallback onOpenSoap;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRx;
  final VoidCallback onEndVisit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AdminGlass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF0F172A),
                child: Text('$index', style: GoogleFonts.roboto(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(apt.fullName, style: adminSans(weight: FontWeight.w700, size: 14)),
                    Text(
                      '${apt.consultType ?? apt.service ?? 'Visit'} · ${apt.preferredTime}',
                      style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
              DoctorStatusBadge(status: apt.status),
            ],
          ),
          const SizedBox(height: 10),
          DoctorVisitActions(
            appointment: apt,
            onJoinVideo: onJoinVideo,
            onOpenSoap: onOpenSoap,
            onOpenChat: onOpenChat,
            onOpenRx: onOpenRx,
            onEndVisit: onEndVisit,
            compact: true,
          ),
        ],
      ),
    ),
    );
  }
}
