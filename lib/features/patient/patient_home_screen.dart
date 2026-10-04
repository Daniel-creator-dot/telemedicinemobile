import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/notification_service.dart';
import '../admin/admin_chrome.dart';
import '../consult/open_video_consult.dart';
import 'appointments_repository.dart';
import 'book_appointment_dialog.dart';
import 'care_repository.dart';
import 'chat_screen.dart';
import 'pay_visit.dart';
import '../../models/appointment.dart';
import '../../models/doctor_profile.dart';
import '../../models/prescription.dart';
import '../../models/consultation.dart';
import '../../shared/widgets/clinical_ui.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  int _unreadChats = 0;
  Timer? _chatBadgeTimer;

  final List<Widget> _screens = [
    const DashboardView(),
    const AppointmentsView(),
    const MessagesView(),
    const ProfileView(),
  ];

  @override
  void initState() {
    super.initState();
    _refreshChatBadge();
    _chatBadgeTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _refreshChatBadge();
    });
  }

  @override
  void dispose() {
    _chatBadgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshChatBadge() async {
    try {
      final count = await context.read<CareRepository>().unreadChatCount();
      if (mounted) setState(() => _unreadChats = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final home = _currentIndex == 0;
    return Scaffold(
      backgroundColor: home ? digiPaper : AdminPalette.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: home
              ? SafeArea(child: _screens[0])
              : AdminMeshBackdrop(
                  child: SafeArea(child: _screens[_currentIndex]),
                ),
        ),
      ),
      bottomNavigationBar: _PatientNav(
        index: _currentIndex,
        unreadChats: _unreadChats,
        onSelect: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) _refreshChatBadge();
        },
      ),
    );
  }
}

// ==================== DASHBOARD VIEW ====================
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  List<DoctorProfile> _doctors = [];
  Appointment? _nextAppointment;
  List<Prescription>? _scripts;
  List<Map<String, dynamic>> _activeCare = [];
  int _openCareCount = 0;
  bool _loading = true;
  String? _loadError;
  int _unreadNotifications = 0;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _refreshUnreadCount();
    _presenceTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      _refreshPresence();
      _refreshUnreadCount();
    });
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final count = await context.read<CareRepository>().unreadNotificationCount();
      if (mounted) setState(() => _unreadNotifications = count);
    } catch (_) {}
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPresence() async {
    if (_doctors.isEmpty) return;
    try {
      final presence = await context.read<CareRepository>().getDoctorPresence();
      if (!mounted || presence.isEmpty) return;
      setState(() {
        _doctors = _doctors.map((d) {
          final online = presence[d.id];
          return online == null ? d : d.copyWith(isOnline: online);
        }).toList()
          ..sort((a, b) {
            if (a.isOnline == b.isOnline) return a.name.compareTo(b.name);
            return a.isOnline ? -1 : 1;
          });
      });
    } catch (_) {}
  }

  Future<void> _openMeeting(Appointment apt) async {
    await openVideoConsult(context, apt);
  }

  Future<void> _openBook(DoctorProfile doc) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BookAppointmentDialog(
        preselectedDoctorId: doc.id,
        preselectedDoctorName: doc.name,
        preselectedSpecialty: doc.specialization,
      ),
    );
    if (mounted) await _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final aptRepo = context.read<AppointmentsRepository>();
      final care = context.read<CareRepository>();
      final docs = await care.getDirectory();
      final myApts = await aptRepo.getMyAppointments();
      List<Map<String, dynamic>> activeCare = [];
      var openCareCount = 0;
      try {
        final journey = await care.healthJourney();
        activeCare = ((journey['active'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        openCareCount = journey['open_count'] is int
            ? journey['open_count'] as int
            : int.tryParse(journey['open_count']?.toString() ?? '') ?? activeCare.length;
      } catch (_) {}

      List<Prescription>? scripts;
      var scriptsLoaded = false;
      try {
        scripts = await aptRepo.getMyPrescriptions();
        scriptsLoaded = true;
      } catch (_) {}

      // Get the next scheduled approved/pending appointment
      final upcoming = myApts
          .where((a) =>
              a.status == 'pending' ||
              a.status == 'approved' ||
              a.status == 'queued' ||
              a.status == 'consulting')
          .toList();

      // Schedule notifications for upcoming telemedicine appointments
      final notificationService = NotificationService();
      await notificationService.scheduleAppointmentReminders(upcoming);

      if (!mounted) return;
      setState(() {
        _doctors = docs;
        _activeCare = activeCare;
        _openCareCount = openCareCount;
        if (upcoming.isNotEmpty) {
          _nextAppointment = upcoming.first;
        } else {
          _nextAppointment = null;
        }
        if (scriptsLoaded) _scripts = scripts;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_doctors.isEmpty && _nextAppointment == null) {
          _loadError = 'We could not open your home. Check the connection and try again.';
        }
      });
    }
  }

  int? get _readyPickupCount {
    final scripts = _scripts;
    if (scripts == null) return null;
    return scripts.where((p) => (p.dispenseStatus ?? '').toLowerCase() == 'ready').length;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _initials(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return 'H';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  void _openDesk() {
    context.push('/patient/prescriptions').then((_) {
      if (mounted) _loadDashboardData();
    });
  }

  void _openConsult() {
    context.push('/patient/consult-now').then((_) {
      if (mounted) _loadDashboardData();
    });
  }

  void _bookVisit() {
    showDialog<void>(
      context: context,
      builder: (_) => const BookAppointmentDialog(),
    ).then((_) {
      if (mounted) _loadDashboardData();
    });
  }

  String _visitStatus(String status) {
    switch (status) {
      case 'approved':
        return 'Confirmed';
      case 'pending':
        return 'Pending';
      case 'queued':
        return 'In queue';
      case 'consulting':
        return 'In consult';
      default:
        return 'Scheduled';
    }
  }

  String _visitLine(Appointment apt) {
    final who = (apt.doctorName ?? '').trim();
    final when = [apt.preferredDate, _clock(apt.preferredTime)].where((part) => part.trim().isNotEmpty).join(' · ');
    if (who.isNotEmpty && when.isNotEmpty) return '$who · $when';
    if (when.isNotEmpty) return when;
    if (who.isNotEmpty) return who;
    final service = (apt.service ?? '').trim();
    if (service.isNotEmpty) return service;
    return 'Upcoming visit';
  }

  String _clock(String raw) {
    final match = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(raw.trim());
    return match?.group(1) ?? raw.trim();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final firstLoad = _loading && _doctors.isEmpty && _nextAppointment == null && _loadError == null;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: digiForest,
      child: firstLoad
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 24, wide ? 32 : 20, 32),
              children: const [
                ClinicalSkeleton(lines: 3),
                SizedBox(height: 24),
                ClinicalCardSkeleton(),
                SizedBox(height: 12),
                ClinicalCardSkeleton(),
              ],
            )
          : _loadError != null && _doctors.isEmpty && _nextAppointment == null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 420,
                      child: ClinicalErrorState(message: _loadError!, onRetry: _loadDashboardData),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 16, wide ? 32 : 20, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: clinicalMaxWidth),
                        child: _home(session, wide),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _home(Session session, bool wide) {
    final story = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _todayCard(),
        if (_openCareCount > 0) ...[
          const SizedBox(height: 16),
          _activeCareCard(),
        ],
        const SizedBox(height: 24),
        _clinicians(),
        const SizedBox(height: 24),
        _record(),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(session),
        const SizedBox(height: 16),
        _searchField(),
        const SizedBox(height: 20),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: story),
              const SizedBox(width: 24),
              SizedBox(width: 320, child: _actions()),
            ],
          )
        else ...[
          _actions(),
          const SizedBox(height: 16),
          story,
        ],
      ],
    );
  }

  Widget _header(Session session) {
    final name = session.user?.name.trim().isNotEmpty == true ? session.user!.name.trim() : 'Patient';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate)),
              const SizedBox(height: 4),
              Text(name, style: clinicalDisplay(32, letterSpacing: -0.8)),
              const SizedBox(height: 8),
              Text(
                'Visits, prescriptions, and the rest of your chart.',
                style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.4),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await context.push('/patient/notifications');
            if (mounted) await _refreshUnreadCount();
          },
          icon: Badge(
            isLabelVisible: _unreadNotifications > 0,
            label: Text('$_unreadNotifications'),
            backgroundColor: digiForest,
            child: const Icon(Icons.notifications_none_rounded, color: digiInk),
          ),
        ),
        const SizedBox(width: 4),
        CircleAvatar(
          radius: 22,
          backgroundColor: digiForest.withValues(alpha: 0.08),
          child: Text(
            _initials(name),
            style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: digiForest),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms);
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: digiLine),
        boxShadow: clinicalShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(clinicalRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(clinicalRadius),
          onTap: () => context.push('/patient/doctors'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: digiSlate, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search clinicians',
                    style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Book care', style: clinicalDisplay(20)),
          const SizedBox(height: 6),
          Text(
            'A visit, a live consult, or the prescription desk.',
            style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4),
          ),
          const SizedBox(height: 16),
          ClinicalPrimaryButton(label: 'Book a visit', onPressed: _bookVisit),
          const SizedBox(height: 8),
          ClinicalSecondaryButton(label: 'Start a consult', onPressed: _openConsult),
          const SizedBox(height: 4),
          _quietAction('Prescription desk', Icons.medication_outlined, _openDesk),
          _quietAction('Live queue', Icons.queue_outlined, _openConsult),
        ],
      ),
    );
  }

  Widget _quietAction(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: digiForest),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: digiInk)),
            ),
            const Icon(Icons.chevron_right, size: 18, color: digiSlate),
          ],
        ),
      ),
    );
  }

  Widget _todayCard() {
    final visit = _nextAppointment;
    final ready = _readyPickupCount;
    final showReady = ready != null && ready > 0;
    final canJoin = visit != null &&
        visit.isTelemedicine &&
        (visit.status == 'approved' || visit.status == 'consulting' || visit.status == 'queued') &&
        visit.meetingLink != null;

    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today',
            style: clinicalDisplay(20),
          ),
          const SizedBox(height: 8),
          if (visit == null && !showReady)
            Text(
              'Nothing on the book today. Book a visit when you need one.',
              style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.45),
            ),
          if (visit != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next visit',
                    style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiForest),
                  ),
                ),
                ClinicalStatusPill(
                  label: _visitStatus(visit.status),
                  tone: visit.status == 'pending' ? ClinicalTone.gold : ClinicalTone.forest,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_visitLine(visit), style: GoogleFonts.dmSans(fontSize: 14, color: digiInk, height: 1.4)),
          ],
          if (showReady) ...[
            const SizedBox(height: 12),
            const ClinicalStatusPill(label: 'Ready', tone: ClinicalTone.forest),
            const SizedBox(height: 8),
            Text(
              ready == 1 ? '1 prescription is ready for pickup.' : '$ready prescriptions are ready for pickup.',
              style: GoogleFonts.dmSans(fontSize: 14, color: digiInk, height: 1.4),
            ),
          ],
          if (canJoin) ...[
            const SizedBox(height: 16),
            ClinicalPrimaryButton(label: 'Join consult', onPressed: () => _openMeeting(visit)),
          ],
          TextButton(
            onPressed: _openDesk,
            style: TextButton.styleFrom(
              foregroundColor: digiForest,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
            ),
            child: Text(
              'Open prescription desk',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: digiForest),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeCareCard() {
    return DigiCard(
      onTap: () => context.push('/patient/journey'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Care in progress',
                  style: clinicalDisplay(20),
                ),
              ),
              ClinicalStatusPill(
                label: '$_openCareCount open',
                tone: ClinicalTone.gold,
              ),
            ],
          ),
          if (_activeCare.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._activeCare.take(3).map((e) {
              final title = e['title']?.toString() ?? 'Care item';
              final partner = e['partner_name']?.toString();
              final label = e['status_label']?.toString() ?? e['status']?.toString() ?? '';
              final line = (partner != null && partner.isNotEmpty) ? '$title · $partner · $label' : '$title · $label';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
          Text('Open health journey', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: digiForest)),
        ],
      ),
    );
  }

  Widget _clinicians() {
    final shown = _doctors.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Clinicians',
                style: clinicalDisplay(20),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/patient/doctors'),
              child: Text('See all', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: digiForest)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading && _doctors.isEmpty)
          const ClinicalCardSkeleton()
        else if (_doctors.isEmpty)
          DigiCard(
            child: Text(
              'No clinicians are listed yet.',
              style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.4),
            ),
          )
        else
          DigiCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: digiLine),
                  _clinicianRow(shown[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _clinicianRow(DoctorProfile doc) {
    final specialty = doc.specialization?.trim().isNotEmpty == true ? doc.specialization! : 'Clinician';
    final fee = doc.consultationFee == null ? 'Book' : 'GHS ${doc.consultationFee!.toStringAsFixed(0)}';
    return InkWell(
      onTap: () => _openBook(doc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: digiForest.withValues(alpha: 0.08),
              child: Text(
                _initials(doc.name),
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiForest),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: digiInk),
                  ),
                  Text(specialty, style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fee, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: digiInk)),
                if (doc.isOnline) ...[
                  const SizedBox(height: 4),
                  const ClinicalStatusPill(label: 'On duty', tone: ClinicalTone.forest),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _record() {
    const treatment = <(String, IconData, String, bool)>[
      ('Prescriptions', Icons.medication_outlined, '/patient/prescriptions', true),
      ('Care phases', Icons.account_tree_outlined, '/patient/phases', false),
      ('Health journey', Icons.timeline, '/patient/journey', false),
      ('Records vault', Icons.folder_shared_outlined, '/patient/records', false),
      ('Health tracker', Icons.monitor_heart_outlined, '/patient/tracker', false),
      ('Follow-up', Icons.event_available_outlined, '/patient/followups', false),
    ];
    const find = <(String, IconData, String, bool)>[
      ('Find a doctor', Icons.medical_services_outlined, '/patient/doctors', false),
      ('Ghana network', Icons.map_outlined, '/patient/network', false),
      ('Symptom helper', Icons.psychology_outlined, '/patient/symptom-helper', false),
      ('Care programs', Icons.favorite_outline, '/patient/programs', false),
    ];
    const account = <(String, IconData, String, bool)>[
      ('Family', Icons.family_restroom, '/patient/family', false),
      ('Payments', Icons.receipt_long_outlined, '/patient/payments', false),
      ('Insurance cover', Icons.health_and_safety_outlined, '/patient/coverage', false),
      ('Membership', Icons.workspace_premium_outlined, '/patient/membership', false),
      ('Help', Icons.support_agent_outlined, '/patient/support', false),
      ('Edit profile', Icons.edit_outlined, '/patient/edit-profile', false),
      ('Consents', Icons.verified_user_outlined, '/patient/consents', false),
      ('Medical profile', Icons.badge_outlined, '/patient/profile', false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your record',
          style: clinicalDisplay(20),
        ),
        const SizedBox(height: 6),
        Text(
          'The rest of the chart, in one list.',
          style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate, height: 1.4),
        ),
        const SizedBox(height: 12),
        _linkGroup('Treatment', treatment),
        const SizedBox(height: 12),
        _linkGroup('Find care', find),
        const SizedBox(height: 12),
        _linkGroup('Account', account),
      ],
    );
  }

  Widget _linkGroup(String title, List<(String, IconData, String, bool)> links) {
    return DigiCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(title, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiSlate)),
          ),
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: digiLine),
            _linkRow(links[i]),
          ],
        ],
      ),
    );
  }

  Widget _linkRow((String, IconData, String, bool) link) {
    return InkWell(
      onTap: () {
        final future = context.push(link.$3);
        if (link.$4) {
          future.then((_) {
            if (mounted) _loadDashboardData();
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(link.$2, size: 18, color: digiForest),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                link.$1,
                style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: digiInk),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: digiSlate),
          ],
        ),
      ),
    );
  }
}

// ==================== APPOINTMENTS VIEW ====================
class AppointmentsView extends StatefulWidget {
  const AppointmentsView({super.key});

  @override
  State<AppointmentsView> createState() => _AppointmentsViewState();
}

class _AppointmentsViewState extends State<AppointmentsView> {
  int _activeTab = 0; // 0: Upcoming, 1: Past, 2: Calendar
  DateTime _calendarMonth = DateTime.now();
  List<Appointment> _appointments = [];
  Map<String, dynamic> _eligibility = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAppointments();
  }

  Future<void> _fetchAppointments() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<AppointmentsRepository>();
      final list = await repo.getMyAppointments();
      Map<String, dynamic> elig = {};
      try {
        elig = await context.read<CareRepository>().eligibility();
      } catch (_) {}
      
      // Schedule notifications for telemedicine appointments
      final notificationService = NotificationService();
      await notificationService.scheduleAppointmentReminders(list);
      
      setState(() {
        _appointments = list;
        _eligibility = elig;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _bookAppointment() {
    showDialog(
      context: context,
      builder: (context) => const BookAppointmentDialog(),
    ).then((val) {
      if (val != null) {
        _fetchAppointments();
      }
    });
  }

  Future<void> _payCopay(Appointment apt) async {
    final result = await payVisitWithPaystack(context, appointmentId: apt.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) _fetchAppointments();
  }

  // Helper: get the set of date strings ('yyyy-MM-dd') that have appointments in the current month
  Set<String> _appointmentDatesInMonth(DateTime month) {
    final result = <String>{};
    for (final apt in _appointments) {
      try {
        // preferredDate may be 'YYYY-MM-DD' or 'Month DD, YYYY'
        DateTime? d = _parseDate(apt.preferredDate);
        if (d != null && d.year == month.year && d.month == month.month) {
          result.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        }
      } catch (_) {}
    }
    return result;
  }

  DateTime? _parseDate(String raw) {
    // Try ISO format first
    try {
      return DateTime.parse(raw.split('T').first);
    } catch (_) {}
    // Try 'Month DD, YYYY'
    final months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final parts = raw.replaceAll(',', '').split(' ');
    if (parts.length == 3) {
      final mi = months.indexWhere((m) => m.toLowerCase() == parts[0].toLowerCase());
      if (mi != -1) {
        return DateTime(int.parse(parts[2]), mi + 1, int.parse(parts[1]));
      }
    }
    return null;
  }

  List<Appointment> _appointmentsForDay(DateTime day) {
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _appointments.where((apt) {
      final d = _parseDate(apt.preferredDate);
      if (d == null) return false;
      final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return dKey == key;
    }).toList();
  }

  void _showDayAppointments(BuildContext context, DateTime day, List<Appointment> apts) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_monthName(day.month)} ${day.day}, ${day.year}',
              style: adminSerif(size: 18, weight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ...apts.map((apt) {
              Color sc;
              switch (apt.status) {
                case 'approved': sc = const Color(0xFF22C55E); break;
                case 'completed': sc = const Color(0xFF00D2C4); break;
                case 'cancelled': sc = Colors.redAccent; break;
                default: sc = const Color(0xFFFBBF24);
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      apt.isTelemedicine ? Icons.videocam_rounded : Icons.local_hospital_rounded,
                      color: theme.colorScheme.primary, size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(apt.doctorName ?? 'Consultation', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(apt.preferredTime, style: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sc.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(apt.status.toUpperCase(), style: GoogleFonts.roboto(color: sc, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) {
    const names = ['', 'January','February','March','April','May','June','July','August','September','October','November','December'];
    return names[m];
  }

  Widget _buildCalendarTab(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = _calendarMonth;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: 1=Mon ... 7=Sun. We want Sun=0 offset
    int startOffset = firstDay.weekday % 7; // Sun=0, Mon=1 ... Sat=6
    final aptDates = _appointmentDatesInMonth(month);
    final dayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      children: [
        // Month navigation header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => setState(() {
                _calendarMonth = DateTime(month.year, month.month - 1);
              }),
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54),
            ),
            Text(
              '${_monthName(month.month)} ${month.year}',
              style: adminSerif(size: 18, weight: FontWeight.w700),
            ),
            IconButton(
              onPressed: () => setState(() {
                _calendarMonth = DateTime(month.year, month.month + 1);
              }),
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Day of week headers
        Row(
          children: dayLabels.map((label) => Expanded(
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemCount: startOffset + daysInMonth,
          itemBuilder: (ctx, i) {
            if (i < startOffset) return const SizedBox();
            final day = i - startOffset + 1;
            final date = DateTime(month.year, month.month, day);
            final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final hasApt = aptDates.contains(key);
            final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

            return GestureDetector(
              onTap: hasApt ? () {
                _showDayAppointments(context, date, _appointmentsForDay(date));
              } : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.colorScheme.primary.withOpacity(0.18)
                      : hasApt
                          ? theme.colorScheme.secondary.withOpacity(0.15)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday
                      ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                      : hasApt
                          ? Border.all(color: theme.colorScheme.secondary.withOpacity(0.4), width: 1)
                          : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '$day',
                      style: GoogleFonts.roboto(
                        color: isToday
                            ? theme.colorScheme.primary
                            : hasApt
                                ? const Color(0xFFC084FC)
                                : const Color(0xFF94A3B8),
                        fontWeight: (isToday || hasApt) ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    if (hasApt)
                      Positioned(
                        bottom: 3,
                        child: Container(
                          width: 4, height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _calLegend(theme.colorScheme.primary, 'Today'),
            const SizedBox(width: 20),
            _calLegend(theme.colorScheme.secondary, 'Has Appointment'),
          ],
        ),
        const SizedBox(height: 16),
        if (aptDates.isEmpty)
          Text('No appointments this month.', style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13))
        else
          Text(
            'Tap a purple day to see details',
            style: GoogleFonts.roboto(color: Colors.white.withOpacity(0.3), fontSize: 11),
          ),
      ],
    );
  }

  Widget _calLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = _appointments.where((a) => a.status == 'pending' || a.status == 'approved' || a.status == 'queued' || a.status == 'consulting' || a.status == 'arrived').toList();
    final past = _appointments.where((a) => a.status == 'completed' || a.status == 'cancelled').toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Schedule Planner',
                style: adminSerif(size: 26, weight: FontWeight.w700, letterSpacing: -0.5),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF00D2C4), size: 28),
                onPressed: _bookAppointment,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Manage your clinical checkups and teleconsultations',
            style: adminSans(color: AdminPalette.mute, size: 13),
          ),
          const SizedBox(height: 20),

          // 3-Tab Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _tabButton(context, 0, 'Upcoming (${upcoming.length})'),
                _tabButton(context, 1, 'History (${past.length})'),
                _tabButton(context, 2, 'Calendar'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : _activeTab == 2
                    ? SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _buildCalendarTab(context),
                      )
                    : (() {
                        final activeList = _activeTab == 0 ? upcoming : past;
                        return activeList.isEmpty
                            ? Center(
                                child: Text(
                                  _activeTab == 0
                                      ? 'No upcoming consultations booked.'
                                      : 'No consultation logs found.',
                                  style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetchAppointments,
                                color: theme.colorScheme.primary,
                                child: ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  itemCount: activeList.length,
                                  itemBuilder: (context, index) {
                                    final apt = activeList[index];
                                    return _buildAppointmentItem(context, apt);
                                  },
                                ),
                              );
                      })(),
          )
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, int index, String label) {
    final theme = Theme.of(context);
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: GoogleFonts.roboto(
              color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentItem(BuildContext context, Appointment apt) {
    final isUnpaid = apt.paymentStatus == 'unpaid';

    Color statusColor;
    switch (apt.status) {
      case 'approved':
        statusColor = const Color(0xFF22C55E);
        break;
      case 'completed':
        statusColor = const Color(0xFF00D2C4);
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFFFBBF24);
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: AdminGlass(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                apt.doctorName ?? 'General Practitioner',
                style: GoogleFonts.roboto(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  apt.status.toUpperCase(),
                  style: GoogleFonts.roboto(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 4),
          Text(
            apt.fullName,
            style: GoogleFonts.roboto(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(
                apt.preferredDate,
                style: GoogleFonts.roboto(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(
                apt.preferredTime,
                style: GoogleFonts.roboto(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          
          if (isUnpaid && apt.status != 'cancelled' && apt.status != 'completed') ...[
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: () => _payCopay(apt),
              icon: const Icon(Icons.payment, size: 16),
              label: Text(
                _eligibility['eligible'] == true
                    ? 'Pay copay GHS ${_eligibility['copay'] ?? 120} (${_eligibility['payer_name'] ?? 'cover'})'
                    : 'Pay GHS ${_eligibility['consult_fee'] ?? _eligibility['copay'] ?? 120} with MoMo or card',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2C4),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ] else if (apt.isTelemedicine && apt.meetingLink != null &&
              (apt.status == 'approved' || apt.status == 'consulting' || apt.isConsultNow)) ...[
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.videocam, color: Color(0xFFC084FC), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            'Secure Link: ${apt.meetingLink}',
                            style: GoogleFonts.roboto(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => openVideoConsult(context, apt),
                    icon: const Icon(Icons.videocam, size: 16),
                    label: const Text('Join Room'),
                  ),
                ],
              )
          ]
        ],
      ),
    ),
    );
  }
}

// ==================== MESSAGES VIEW ====================
class _MessageThread {
  const _MessageThread({
    required this.appointment,
    required this.lastMessage,
    required this.timeLabel,
    this.unreadCount = 0,
  });

  final Appointment appointment;
  final String lastMessage;
  final String timeLabel;
  final int unreadCount;
}

class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  List<_MessageThread> _threads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _timeLabelFor(String? stamp, Appointment apt) {
    if (stamp != null && stamp.length >= 16) {
      return stamp.substring(11, 16);
    }
    return apt.preferredDate.split('T').first;
  }

  Future<void> _load() async {
    try {
      final care = context.read<CareRepository>();
      final rows = await care.getChatThreads();
      final previews = <_MessageThread>[];
      for (final row in rows) {
        final rawApt = row['appointment'];
        if (rawApt is! Map) continue;
        final apt = Appointment.fromJson(Map<String, dynamic>.from(rawApt));
        final unread = row['unread_count'];
        previews.add(
          _MessageThread(
            appointment: apt,
            lastMessage: row['last_message']?.toString() ?? 'Tap to start a clinical message',
            timeLabel: _timeLabelFor(row['last_created_at']?.toString(), apt),
            unreadCount: unread is int ? unread : int.tryParse(unread?.toString() ?? '') ?? 0,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _threads = previews;
        _loading = false;
      });
    } catch (_) {
      // Fallback to appointment list if threads endpoint is not live yet.
      try {
        final apts = await context.read<AppointmentsRepository>().getMyAppointments();
        final care = context.read<CareRepository>();
        final open = apts.where((a) => a.status != 'cancelled').toList();
        final previews = await Future.wait(open.map((apt) async {
          try {
            final msgs = await care.getChat(apt.id);
            if (msgs.isEmpty) {
              return _MessageThread(
                appointment: apt,
                lastMessage: 'Tap to start a clinical message',
                timeLabel: apt.preferredDate.split('T').first,
              );
            }
            final last = msgs.last;
            return _MessageThread(
              appointment: apt,
              lastMessage: '${last.senderName}: ${last.body}',
              timeLabel: _timeLabelFor(last.createdAt, apt),
            );
          } catch (_) {
            return _MessageThread(
              appointment: apt,
              lastMessage: apt.consultType ?? apt.service ?? 'Consultation thread',
              timeLabel: apt.preferredDate.split('T').first,
            );
          }
        }));
        if (!mounted) return;
        setState(() {
          _threads = previews;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secure Chats',
            style: adminSerif(size: 26, weight: FontWeight.w700, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Clinical messaging linked to your consultations',
            style: adminSans(color: AdminPalette.mute, size: 13),
          ),
          const SizedBox(height: 25),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _threads.isEmpty
                    ? Center(child: Text('No consultation threads yet.', style: adminSans(color: AdminPalette.mute, size: 13)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: _threads.length,
                          itemBuilder: (context, index) {
                            final thread = _threads[index];
                            final apt = thread.appointment;
                            final name = apt.doctorName ?? 'Care team';
                            return _buildChatItem(
                              context,
                              initials: name.substring(0, name.length > 1 ? 2 : 1).toUpperCase(),
                              name: name,
                              lastMessage: thread.lastMessage,
                              time: thread.timeLabel,
                              unreadCount: thread.unreadCount,
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ClinicalChatScreen(appointment: apt),
                                ));
                                if (mounted) await _load();
                              },
                            );
                          },
                        ),
                      ),
          )
        ],
      ),
    );
  }

  Widget _buildChatItem(
    BuildContext context, {
    required String initials,
    required String name,
    required String lastMessage,
    required String time,
    required int unreadCount,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AdminGlass(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AdminPalette.cyan.withValues(alpha: 0.16),
            child: Text(
              initials,
              style: adminSans(
                color: AdminPalette.cyan,
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      time,
                      style: GoogleFonts.roboto(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: unreadCount > 0 ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AdminPalette.cyan,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$unreadCount',
                style: GoogleFonts.roboto(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          ]
        ],
      ),
      ),
    );
  }
}

// ==================== PROFILE VIEW ====================
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  List<Prescription> _prescriptions = [];
  List<Consultation> _consultations = [];
  List<Map<String, dynamic>> _labs = [];
  List<Map<String, dynamic>> _scans = [];
  List<Map<String, dynamic>> _referrals = [];
  Map<String, dynamic> _eligibility = {};
  bool _loadingData = true;

  @override
  void initState() {
    super.initState();
    _loadProfileLogs();
  }

  Future<void> _loadProfileLogs() async {
    try {
      final repo = context.read<AppointmentsRepository>();
      final scripts = await repo.getMyPrescriptions();
      final logs = await repo.getMyConsultations();
      Map<String, dynamic> network = {};
      Map<String, dynamic> elig = {};
      try {
        network = await context.read<CareRepository>().myNetwork();
      } catch (_) {}
      try {
        elig = await context.read<CareRepository>().eligibility();
      } catch (_) {}
      setState(() {
        _prescriptions = scripts;
        _consultations = logs;
        _labs = ((network['labs'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _scans = ((network['scans'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _referrals = ((network['referrals'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _eligibility = elig;
        _loadingData = false;
      });
    } catch (e) {
      setState(() => _loadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Profile Header
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF1E293B),
              child: Text(
                session.user?.name.substring(0, session.user!.name.length > 1 ? 2 : 1).toUpperCase() ?? 'SJ',
                style: GoogleFonts.roboto(
                  fontSize: 24,
                  color: Color(0xFF00D2C4),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            session.user?.name ?? 'Patient',
            style: adminSerif(size: 22, weight: FontWeight.w700),
          ),
          Text(
            'Patient ID: ${session.user?.patientCode ?? 'DH-${session.user?.id ?? "00"}'}',
            style: adminSans(
              size: 11,
              color: AdminPalette.cyan,
              weight: FontWeight.w700,
            ),
          ),
          if (_eligibility['payer_name'] != null) ...[
            const SizedBox(height: 6),
            Text(
              _eligibility['eligible'] == true
                  ? '${_eligibility['payer_name']} · copay GHS ${_eligibility['copay']}'
                  : 'Self pay · GHS ${_eligibility['consult_fee'] ?? 120}',
              style: GoogleFonts.roboto(fontSize: 11, color: Colors.white70),
            ),
          ],
          
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 10),

          Expanded(
            child: _loadingData
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : DefaultTabController(
                    length: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor: Colors.white38,
                          indicatorColor: theme.colorScheme.primary,
                          tabs: const [
                            Tab(text: 'Prescriptions'),
                            Tab(text: 'Results'),
                            Tab(text: 'Consults'),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildPrescriptionsTab(),
                              _buildResultsTab(),
                              _buildConsultationsTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          
          OutlinedButton.icon(
            onPressed: () => context.push('/patient/edit-profile'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit profile'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/patient/profile'),
            child: Text(
              'Edit medical profile',
              style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () async {
              await session.clear();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log Out from Portal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withOpacity(0.12),
              foregroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionsTab() {
    final list = _prescriptions.isEmpty
        ? Center(
            child: Text(
              'No active prescriptions registered.',
              style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13),
            ),
          )
        : ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: _prescriptions.length,
            itemBuilder: (context, index) {
              final pr = _prescriptions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.02)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pr.prescriptionRef != null ? '${pr.prescriptionRef} · ${pr.medicationName}' : pr.medicationName,
                      style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dosage: ${pr.dosage ?? "-"}  |  ${pr.strength ?? ''}  |  ${pr.route ?? ''}  |  Qty: ${pr.quantity ?? "-"}',
                      style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11),
                    ),
                    if (pr.instructions != null && pr.instructions!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Instructions: ${pr.instructions}',
                        style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                    if ((pr.pharmacyName ?? '').isNotEmpty || (pr.dispenseStatus != null && pr.dispenseStatus != 'unsent')) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if ((pr.pharmacyName ?? '').isNotEmpty) pr.pharmacyName!,
                          if (pr.dispenseStatus != null && pr.dispenseStatus != 'unsent') pr.dispenseStatus,
                        ].join(' · '),
                        style: GoogleFonts.roboto(color: const Color(0xFFF59E0B), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              );
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/patient/prescriptions'),
            icon: const Icon(Icons.local_pharmacy_outlined, size: 18, color: Color(0xFF00D2C4)),
            label: Text(
              'Open prescription desk',
              style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildResultsTab() {
    final items = <Map<String, String>>[
      ..._labs.map((l) => {
            'title': l['test_name']?.toString() ?? 'Lab',
            'meta': '${l['partner_name'] ?? 'Lab'} · ${l['status'] ?? ''}',
            'body': (l['results'] ?? l['result_notes'] ?? 'Awaiting result').toString(),
          }),
      ..._scans.map((s) => {
            'title': '${s['scan_type'] ?? 'Scan'} ${s['body_part'] ?? ''}'.trim(),
            'meta': '${s['partner_name'] ?? 'Imaging'} · ${s['status'] ?? ''}',
            'body': (s['results'] ?? s['result_notes'] ?? 'Awaiting report').toString(),
          }),
      ..._referrals.map((r) => {
            'title': '${r['referral_code'] ?? 'REF'} · ${r['specialty'] ?? 'Specialist'}',
            'meta': '${r['to_doctor_name'] ?? r['org_name'] ?? 'Specialist'} · ${r['status'] ?? ''}',
            'body': (r['result_notes'] ?? r['reason'] ?? '').toString(),
          }),
    ];
    if (items.isEmpty) {
      return Center(
        child: Text('No lab, imaging, or referral results yet.', style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13)),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.02)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['title']!, style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              Text(item['meta']!, style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontSize: 11)),
              const SizedBox(height: 4),
              Text(item['body']!, style: GoogleFonts.roboto(color: Colors.white54, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConsultationsTab() {
    if (_consultations.isEmpty) {
      return Center(
        child: Text('No past consultation logs found.', style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13)),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _consultations.length,
      itemBuilder: (context, index) {
        final c = _consultations[index];
        // Collect vitals that were recorded
        final vitals = <Map<String, String>>[];
        if (c.vitalsBp != null && c.vitalsBp!.isNotEmpty) vitals.add({'label': 'BP', 'value': c.vitalsBp!});
        if (c.vitalsTemp != null && c.vitalsTemp!.isNotEmpty) vitals.add({'label': 'Temp', 'value': '${c.vitalsTemp}°C'});
        if (c.vitalsPulse != null && c.vitalsPulse!.isNotEmpty) vitals.add({'label': 'Pulse', 'value': '${c.vitalsPulse} bpm'});
        if (c.vitalsWeight != null && c.vitalsWeight!.isNotEmpty) vitals.add({'label': 'Wt', 'value': '${c.vitalsWeight} kg'});
        if (c.vitalsHeight != null && c.vitalsHeight!.isNotEmpty) vitals.add({'label': 'Ht', 'value': '${c.vitalsHeight} cm'});
        if (c.vitalsSpo2 != null && c.vitalsSpo2!.isNotEmpty) vitals.add({'label': 'SpO2', 'value': '${c.vitalsSpo2}%'});

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.02)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.doctorName ?? 'Consultation Log',
                      style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  if (c.createdAt != null)
                    Text(
                      c.createdAt!.split('T').first,
                      style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 10),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_outline, color: Color(0xFF00D2C4), size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Diagnosis: ${c.diagnosis ?? "No diagnosis entered."}',
                style: GoogleFonts.roboto(color: Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text('Chief Complaint: ${c.chiefComplaint ?? "-"}', style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11)),
              Text('Symptoms: ${c.symptoms ?? "-"}', style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11)),
              if (c.clinicalNotes != null && c.clinicalNotes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Advice: ${c.clinicalNotes}', style: GoogleFonts.roboto(color: Colors.white38, fontSize: 11)),
              ],
              // Vitals badges row
              if (vitals.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: vitals.map((v) => _vitalsBadge(v['label']!, v['value']!)).toList(),
                ),
              ],
              if (c.followUpDate != null && c.followUpDate!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.event_repeat_rounded, size: 12, color: Color(0xFF00D2C4)),
                    const SizedBox(width: 4),
                    Text(
                      'Follow-up: ${c.followUpDate}',
                      style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _vitalsBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PatientNav extends StatelessWidget {
  const _PatientNav({
    required this.index,
    required this.unreadChats,
    required this.onSelect,
  });

  final int index;
  final int unreadChats;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.calendar_today_outlined, Icons.calendar_today, 'Visits'),
      (Icons.forum_outlined, Icons.forum, 'Messages'),
      (Icons.person_outline, Icons.person, 'You'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: digiLine)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: index == i ? clinicalActionGradient : null,
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: index == i ? 12 : 0,
                                  vertical: index == i ? 4 : 0,
                                ),
                                child: Icon(
                                  index == i ? items[i].$2 : items[i].$1,
                                  size: 22,
                                  color: index == i ? Colors.white : digiSlate,
                                ),
                              ),
                            ),
                            if (i == 2 && unreadChats > 0)
                              Positioned(
                                right: -10,
                                top: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: digiForest,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    unreadChats > 99 ? '99+' : '$unreadChats',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[i].$3,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
                            color: index == i ? healynksBlue : digiSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
