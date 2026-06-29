import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/appointment.dart';
import 'consultation_dialog.dart';
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
  Map<String, dynamic> _stats = {
    'stats': {'total': 0, 'today': 0, 'pending': 0, 'completed': 0},
    'trends': [],
    'workload': [],
  };
  bool _loading = true;
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
      final aptsRaw = results[0].data as List<dynamic>? ?? [];
      final statsRaw = results[1].data as Map<String, dynamic>? ?? {};
      final docsRaw = results[2].data as List<dynamic>? ?? [];
      setState(() {
        _appointments = aptsRaw
            .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
            .toList();
        _stats = statsRaw;
        _doctors = docsRaw.map((j) => j as Map<String, dynamic>).toList();
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

  Future<void> _generateLink(Appointment apt) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/appointments/${apt.id}/generate-link',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meeting link generated & SMS sent!')),
        );
      _loadAll();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  void _openConsultation(Appointment apt) {
    showDialog(
      context: context,
      builder: (ctx) => ConsultationDialog(appointment: apt),
    ).then((_) => _loadAll());
  }

  void _openPrescription(Appointment apt) {
    showDialog(
      context: context,
      builder: (ctx) => PrescriptionDialog(appointment: apt),
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(session, isDesktop),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF4F46E5),
                      ),
                    )
                  : _error != null
                  ? _buildError()
                  : _buildContent(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !isDesktop ? _buildBottomNav() : null,
    );
  }

  Widget _headerTabItem(String label, _DoctorTab tab, IconData icon) {
    final active = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4F46E5).withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.roboto(
                color: active ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
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

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: isDesktop
          ? Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                    border: Border.all(
                      color: const Color(0xFF4F46E5).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: Color(0xFF4F46E5),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Digi Health',
                      style: GoogleFonts.roboto(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Doctor Portal',
                      style: GoogleFonts.roboto(
                        color: Color(0xFF64748B),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 20),
                Expanded(
                  child: Row(
                    children: [
                      _headerTabItem('Dashboard', _DoctorTab.overview, Icons.dashboard_rounded),
                      _headerTabItem('Appointments', _DoctorTab.appointments, Icons.calendar_month_rounded),
                      _headerTabItem('Queue', _DoctorTab.queue, Icons.queue_rounded),
                      _headerTabItem('Doctors', _DoctorTab.doctors, Icons.people_alt_rounded),
                      _headerTabItem('Reports', _DoctorTab.reports, Icons.bar_chart_rounded),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
                  onPressed: _loadAll,
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFEEF2FF),
                      child: Text(
                        (session.user?.name ?? 'D')[0].toUpperCase(),
                        style: GoogleFonts.roboto(
                          color: Color(0xFF4F46E5),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.user?.name ?? 'Doctor',
                      style: GoogleFonts.roboto(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 16, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Logout',
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await session.clear();
                    if (mounted) context.go('/login');
                  },
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                    border: Border.all(
                      color: const Color(0xFF4F46E5).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: Color(0xFF4F46E5),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tabLabels[_tab]!,
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
                  onPressed: _loadAll,
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFEEF2FF),
                  child: Text(
                    (session.user?.name ?? 'D')[0].toUpperCase(),
                    style: GoogleFonts.roboto(
                      color: Color(0xFF4F46E5),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                  onPressed: () async {
                    await session.clear();
                    if (mounted) context.go('/login');
                  },
                ),
              ],
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.map((item) {
              final active = _tab == item.$1;
              return GestureDetector(
                onTap: () => setState(() => _tab = item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF4F46E5).withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$2,
                        size: 20,
                        color: active ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: GoogleFonts.roboto(
                          fontSize: 9,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: active ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25), width: 1.2),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image (faded texture)
              if (backgroundImage != null)
                Image.asset(backgroundImage, fit: BoxFit.cover),

              // Light overlay — image shows through with a bright wash
              Container(
                color: backgroundImage != null
                    ? Colors.white.withOpacity(0.15)
                    : color.withOpacity(0.06),
              ),

              // Foreground content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.20),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.roboto(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.roboto(
                        color: color.withOpacity(0.80),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFF4F46E5),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Failed to load data',
              style: GoogleFonts.roboto(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again',
              style: GoogleFonts.roboto(
                color: const Color(0xFF64748B),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 4,
                shadowColor: const Color(0xFF4F46E5).withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // OVERVIEW TAB
  // ===========================================================================
  Widget _buildOverview() {
    final activeConsult = _appointments.cast<Appointment?>().firstWhere(
      (a) => a != null && a.status == 'consulting' && a.isTelemedicine,
      orElse: () => null,
    );
    final trends = _stats['trends'] as List<dynamic>? ?? [];
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
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
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
                          const Color(0xFF0F172A).withOpacity(0.95),
                          const Color(0xFF4F46E5).withOpacity(0.45),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$greeting,',
                          style: GoogleFonts.roboto(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (session.user?.name != null)
                              ? (session.user!.name.toLowerCase().startsWith('dr.')
                                  ? session.user!.name
                                  : 'Dr. ${session.user!.name}')
                              : 'Doctor',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF00D2C4), size: 12),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_todayCount appointments today',
                                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              if (!isMobile)
                                Container(
                                  width: 1,
                                  height: 16,
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 12),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$_pendingCount pending',
                                    style: GoogleFonts.roboto(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                              if (activeConsult.isTelemedicine)
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: activeConsult.meetingLink != null
                                        ? () => _launchUrl(
                                            activeConsult.meetingLink!,
                                          )
                                        : () => _generateLink(activeConsult),
                                    icon: Icon(
                                      activeConsult.meetingLink != null
                                          ? Icons.videocam_rounded
                                          : Icons.add_link_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      activeConsult.meetingLink != null
                                          ? 'JOIN ROOM'
                                          : 'LINK SMS',
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
                              if (activeConsult.isTelemedicine)
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
                .fadeIn(duration: 400.ms).slideY(begin: -0.1),
              ),
            ),

          // ── Quick Actions Grid ──────────────────────────────────────────────
          _sectionHeader('Quick Actions'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: isMobile ? 2 : 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isMobile ? 1.5 : 2.0,
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
            childAspectRatio: isMobile ? 0.95 : 1.15,
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.02),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _getLiveAppointmentsList().isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'No live appointments scheduled for today',
                          style: GoogleFonts.roboto(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _getLiveAppointmentsList().length,
                      separatorBuilder: (context, index) => const Divider(
                        color: Color(0xFFF1F5F9),
                        height: 1,
                        thickness: 1,
                      ),
                      itemBuilder: (context, index) {
                        final apt = _getLiveAppointmentsList()[index];
                        return _liveRow(apt);
                      },
                    ),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
          const SizedBox(height: 20),

          // ── Doctor Workload ────────────────────────────────────────────────
          if (workload.isNotEmpty) ...[
            _sectionHeader('Doctor Workload (Today)'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: workload.map((w) {
                  final name = w['name']?.toString() ?? '';
                  final count =
                      int.tryParse(w['count']?.toString() ?? '0') ?? 0;
                  final pct = (count / 20.0).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.roboto(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '$count Patients',
                              style: GoogleFonts.roboto(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF4F46E5),
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    Widget? trendWidget;
    if (label.toLowerCase().contains("today")) {
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.trending_up_rounded,
            color: Color(0xFF16A34A),
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            'Active schedule',
            style: GoogleFonts.roboto(
              color: const Color(0xFF16A34A),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else if (label.toLowerCase().contains("pending")) {
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notification_important_rounded,
            color: Color(0xFFD97706),
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            'Needs review',
            style: GoogleFonts.roboto(
              color: const Color(0xFFD97706),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else if (label.toLowerCase().contains("completed")) {
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.task_alt_rounded,
            color: Color(0xFF16A34A),
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            'Finished today',
            style: GoogleFonts.roboto(
              color: const Color(0xFF16A34A),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else {
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.show_chart_rounded,
            color: Color(0xFF4F46E5),
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            '+8% this week',
            style: GoogleFonts.roboto(
              color: const Color(0xFF4F46E5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    final cardPadding = isMobile ? 12.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Icon Container and a small indicator dot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: isMobile ? 38 : 44,
                height: isMobile ? 38 : 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: accent, size: isMobile ? 18 : 20),
              ),
              // Small status dot indicator
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Value
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.roboto(
              color: const Color(0xFF0F172A),
              fontSize: isMobile ? 26 : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 2),
          // Label
          Text(
            label,
            style: GoogleFonts.roboto(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (trendWidget != null) ...[
            const SizedBox(height: 6),
            // Trend badge at the bottom
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: bg.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: trendWidget,
            ),
          ],
        ],
      ),
    );
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
                  backgroundColor: const Color(0xFFEEF2FF),
                  child: Text(
                    _getInitials(apt.fullName),
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF4F46E5),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: const Color(0xFF0F172A),
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
                        style: GoogleFonts.roboto(
                          color: const Color(0xFF475569),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
    if (apt.isTelemedicine) {
      if (apt.meetingLink != null) {
        return ElevatedButton.icon(
          onPressed: () => _launchUrl(apt.meetingLink!),
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
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                  ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
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
                        style: GoogleFonts.roboto(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
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
              color: const Color(0xFFF8FAFC),
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
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    color: const Color(0xFF475569),
                  ),
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
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(width: 8),
                if (apt.doctorName != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      apt.doctorName!,
                      style: GoogleFonts.roboto(
                        fontSize: 11,
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w600,
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
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        apt.service!,
                        style: GoogleFonts.roboto(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF475569),
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
          if (apt.isTelemedicine && apt.meetingLink != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => _launchUrl(apt.meetingLink!),
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
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _appointmentActions(Appointment apt) {
    final status = apt.status.toLowerCase();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Telemedicine: generate link or show JOIN button
        if (apt.isTelemedicine && apt.meetingLink == null)
          _actionBtn(
            'Generate Link',
            const Color(0xFF16A34A),
            () => _generateLink(apt),
            icon: Icons.add_link_rounded,
          ),
        if (apt.isTelemedicine && apt.meetingLink != null)
          _actionBtn(
            'JOIN SESSION',
            const Color(0xFF4F46E5),
            () => _launchUrl(apt.meetingLink!),
            icon: Icons.video_call_rounded,
          ),

        // Consultation workspace
        _actionBtn(
          'Consult',
          const Color(0xFF4F46E5),
          () => _openConsultation(apt),
          icon: Icons.assignment_rounded,
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
    final queue = _appointments
        .where(
          (a) => [
            'approved',
            'arrived',
            'waiting',
            'consulting',
          ].contains(a.status.toLowerCase()),
        )
        .toList();

    return queue.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 200,
                  height: 140,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/branding/onboarding_2.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const Icon(
                  Icons.hourglass_empty_rounded,
                  color: Color(0xFFCBD5E1),
                  size: 48,
                ),
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
                  'Patients will appear here once they check in',
                  style: GoogleFonts.roboto(color: Color(0xFFCBD5E1), fontSize: 12),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: queue.length + 2,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                // ── Queue hero banner ──
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
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
                          'assets/branding/onboarding_2.png',
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
                                'Queue & Check-In',
                                style: GoogleFonts.roboto(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${queue.length} patients currently in queue',
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.queue_rounded,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Current Queue',
                        style: GoogleFonts.roboto(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.people_rounded,
                              size: 12,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${queue.length} Waiting',
                              style: GoogleFonts.roboto(
                                color: Color(0xFF2563EB),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              final apt = queue[i - 2];
              return _queueCard(i - 1, apt);
            },
          );
  }

  Widget _queueCard(int idx, Appointment apt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Queue number
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$idx',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Patient info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  apt.fullName,
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                if (apt.whoIsComing != null && apt.whoIsComing!.isNotEmpty)
                  Text(
                    'For: ${apt.whoIsComing!.join(', ')}',
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF4F46E5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (apt.staffId != null)
                  Text(
                    'Staff No: ${apt.staffId}',
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF64748B),
                      fontSize: 10,
                    ),
                  ),
                if (apt.nationwideId != null)
                  Text(
                    'Nationwide: ${apt.nationwideId}',
                    style: GoogleFonts.roboto(
                      color: const Color(0xFF94A3B8),
                      fontSize: 9,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Time: ${apt.preferredTime}',
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF475569),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status + actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _badge(apt.status),
              const SizedBox(height: 8),
              _queueActions(apt),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _queueActions(Appointment apt) {
    final s = apt.status.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Telemedicine session buttons
        if (apt.isTelemedicine) ...[
          if (apt.meetingLink != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _actionBtn(
                'JOIN SESSION',
                const Color(0xFF4F46E5),
                () => _launchUrl(apt.meetingLink!),
                icon: Icons.video_call_rounded,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _actionBtn(
                'Generate Link',
                const Color(0xFF16A34A),
                () => _generateLink(apt),
                icon: Icons.add_link_rounded,
              ),
            ),
        ],
        // Status actions
        if (s == 'arrived')
          _actionBtn(
            'In Consultation',
            const Color(0xFF7C3AED),
            () => _updateStatus(apt, 'consulting'),
          ),
        if (s == 'consulting') ...[
          _actionBtn(
            '📋 Consult',
            const Color(0xFF4F46E5),
            () => _openConsultation(apt),
          ),
          const SizedBox(height: 4),
          _actionBtn(
            'Complete',
            const Color(0xFF16A34A),
            () => _updateStatus(apt, 'completed'),
          ),
        ],
      ],
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
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                  ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFEEF2FF),
                child: Text(
                  initials,
                  style: GoogleFonts.roboto(
                    color: Color(0xFF4F46E5),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
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
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      doc['specialization']?.toString() ?? '',
                      style: GoogleFonts.roboto(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
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
              color: const Color(0xFFF8FAFC),
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
                        style: GoogleFonts.roboto(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
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
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
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
    final maxTrend = trends.isEmpty
        ? 1.0
        : trends
              .map((t) => double.tryParse(t['count']?.toString() ?? '0') ?? 0.0)
              .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reports & Analytics',
            style: GoogleFonts.roboto(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),

          // Trends bar chart
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Appointment Trends (Last 7 Days)'),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: trends.isEmpty
                        ? [
                            Expanded(
                              child: Center(
                                child: Text(
                                  'No data',
                                  style: GoogleFonts.roboto(color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                          ]
                        : trends.map<Widget>((t) {
                            final count =
                                double.tryParse(
                                  t['count']?.toString() ?? '0',
                                ) ??
                                0.0;
                            final h = maxTrend > 0 ? (count / maxTrend) : 0.0;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${count.toInt()}',
                                      style: GoogleFonts.roboto(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 9,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: (h * 100).clamp(6.0, 100.0),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF4F46E5),
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(6),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      t['day']?.toString().toUpperCase() ?? '',
                                      style: GoogleFonts.roboto(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Attendance Rate
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Patient Attendance Rate'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: 1,
                            strokeWidth: 12,
                            color: const Color(0xFFF1F5F9),
                          ),
                          CircularProgressIndicator(
                            value: attendanceRate.toDouble(),
                            strokeWidth: 12,
                            color: const Color(0xFF4F46E5),
                            backgroundColor: Colors.transparent,
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${(attendanceRate * 100).toInt()}%',
                                style: GoogleFonts.roboto(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Rate',
                                style: GoogleFonts.roboto(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          _reportStatRow(
                            'Total Appointments',
                            '$total',
                            const Color(0xFF4F46E5),
                          ),
                          _reportStatRow(
                            'Completed',
                            '$completed',
                            const Color(0xFF16A34A),
                          ),
                          _reportStatRow(
                            'Pending',
                            '$_pendingCount',
                            const Color(0xFFD97706),
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
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
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${(noShowRate * 100).toInt()}%',
                        style: GoogleFonts.roboto(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall No-Show Rate',
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Calculated from total appointments',
                          style: GoogleFonts.roboto(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
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
                        const Color(0xFFFEF2F2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _noShowStatBox(
                        'Repeat Offenders',
                        '$repeated',
                        const Color(0xFFFFF7ED),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _noShowStatBox(
                        'Restricted',
                        '0',
                        const Color(0xFFF8FAFC),
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

  Widget _noShowStatBox(String label, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.roboto(
              color: Color(0xFF64748B),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 20),
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
                style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.roboto(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.roboto(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}
