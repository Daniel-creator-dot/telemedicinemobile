import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/appointment.dart';
import '../admin/admin_chrome.dart';
import '../consult/open_video_consult.dart';
import '../patient/appointments_repository.dart';
import '../patient/care_repository.dart';
import '../patient/chat_screen.dart';
import 'consultation_dialog.dart';
import 'doctor_queue_tab.dart';
import 'prescription_dialog.dart';

// ---------------------------------------------------------------------------
// Tab enum
// ---------------------------------------------------------------------------
enum _DoctorTab { overview, appointments, queue, doctors, reports }

// ---------------------------------------------------------------------------
// DoctorHomeScreen
// ---------------------------------------------------------------------------
class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _DoctorTab _tab = _DoctorTab.overview;
  bool _sidebarOpen = false;
  bool? _sidebarWasInitialized;

  List<Appointment> _appointments = [];
  List<Map<String, dynamic>> _doctors = [];
  List<Map<String, dynamic>> _referrals = [];
  Map<String, dynamic> _stats = {
    'stats': {'total': 0, 'today': 0, 'pending': 0, 'completed': 0},
    'trends': [],
    'workload': [],
  };
  bool _loading = true;
  bool _online = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.dio.get<List<dynamic>>('/api/appointments'),
        api.dio.get<Map<String, dynamic>>('/api/analytics/dashboard'),
        api.dio.get<List<dynamic>>('/api/doctors'),
      ]);
      List<Map<String, dynamic>> refs = [];
      try {
        refs = await context.read<CareRepository>().getReferrals();
      } catch (_) {}
      final aptsRaw = results[0].data as List<dynamic>? ?? [];
      final statsRaw = results[1].data as Map<String, dynamic>? ?? {};
      final docsRaw = results[2].data as List<dynamic>? ?? [];
      setState(() {
        _appointments = aptsRaw
            .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
            .toList();
        _stats = statsRaw;
        _doctors = docsRaw.map((j) => j as Map<String, dynamic>).toList();
        _referrals = refs;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(Appointment apt, String status) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.patch<Map<String, dynamic>>(
        '/api/appointments/${apt.id}/status',
        data: {'status': status},
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Marked as $status')));
      _loadAll();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _generateLink(Appointment apt) => _joinVideoConsult(apt);

  Future<void> _joinVideoConsult(Appointment apt) async {
    var current = apt;
    final repo = context.read<AppointmentsRepository>();
    try {
      if (!current.hasMeetingLink) {
        current = await repo.generateMeetingLink(apt.id);
        current = current.copyWith(doctorName: apt.doctorName ?? current.doctorName);
      }
      final status = current.status.toLowerCase();
      if (status != 'completed' && status != 'cancelled' && status != 'consulting') {
        try {
          await repo.updateAppointmentStatus(current.id, 'consulting');
          current = current.copyWith(status: 'consulting');
        } catch (_) {}
      }
      if (!mounted) return;
      await openVideoConsult(context, current, isClinician: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start video consult: $e')),
        );
      }
      return;
    }
    if (mounted) _loadAll();
  }

  void _openConsultation(Appointment apt) {
    showDialog(
      context: context,
      builder: (ctx) => ConsultationDialog(appointment: apt),
    ).then((_) => _loadAll());
  }

  void _openChat(Appointment apt) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClinicalChatScreen(appointment: apt)),
    );
  }

  void _openPrescription(Appointment apt) {
    showDialog(
      context: context,
      builder: (ctx) => PrescriptionDialog(appointment: apt),
    );
  }

  Widget _referralCard(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? 'pending';
    final incoming = r['to_doctor_id']?.toString() == context.read<Session>().user?.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r['referral_code'] ?? ''} · ${r['specialty'] ?? 'Specialist'}',
              style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
            ),
            Text('${r['patient_name'] ?? ''} · ${incoming ? 'Incoming' : 'Sent'} · $status'),
            Text(r['reason']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if ((r['result_notes'] ?? '').toString().isNotEmpty)
              Text('Result: ${r['result_notes']}', style: const TextStyle(fontSize: 12, color: Color(0xFF0F766E))),
            if (incoming && status == 'pending')
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await context.read<CareRepository>().updateReferral(r['id'] as int, {'status': 'accepted'});
                    _loadAll();
                  },
                  child: const Text('Accept'),
                ),
              ),
            if (incoming && (status == 'accepted' || status == 'in_progress'))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final notes = TextEditingController();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Return referral result'),
                        content: TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Findings / plan')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await context.read<CareRepository>().updateReferral(r['id'] as int, {
                        'status': 'completed',
                        'result_notes': notes.text.trim(),
                      });
                      _loadAll();
                    }
                  },
                  child: const Text('Return result'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _fmtDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(String s) {
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
        return const Color(0xFFD97706);
      case 'cancelled':
        return const Color(0xFFDC2626);
      case 'missed':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _badge(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3)),
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

  int get _todayCount {
    final stats = _stats['stats'];
    return int.tryParse(stats?['today']?.toString() ?? '0') ?? 0;
  }

  int get _pendingCount {
    final stats = _stats['stats'];
    return int.tryParse(stats?['pending']?.toString() ?? '0') ?? 0;
  }

  int get _completedCount {
    final stats = _stats['stats'];
    return int.tryParse(stats?['completed']?.toString() ?? '0') ?? 0;
  }

  int get _totalCount {
    final stats = _stats['stats'];
    return int.tryParse(stats?['total']?.toString() ?? '0') ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AdminPalette.bg,
      body: AdminMeshBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(session, isDesktop),
              Expanded(
                child: _loading
                    ? const AdminOrbitLoader(message: 'Opening clinic floor…')
                    : _error != null
                        ? _buildError()
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            child: KeyedSubtree(key: ValueKey(_tab), child: _buildContent()),
                          ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: !isDesktop ? _buildBottomNav() : null,
    );
  }

  Widget _headerTabItem(String label, _DoctorTab tab, IconData icon) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: active ? const LinearGradient(colors: [AdminPalette.gold, Color(0xFFC4A574)]) : null,
          color: active ? null : Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? Colors.black : AdminPalette.mute, size: 15),
            const SizedBox(width: 6),
            Text(label, style: adminSans(size: 12, weight: FontWeight.w800, color: active ? Colors.black : AdminPalette.mute)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(Session session, bool isDesktop) {
    final tabLabels = {
      _DoctorTab.overview: 'Dashboard',
      _DoctorTab.appointments: 'Appointments',
      _DoctorTab.queue: 'Queue Management',
      _DoctorTab.doctors: 'Doctors & Schedules',
      _DoctorTab.reports: 'Reports & Analytics',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: AdminGlass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: isDesktop
            ? Row(
                children: [
                  _clinicMark(),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _headerTabItem('Floor', _DoctorTab.overview, Icons.dashboard_rounded),
                          _headerTabItem('Bookings', _DoctorTab.appointments, Icons.calendar_month_rounded),
                          _headerTabItem('Queue', _DoctorTab.queue, Icons.graphic_eq_rounded),
                          _headerTabItem('Roster', _DoctorTab.doctors, Icons.people_alt_rounded),
                          _headerTabItem('Pulse', _DoctorTab.reports, Icons.insights_rounded),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AdminPalette.gold),
                    onPressed: _loadAll,
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AdminPalette.gold.withValues(alpha: 0.18),
                    child: Text(
                      (session.user?.name ?? 'D')[0].toUpperCase(),
                      style: adminSans(size: 13, weight: FontWeight.w800, color: AdminPalette.gold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(session.user?.name ?? 'Doctor', style: adminSans(size: 13, weight: FontWeight.w700)),
                  IconButton(
                    tooltip: 'Logout',
                    icon: const Icon(Icons.logout_rounded, color: AdminPalette.rose, size: 20),
                    onPressed: () async {
                      await session.clear();
                      if (mounted) context.go('/login');
                    },
                  ),
                ],
              )
            : Row(
                children: [
                  _clinicMark(compact: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tabLabels[_tab]!, style: adminSerif(size: 16, weight: FontWeight.w700)),
                        Text('CLINIC FLOOR', style: adminSans(size: 9, weight: FontWeight.w800, color: AdminPalette.gold, letterSpacing: 1.4)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AdminPalette.gold),
                    onPressed: _loadAll,
                  ),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AdminPalette.gold.withValues(alpha: 0.18),
                    child: Text(
                      (session.user?.name ?? 'D')[0].toUpperCase(),
                      style: adminSans(size: 12, weight: FontWeight.w800, color: AdminPalette.gold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: AdminPalette.rose, size: 18),
                    onPressed: () async {
                      await session.clear();
                      if (mounted) context.go('/login');
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Widget _clinicMark({bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AdminPalette.gold, AdminPalette.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: AdminPalette.gold.withValues(alpha: 0.45), blurRadius: 16)],
          ),
          child: const Icon(Icons.health_and_safety_rounded, color: Colors.black, size: 20),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Digi Health', style: adminSerif(size: 15, weight: FontWeight.w700)),
              Text('CLINIC FLOOR', style: adminSans(size: 9, weight: FontWeight.w800, color: AdminPalette.gold, letterSpacing: 1.4)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBottomNav() {
    final items = [
      (_DoctorTab.overview, Icons.dashboard_rounded, 'Home'),
      (_DoctorTab.appointments, Icons.calendar_month_rounded, 'Schedule'),
      (_DoctorTab.queue, Icons.queue_rounded, 'Queue'),
      (_DoctorTab.doctors, Icons.people_alt_rounded, 'Doctors'),
      (_DoctorTab.reports, Icons.bar_chart_rounded, 'Reports'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC0C1422),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(color: AdminPalette.gold.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, -4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: items.map((item) {
                  final active = _tab == item.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _tab = item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: active ? const LinearGradient(colors: [AdminPalette.gold, Color(0xFFC4A574)]) : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.$2, size: 20, color: active ? Colors.black : AdminPalette.mute),
                          const SizedBox(height: 3),
                          Text(
                            item.$3,
                            style: adminSans(
                              size: 10,
                              weight: FontWeight.w800,
                              color: active ? Colors.black : AdminPalette.mute,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? backgroundImage,
    Color? overlayColor,
  }) {
    return AdminActionTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  // ---------------------------------------------------------------------------
  // Content router
  // ---------------------------------------------------------------------------
  Widget _buildContent() {
    switch (_tab) {
      case _DoctorTab.overview:
        return _buildOverview();
      case _DoctorTab.appointments:
        return _buildAppointmentsTab();
      case _DoctorTab.queue:
        return _buildQueueTab();
      case _DoctorTab.doctors:
        return _buildDoctorsTab();
      case _DoctorTab.reports:
        return _buildReportsTab();
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AdminGlass(
          glow: AdminPalette.gold,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AdminPalette.gold.withValues(alpha: 0.35), AdminPalette.cyan.withValues(alpha: 0.2)],
                  ),
                ),
                child: const Icon(Icons.wifi_off_rounded, color: AdminPalette.gold, size: 42),
              ),
              const SizedBox(height: 18),
              Text('Clinic floor is offline', style: adminSerif(size: 20, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Check the connection and sync the floor again.',
                style: adminSans(size: 13, color: AdminPalette.mute),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminPalette.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // OVERVIEW TAB
  // ===========================================================================
  Widget _buildOverview() {
    final liveVideo = _appointments.where((a) {
      final s = a.status.toLowerCase();
      return a.isVideoConsult &&
          !['completed', 'cancelled', 'rejected', 'missed'].contains(s);
    }).toList()
      ..sort((a, b) {
        int rank(String s) {
          switch (s.toLowerCase()) {
            case 'consulting':
              return 0;
            case 'arrived':
              return 1;
            case 'approved':
              return 2;
            case 'queued':
              return 3;
            default:
              return 4;
          }
        }
        return rank(a.status).compareTo(rank(b.status));
      });
    final activeConsult = liveVideo.isEmpty ? null : liveVideo.first;
    final workload = _stats['workload'] as List<dynamic>? ?? [];
    final session = context.watch<Session>();
    final greeting = _getGreeting();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Welcome Banner with Image ─────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            height: 188,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AdminPalette.gold.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/branding/onboarding_1.png',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF070B14).withValues(alpha: 0.92),
                          AdminPalette.gold.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            const AdminLiveDot(color: AdminPalette.gold),
                            const SizedBox(width: 8),
                            Text(
                              '$greeting,',
                              style: adminSans(size: 12, weight: FontWeight.w600, color: AdminPalette.mute, letterSpacing: 0.4),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          (session.user?.name != null)
                              ? (session.user!.name.toLowerCase().startsWith('dr.')
                                  ? session.user!.name
                                  : 'Dr. ${session.user!.name}')
                              : 'Doctor',
                          style: adminSerif(size: 28, weight: FontWeight.w700, letterSpacing: -0.6),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            AdminStatusChip(label: '$_todayCount today', color: AdminPalette.cyan),
                            AdminStatusChip(label: '$_pendingCount pending', color: AdminPalette.gold),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05),

          // ── Active Consultation Spotlight ──────────────────────────────────
          if (activeConsult != null)
            Builder(
              builder: (context) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF4F46E5).withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withOpacity(0.2),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Watermark background icon
                        Positioned(
                          right: -25,
                          bottom: -25,
                          child: Icon(
                            activeConsult.isTelemedicine
                                ? Icons.videocam_rounded
                                : Icons.assignment_rounded,
                            size: 160,
                            color: Colors.white.withOpacity(0.03),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFEF4444).withOpacity(0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                            .animate(onPlay: (c) => c.repeat())
                                            .scale(
                                              begin: const Offset(0.7, 0.7),
                                              end: const Offset(1.4, 1.4),
                                              duration: 1000.ms,
                                            )
                                            .then()
                                            .fadeOut(),
                                        const SizedBox(width: 6),
                                        Text(
                                          '● LIVE',
                                          style: GoogleFonts.roboto(
                                            color: const Color(0xFFEF4444),
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4F46E5,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF4F46E5,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  activeConsult.isTelemedicine
                                      ? 'TELEHEALTH'
                                      : 'IN-CLINIC',
                                  style: GoogleFonts.roboto(
                                    color: const Color(0xFF818CF8),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            activeConsult.fullName,
                            style: GoogleFonts.roboto(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                color: Colors.white38,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Scheduled for ${activeConsult.preferredTime}',
                                style: GoogleFonts.roboto(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (activeConsult.isVideoConsult)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _joinVideoConsult(activeConsult),
                                    icon: Icon(
                                      activeConsult.hasMeetingLink
                                          ? Icons.videocam_rounded
                                          : Icons.add_link_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      activeConsult.hasMeetingLink
                                          ? 'JOIN ROOM'
                                          : 'START ROOM',
                                      style: GoogleFonts.roboto(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00D2C4),
                                      foregroundColor: Colors.black,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              if (activeConsult.isVideoConsult)
                                const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _openConsultation(activeConsult),
                                  icon: const Icon(
                                    Icons.assignment_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'WORKSPACE',
                                    style: GoogleFonts.roboto(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                      width: 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Tooltip(
                                message: 'Write Prescription',
                                child: Container(
                                  height: 42,
                                  width: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.description_rounded,
                                      color: Colors.amber,
                                      size: 18,
                                    ),
                                    onPressed: () =>
                                        _openPrescription(activeConsult),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ).animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 2000.ms,
                  color: const Color(0xFF4F46E5).withOpacity(0.3),
                  angle: 0.5,
                )
                .then()
                .shimmer(
                  duration: 2000.ms,
                  color: const Color(0xFF818CF8).withOpacity(0.2),
                  angle: -0.5,
                )
                .fadeIn(duration: 400.ms).slideY(begin: -0.1);
              },
            ),

          AdminGlass(
            glow: _online ? AdminPalette.lime : AdminPalette.line,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SwitchListTile(
              value: _online,
              onChanged: (v) async {
                setState(() => _online = v);
                try {
                  await context.read<CareRepository>().setDoctorOnline(v);
                } catch (_) {}
              },
              title: Text('Available for Consult Now', style: adminSans(size: 14, weight: FontWeight.w800)),
              subtitle: Text(
                _online ? 'Patients can be matched to you now' : 'Go online to receive live queue patients',
                style: adminSans(size: 12, color: AdminPalette.mute),
              ),
              activeThumbColor: AdminPalette.lime,
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick Actions Grid ──────────────────────────────────────────────
          if (_referrals.isNotEmpty) ...[
            _sectionHeader('Referrals'),
            const SizedBox(height: 10),
            ..._referrals.take(6).map(_referralCard),
            const SizedBox(height: 16),
          ],
          _sectionHeader('Quick Actions'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: isMobile ? 2 : 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isMobile ? 1.05 : 1.35,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _quickActionCard(
                'Appointments',
                'Schedule & slots',
                Icons.calendar_month_rounded,
                const Color(0xFF4F46E5),
                () => setState(() => _tab = _DoctorTab.appointments),
                backgroundImage: 'assets/appointment.png',
                overlayColor: const Color(0xFF4C0099), // deep purple
              ),
              _quickActionCard(
                'Live Queue',
                'Patient check-ins',
                Icons.queue_rounded,
                const Color(0xFF00D2C4),
                () => setState(() => _tab = _DoctorTab.queue),
                backgroundImage: 'assets/live queue.png',
                overlayColor: const Color(0xFF9B1C1C), // deep crimson
              ),
              _quickActionCard(
                'Specialists',
                'Doctors directory',
                Icons.people_alt_rounded,
                const Color(0xFFF59E0B),
                () => setState(() => _tab = _DoctorTab.doctors),
                backgroundImage: 'assets/speciality.png',
                overlayColor: const Color(0xFF065F46), // deep emerald
              ),
              _quickActionCard(
                'Reports',
                'Clinic analytics',
                Icons.bar_chart_rounded,
                const Color(0xFFEF4444),
                () => setState(() => _tab = _DoctorTab.reports),
                backgroundImage: 'assets/records.png',
                overlayColor: const Color(0xFF92400E), // deep amber
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
          const SizedBox(height: 20),

          // ── Stats grid ─────────────────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isMobile ? 1.05 : 1.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _statCard(
                "Today's Appointments",
                '$_todayCount',
                Icons.calendar_today_rounded,
                const Color(0xFF2563EB),
                const Color(0xFFEFF6FF),
              ).animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
              _statCard(
                'Pending Approval',
                '$_pendingCount',
                Icons.hourglass_top_rounded,
                const Color(0xFFD97706),
                const Color(0xFFFFFBEB),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
              _statCard(
                'Completed',
                '$_completedCount',
                Icons.check_circle_rounded,
                const Color(0xFF16A34A),
                const Color(0xFFF0FDF4),
              ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
              _statCard(
                'Total Bookings',
                '$_totalCount',
                Icons.people_rounded,
                const Color(0xFF4F46E5),
                const Color(0xFFEEF2FF),
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
            ],
          ),
          const SizedBox(height: 20),

          // ── Live Appointment Table ─────────────────────────────────────────
          _sectionHeader('Live Appointment View'),
          const SizedBox(height: 10),
          AdminGlass(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _getLiveAppointmentsList().isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No live appointments scheduled for today',
                        style: adminSans(size: 13, color: AdminPalette.mute),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _getLiveAppointmentsList().length,
                    separatorBuilder: (context, index) => Divider(
                      color: Colors.white.withValues(alpha: 0.06),
                      height: 1,
                      thickness: 1,
                    ),
                    itemBuilder: (context, index) {
                      final apt = _getLiveAppointmentsList()[index];
                      return _liveRow(apt);
                    },
                  ),
          ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
          const SizedBox(height: 20),

          // ── Doctor Workload ────────────────────────────────────────────────
          if (workload.isNotEmpty) ...[
            _sectionHeader('Doctor Workload (Today)'),
            const SizedBox(height: 10),
            AdminGlass(
              child: Column(
                children: [
                  for (final w in workload) ...[
                    Builder(
                      builder: (_) {
                        final name = w['name']?.toString() ?? '';
                        final count = int.tryParse(w['count']?.toString() ?? '0') ?? 0;
                        final pct = (count / 20.0).clamp(0.0, 1.0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: AdminGlowBar(
                            label: name,
                            pct: pct,
                            color: AdminPalette.gold,
                            trailing: '$count pts',
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String actionLabel,
    required Color actionColor,
    required VoidCallback onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.roboto(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: GoogleFonts.roboto(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color accent,
    Color bg,
  ) {
    return AdminKpiCard(label: label, value: value, icon: icon, color: accent);
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  List<Appointment> _getLiveAppointmentsList() {
    final now = DateTime.now();
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final activeList = _appointments.where((apt) {
      final s = apt.status.toLowerCase();
      return !['completed', 'cancelled', 'rejected', 'missed'].contains(s);
    }).toList();

    DateTime? parseDt(String dateStr, String timeStr) {
      try {
        final parts = timeStr.split(':');
        final formattedTime = parts.map((p) => p.padLeft(2, '0')).join(':');
        return DateTime.parse("${dateStr}T$formattedTime");
      } catch (_) {
        return null;
      }
    }

    activeList.sort((a, b) {
      final dtA = parseDt(a.preferredDate, a.preferredTime) ?? DateTime(1970);
      final dtB = parseDt(b.preferredDate, b.preferredTime) ?? DateTime(1970);

      final isTodayA = a.preferredDate == todayStr;
      final isTodayB = b.preferredDate == todayStr;

      if (isTodayA && !isTodayB) return -1;
      if (!isTodayA && isTodayB) return 1;

      return dtA.compareTo(dtB);
    });

    return activeList.take(5).toList();
  }

  Widget _liveRow(Appointment apt) {
    final isConsulting = apt.status.toLowerCase() == 'consulting';

    return InkWell(
      onTap: () => _openConsultation(apt),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AdminPalette.gold.withValues(alpha: 0.16),
                  child: Text(
                    _getInitials(apt.fullName),
                    style: adminSans(
                      color: AdminPalette.gold,
                      weight: FontWeight.w800,
                      size: 14,
                    ),
                  ),
                ),
                if (isConsulting)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2C4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          apt.fullName,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: adminSans(
                            weight: FontWeight.w700,
                            size: 15,
                          ),
                        ),
                      ),
                      if (apt.priority == 'High') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'HIGH',
                            style: GoogleFonts.roboto(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: Color(0xFF64748B),
                        size: 12,
                      ),
                      Text(
                        apt.preferredTime,
                        style: adminSans(
                          color: AdminPalette.mute,
                          size: 11,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCBD5E1),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        _fmtDate(apt.preferredDate),
                        style: GoogleFonts.roboto(
                          color: const Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                      if (apt.isTelemedicine) ...[
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          'Telehealth',
                          style: GoogleFonts.roboto(
                            color: const Color(0xFF4F46E5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (apt.staffId != null ||
                      apt.nationwideId != null ||
                      (apt.whoIsComing != null &&
                          apt.whoIsComing!.isNotEmpty)) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (apt.whoIsComing != null &&
                            apt.whoIsComing!.isNotEmpty)
                          'For: ${apt.whoIsComing!.join(', ')}',
                        if (apt.staffId != null) 'Staff ID: ${apt.staffId}',
                        if (apt.nationwideId != null)
                          'Nationwide: ${apt.nationwideId}',
                      ].join(' • '),
                      style: GoogleFonts.roboto(
                        color: const Color(0xFF94A3B8),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _badge(apt.status),
                const SizedBox(height: 8),
                _liveRowAction(apt),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveRowAction(Appointment apt) {
    if (apt.isVideoConsult) {
      if (apt.hasMeetingLink) {
        return ElevatedButton.icon(
          onPressed: () => _joinVideoConsult(apt),
          icon: const Icon(Icons.videocam_rounded, size: 12),
          label: const Text('JOIN'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: GoogleFonts.roboto(fontSize: 10, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        return OutlinedButton.icon(
          onPressed: () => _generateLink(apt),
          icon: const Icon(Icons.add_link_rounded, size: 12),
          label: const Text('LINK'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF16A34A),
            side: const BorderSide(color: Color(0xFF16A34A), width: 1.0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: GoogleFonts.roboto(fontSize: 10, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
    return ElevatedButton.icon(
      onPressed: () => _openConsultation(apt),
      icon: const Icon(Icons.assignment_rounded, size: 12),
      label: const Text('CONSULT'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00D2C4),
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: GoogleFonts.roboto(fontSize: 10, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  // ===========================================================================
  // APPOINTMENTS TAB (full table)
  // ===========================================================================
  Widget _buildAppointmentsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _appointments.length + 2,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          // ── Appointments hero banner ──
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/branding/onboarding_4.png',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0F172A).withOpacity(0.8),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Appointment Management',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_appointments.length} total appointments • $_pendingCount pending approval',
                          style: GoogleFonts.roboto(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms);
        }
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF4F46E5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'All Appointments',
                  style: adminSans(weight: FontWeight.w800, size: 15),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_appointments.length}',
                    style: GoogleFonts.roboto(
                      color: Color(0xFF4F46E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final apt = _appointments[i - 2];
        return _appointmentCard(apt);
      },
    );
  }

  Widget _appointmentCard(Appointment apt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        apt.fullName,
                        style: adminSans(weight: FontWeight.w800, size: 15),
                      ),
                      if (apt.whoIsComing != null &&
                          apt.whoIsComing!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'For: ${apt.whoIsComing!.join(', ')}',
                            style: GoogleFonts.roboto(
                              color: const Color(0xFF4F46E5),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (apt.email != null)
                        Text(
                          apt.email!,
                          style: GoogleFonts.roboto(
                            color: const Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      if (apt.staffId != null)
                        Text(
                          'Staff No: ${apt.staffId}',
                          style: GoogleFonts.roboto(
                            color: const Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      if (apt.nationwideId != null)
                        Text(
                          'Nationwide: ${apt.nationwideId}',
                          style: GoogleFonts.roboto(
                            color: const Color(0xFF94A3B8),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                _badge(apt.status),
              ],
            ),
          ),

          // Info strip
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  _fmtDate(apt.preferredDate),
                  style: adminSans(size: 11, color: AdminPalette.mute),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.access_time_rounded,
                  size: 12,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  apt.preferredTime,
                  style: adminSans(size: 11, color: AdminPalette.mute),
                ),
                const SizedBox(width: 8),
                if (apt.doctorName != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      apt.doctorName!,
                      style: adminSans(
                        size: 11,
                        color: AdminPalette.mute,
                        weight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Service + priority badges
          if (apt.service != null || apt.priority != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (apt.service != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        apt.service!,
                        style: adminSans(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AdminPalette.mute,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  if (apt.priority == 'High')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            size: 10,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Priority',
                            style: GoogleFonts.roboto(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (apt.isTelemedicine)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 10,
                            color: Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Telehealth',
                            style: GoogleFonts.roboto(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF4F46E5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // Telemedicine link
          if (apt.isVideoConsult && apt.hasMeetingLink)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => _joinVideoConsult(apt),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.video_call_rounded,
                          color: Color(0xFF4F46E5),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Join Video Session',
                          style: GoogleFonts.roboto(
                            color: const Color(0xFF4F46E5),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_new_rounded,
                          color: Color(0xFF4F46E5),
                          size: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Actions row
          Padding(
            padding: const EdgeInsets.all(16),
            child: _appointmentActions(apt),
          ),
        ],
      ),
    ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _appointmentActions(Appointment apt) {
    final status = apt.status.toLowerCase();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Telemedicine: generate link or show JOIN button
        if (apt.isVideoConsult && !apt.hasMeetingLink)
          _actionBtn(
            'START ROOM',
            const Color(0xFF16A34A),
            () => _joinVideoConsult(apt),
            icon: Icons.add_link_rounded,
          ),
        if (apt.isVideoConsult && apt.hasMeetingLink)
          _actionBtn(
            'JOIN SESSION',
            const Color(0xFF4F46E5),
            () => _joinVideoConsult(apt),
            icon: Icons.video_call_rounded,
          ),

        // Consultation workspace
        _actionBtn(
          'Consult',
          const Color(0xFF4F46E5),
          () => _openConsultation(apt),
          icon: Icons.assignment_rounded,
        ),

        // Chat with patient
        _actionBtn(
          'Chat',
          const Color(0xFF00D2C4),
          () => _openChat(apt),
          icon: Icons.chat_bubble_rounded,
        ),

        // Prescription
        _actionBtn(
          'Prescription',
          const Color(0xFF2563EB),
          () => _openPrescription(apt),
          icon: Icons.description_rounded,
        ),

        // Status progression
        if (status == 'arrived')
          _actionBtn(
            'In Consultation',
            const Color(0xFF7C3AED),
            () => _updateStatus(apt, 'consulting'),
          ),
        if (status == 'consulting')
          _actionBtn(
            'Complete',
            const Color(0xFF16A34A),
            () => _updateStatus(apt, 'completed'),
          ),
      ],
    );
  }

  Widget _actionBtn(
    String label,
    Color color,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
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

  // ===========================================================================
  // QUEUE TAB
  // ===========================================================================
  Widget _buildQueueTab() {
    return DoctorQueueTab(
      appointments: _appointments,
      onJoinVideo: _joinVideoConsult,
      onOpenSoap: _openConsultation,
      onOpenChat: _openChat,
      onOpenRx: _openPrescription,
      onUpdateStatus: _updateStatus,
    );
  }

  // ===========================================================================
  // DOCTORS TAB
  // ===========================================================================
  Widget _buildDoctorsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _doctors.length + 2,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          // ── Doctors hero banner ──
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/branding/onboarding_3.png',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0F172A).withOpacity(0.8),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Doctor Profiles & Schedules',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_doctors.length} doctors registered',
                          style: GoogleFonts.roboto(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms);
        }
        if (i == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF4F46E5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'All Doctors',
                  style: adminSans(weight: FontWeight.w800, size: 15),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_doctors.length}',
                    style: GoogleFonts.roboto(
                      color: Color(0xFF4F46E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final doc = _doctors[i - 2];
        return _doctorProfileCard(doc);
      },
    );
  }

  Widget _doctorProfileCard(Map<String, dynamic> doc) {
    final active = doc['is_active'] == true || doc['is_active'] == 1;
    final initials = (doc['name']?.toString() ?? '?')
        .split(' ')
        .map((p) => p.isNotEmpty ? p[0] : '')
        .take(2)
        .join();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminGlass(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AdminPalette.gold.withValues(alpha: 0.18),
                child: Text(
                  initials,
                  style: adminSans(
                    color: AdminPalette.gold,
                    weight: FontWeight.w800,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc['name']?.toString() ?? '',
                      style: adminSans(weight: FontWeight.w800, size: 15),
                    ),
                    Text(
                      doc['specialization']?.toString() ?? '',
                      style: adminSans(color: AdminPalette.mute, size: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFFECACA),
                  ),
                ),
                child: Text(
                  active ? 'Active' : 'Inactive',
                  style: GoogleFonts.roboto(
                    color: active
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SLOT DURATION',
                        style: GoogleFonts.roboto(
                          color: Color(0xFF94A3B8),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '${doc['slot_duration']} mins',
                        style: adminSans(weight: FontWeight.w700, size: 14),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 30, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WORKING HOURS',
                          style: GoogleFonts.roboto(
                            color: Color(0xFF94A3B8),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${doc['start_time']?.toString().substring(0, 5) ?? '--'} – ${doc['end_time']?.toString().substring(0, 5) ?? '--'}',
                          style: adminSans(weight: FontWeight.w700, size: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ).animate().fadeIn(duration: 200.ms);
  }

  // ===========================================================================
  // REPORTS TAB
  // ===========================================================================
  Widget _buildReportsTab() {
    final trends = _stats['trends'] as List<dynamic>? ?? [];
    final noShow = _stats['noShow'] as Map<String, dynamic>? ?? {};
    final total =
        int.tryParse(_stats['stats']?['total']?.toString() ?? '0') ?? 0;
    final completed =
        int.tryParse(_stats['stats']?['completed']?.toString() ?? '0') ?? 0;
    final missed = int.tryParse(noShow['missed_total']?.toString() ?? '0') ?? 0;
    final repeated =
        int.tryParse(noShow['repeated_offenders']?.toString() ?? '0') ?? 0;
    final attendanceRate = total > 0 ? (completed / total) : 0.0;
    final noShowRate = total > 0 ? (missed / total) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reports & Analytics',
            style: adminSerif(size: 22, weight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // Trends bar chart
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Appointment Trends (Last 7 Days)'),
                const SizedBox(height: 16),
                AdminTrendChart(trends: trends),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Attendance Rate
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Patient Attendance Rate'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    AdminRingMetric(label: 'Rate', pct: attendanceRate.toDouble(), color: AdminPalette.gold),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _reportStatRow(
                            'Total Appointments',
                            '$total',
                            AdminPalette.cyan,
                          ),
                          _reportStatRow(
                            'Completed',
                            '$completed',
                            AdminPalette.lime,
                          ),
                          _reportStatRow(
                            'Pending',
                            '$_pendingCount',
                            AdminPalette.gold,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // No-show Analysis
          AdminGlass(
            glow: AdminPalette.rose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('No-Show Analysis'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AdminPalette.rose.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${(noShowRate * 100).toInt()}%',
                        style: adminSans(
                          color: AdminPalette.rose,
                          weight: FontWeight.w800,
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall No-Show Rate',
                          style: adminSans(weight: FontWeight.w700, size: 13),
                        ),
                        Text(
                          'Calculated from total appointments',
                          style: adminSans(color: AdminPalette.mute, size: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _noShowStatBox(
                        'Missed',
                        '$missed',
                        AdminPalette.rose,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _noShowStatBox(
                        'Repeat Offenders',
                        '$repeated',
                        AdminPalette.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _noShowStatBox(
                        'Restricted',
                        '0',
                        AdminPalette.mute,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noShowStatBox(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: adminSans(color: AdminPalette.mute, size: 9, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: adminSerif(weight: FontWeight.w700, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _reportStatRow(String label, String value, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: adminSans(color: AdminPalette.mute, size: 11),
              ),
            ],
          ),
          Text(
            value,
            style: adminSans(weight: FontWeight.w800, size: 13),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: adminSans(size: 11, weight: FontWeight.w800, color: AdminPalette.mute, letterSpacing: 1.2),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}
