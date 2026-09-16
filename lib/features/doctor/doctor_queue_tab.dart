import 'package:flutter/foundation.dart';
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
    final pending = queue
        .where((a) {
          final s = a.status.toLowerCase();
          return s == 'pending' || s == 'triage';
        })
        .toList();
    final live = queue
        .where((a) {
          final s = a.status.toLowerCase();
          return s != 'pending' && s != 'triage';
        })
        .toList();

    if (kDebugMode) {
      debugPrint(
        'DoctorQueueTab: ${pending.length} pending approval, '
        '${live.length} live queue, ${appointments.length} total loaded',
      );
    }

    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFCBD5E1), size: 48),
            const SizedBox(height: 12),
            Text(
              'No patients in queue',
              style: GoogleFonts.roboto(
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'New bookings needing approval will appear here',
              style: GoogleFonts.roboto(color: const Color(0xFFCBD5E1), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pending.isNotEmpty) ...[
          Text(
            'Pending approval (${pending.length})',
            style: adminSans(weight: FontWeight.w800, size: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Approve new bookings before they join the live queue',
            style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...pending.map(
            (apt) => _PendingApprovalCard(
              appointment: apt,
              onApprove: () => onUpdateStatus(apt, 'approved'),
              onStart: () => onUpdateStatus(apt, 'consulting'),
              onDecline: () => onUpdateStatus(apt, 'cancelled'),
              onJoinVideo: () => onJoinVideo(apt),
              onOpenSoap: () => onOpenSoap(apt),
              onOpenChat: () => onOpenChat(apt),
              onOpenRx: () => onOpenRx(apt),
            ).animate().fadeIn(duration: 250.ms),
          ),
          const SizedBox(height: 20),
        ],
        if (live.isNotEmpty) ...[
          Text(
            'Live queue (${live.length})',
            style: adminSans(weight: FontWeight.w800, size: 14),
          ),
          const SizedBox(height: 12),
          _NextPatientCockpit(
            appointment: live.first,
            waiting: live.length - 1,
            onJoinVideo: () => onJoinVideo(live.first),
            onOpenSoap: () => onOpenSoap(live.first),
            onOpenChat: () => onOpenChat(live.first),
            onOpenRx: () => onOpenRx(live.first),
            onEndVisit: () => onUpdateStatus(live.first, 'completed'),
            onStart: () => onUpdateStatus(
              live.first,
              live.first.status.toLowerCase() == 'arrived' ? 'consulting' : 'arrived',
            ),
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 16),
          Text(
            'Waiting (${live.length - 1})',
            style: adminSans(weight: FontWeight.w800, size: 14),
          ),
          const SizedBox(height: 8),
          if (live.length <= 1)
            Text(
              'No one else is waiting.',
              style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 13),
            ),
          ...live.skip(1).toList().asMap().entries.map(
                (e) => _QueueRow(
                  index: e.key + 2,
                  apt: e.value,
                  onJoinVideo: () => onJoinVideo(e.value),
                  onOpenSoap: () => onOpenSoap(e.value),
                  onOpenChat: () => onOpenChat(e.value),
                  onOpenRx: () => onOpenRx(e.value),
                  onEndVisit: () => onUpdateStatus(e.value, 'completed'),
                  onApprove: () => onUpdateStatus(e.value, 'approved'),
                  onDecline: () => onUpdateStatus(e.value, 'cancelled'),
                  onStartConsult: () => onUpdateStatus(e.value, 'consulting'),
                ),
              ),
        ] else if (pending.isNotEmpty)
          Text(
            'No patients checked in yet — approve pending bookings above.',
            style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 13),
          ),
      ],
    );
  }
}

class _PendingApprovalCard extends StatelessWidget {
  const _PendingApprovalCard({
    required this.appointment,
    required this.onApprove,
    required this.onStart,
    required this.onDecline,
    required this.onJoinVideo,
    required this.onOpenSoap,
    required this.onOpenChat,
    required this.onOpenRx,
  });

  final Appointment appointment;
  final VoidCallback onApprove;
  final VoidCallback onStart;
  final VoidCallback onDecline;
  final VoidCallback onJoinVideo;
  final VoidCallback onOpenSoap;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRx;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminGlass(
        glow: AdminPalette.gold,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.fullName,
                        style: adminSans(weight: FontWeight.w800, size: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          appointment.consultType ?? appointment.service ?? 'Consultation',
                          appointment.preferredDate,
                          appointment.preferredTime,
                        ].join(' · '),
                        style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                DoctorStatusBadge(status: appointment.status),
              ],
            ),
            if ((appointment.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                appointment.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.roboto(color: Colors.white60, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DoctorActionChip(
                  label: 'Approve',
                  color: const Color(0xFF16A34A),
                  icon: Icons.check_circle_outline_rounded,
                  onTap: onApprove,
                ),
                DoctorActionChip(
                  label: 'Start',
                  color: const Color(0xFF7C3AED),
                  icon: Icons.play_arrow_rounded,
                  onTap: onStart,
                ),
                DoctorActionChip(
                  label: 'Decline',
                  color: const Color(0xFFDC2626),
                  icon: Icons.close_rounded,
                  onTap: onDecline,
                ),
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
                  label: 'Chat',
                  color: const Color(0xFF00D2C4),
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: onOpenChat,
                ),
                DoctorActionChip(
                  label: 'Rx',
                  color: const Color(0xFFF59E0B),
                  icon: Icons.medication_rounded,
                  onTap: onOpenRx,
                ),
              ],
            ),
          ],
        ),
      ),
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
          Text(
            'NEXT PATIENT',
            style: adminSans(
              color: AdminPalette.cyan,
              size: 11,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
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
            Text(
              appointment.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.roboto(color: Colors.white60, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              DoctorStatusBadge(status: appointment.status),
              const SizedBox(width: 8),
              Text(
                '$waiting waiting behind',
                style: GoogleFonts.roboto(color: Colors.white54, fontSize: 12),
              ),
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
                child: Text(
                  appointment.status.toLowerCase() == 'arrived'
                      ? 'Start consultation'
                      : 'Mark arrived',
                ),
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
    required this.onApprove,
    required this.onDecline,
    required this.onStartConsult,
  });

  final int index;
  final Appointment apt;
  final VoidCallback onJoinVideo;
  final VoidCallback onOpenSoap;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenRx;
  final VoidCallback onEndVisit;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final VoidCallback onStartConsult;

  @override
  Widget build(BuildContext context) {
    final status = apt.status.toLowerCase();
    final needsApproval = status == 'pending' || status == 'triage';

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
                  child: Text(
                    '$index',
                    style: GoogleFonts.roboto(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            if (needsApproval)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  DoctorActionChip(
                    label: 'Approve',
                    color: const Color(0xFF16A34A),
                    icon: Icons.check_circle_outline_rounded,
                    onTap: onApprove,
                  ),
                  DoctorActionChip(
                    label: 'Start',
                    color: const Color(0xFF7C3AED),
                    icon: Icons.play_arrow_rounded,
                    onTap: onStartConsult,
                  ),
                  DoctorActionChip(
                    label: 'Decline',
                    color: const Color(0xFFDC2626),
                    icon: Icons.close_rounded,
                    onTap: onDecline,
                  ),
                ],
              )
            else
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
