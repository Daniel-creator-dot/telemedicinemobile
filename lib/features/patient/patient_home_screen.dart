import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/brand.dart';
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
    return Scaffold(
      backgroundColor: AdminPalette.bg,
      body: AdminMeshBackdrop(
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey(_currentIndex),
              child: _screens[_currentIndex],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
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
                    BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.14), blurRadius: 30, offset: const Offset(0, -4)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(4, (index) {
                    const icons = [
                      Icons.home_outlined,
                      Icons.calendar_today_outlined,
                      Icons.forum_outlined,
                      Icons.person_outline,
                    ];
                    const activeIcons = [
                      Icons.home_filled,
                      Icons.calendar_today,
                      Icons.forum,
                      Icons.person,
                    ];
                    const labels = ['Home', 'Visits', 'Messages', 'You'];
                    final isActive = _currentIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _currentIndex = index);
                        if (index == 2) _refreshChatBadge();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: isActive ? const LinearGradient(colors: [AdminPalette.cyan, Color(0xFF1AA89C)]) : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  isActive ? activeIcons[index] : icons[index],
                                  color: isActive ? Colors.black : AdminPalette.mute,
                                  size: 22,
                                ),
                                if (index == 2 && _unreadChats > 0)
                                  Positioned(
                                    right: -8,
                                    top: -4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AdminPalette.cyan,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _unreadChats > 99 ? '99+' : '$_unreadChats',
                                        style: adminSans(size: 9, weight: FontWeight.w800, color: Colors.black),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              labels[index],
                              style: adminSans(
                                size: 10,
                                weight: FontWeight.w800,
                                color: isActive ? Colors.black : AdminPalette.mute,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
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
  List<Map<String, dynamic>> _activeCare = [];
  int _openCareCount = 0;
  bool _loading = true;
  bool _isSearchFocused = false;
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

      setState(() {
        _doctors = docs;
        _activeCare = activeCare;
        _openCareCount = openCareCount;
        if (upcoming.isNotEmpty) {
          _nextAppointment = upcoming.first;
        } else {
          _nextAppointment = null;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: AdminPalette.cyan,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back,', style: adminSans(size: 13, color: AdminPalette.mute)),
                    Text(
                      session.user?.name ?? 'Patient',
                      style: adminSerif(size: 26, weight: FontWeight.w700, letterSpacing: -0.5),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () async {
                        await context.push('/patient/notifications');
                        if (mounted) await _refreshUnreadCount();
                      },
                      icon: Badge(
                        isLabelVisible: _unreadNotifications > 0,
                        label: Text('$_unreadNotifications'),
                        child: const Icon(Icons.notifications_none_rounded, color: AdminPalette.ink),
                      ),
                    ),
                    const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AdminPalette.gold, AdminPalette.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AdminPalette.cyan.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AdminPalette.surface,
                    child: Text(
                      (session.user?.name.isNotEmpty == true)
                          ? session.user!.name.substring(0, session.user!.name.length > 1 ? 2 : 1).toUpperCase()
                          : 'DH',
                      style: adminSans(
                        color: AdminPalette.ink,
                        weight: FontWeight.w800,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0),

            const SizedBox(height: 25),

            // Welcome Banner using onboarding_3.png
            Container(
              margin: const EdgeInsets.only(bottom: 25),
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
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
                            const Color(0xFF0F172A).withOpacity(0.9),
                            theme.colorScheme.primary.withOpacity(0.4),
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
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Image.asset(AppBrand.logoAsset, width: 28, height: 28, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                AppBrand.name,
                                style: GoogleFonts.roboto(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Care that stays with you',
                            style: GoogleFonts.sourceSerif4(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Consult, investigate, treat, and follow up — one record.',
                            style: GoogleFonts.dmSans(
                              color: Colors.white.withOpacity(0.78),
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
            ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05),

            // Modern Search Bar
            AdminGlass(
              glow: _isSearchFocused ? AdminPalette.cyan : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: TextField(
                onTap: () {
                  setState(() => _isSearchFocused = true);
                  context.push('/patient/doctors');
                },
                onSubmitted: (_) {
                  setState(() => _isSearchFocused = false);
                  context.push('/patient/doctors');
                },
                style: adminSans(size: 14),
                decoration: InputDecoration(
                  icon: Icon(
                    Icons.search_rounded,
                    color: _isSearchFocused ? AdminPalette.cyan : AdminPalette.mute,
                  ),
                  hintText: 'Search symptoms, specialists, clinics...',
                  hintStyle: adminSans(size: 14, color: AdminPalette.mute),
                  border: InputBorder.none,
                ),
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 24),

            // Quick Actions
            Text(
              'Quick Actions',
              style: adminSans(size: 16, weight: FontWeight.w800),
            ).animate().fadeIn(delay: 150.ms),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildQuickAction(
                  context,
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Book Visit',
                  color: const Color(0xFF8B5CF6),
                  backgroundImage: 'assets/appointment.png',
                  overlayColor: const Color(0xFF4C0099), // deep purple
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => const BookAppointmentDialog(),
                    ).then((_) => _loadDashboardData());
                  },
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.videocam_rounded,
                  label: 'Teleconsult',
                  color: const Color(0xFF00D2C4),
                  backgroundImage: 'assets/speciality.png',
                  overlayColor: const Color(0xFF065F46), // deep emerald
                  onTap: () {
                    context.push('/patient/consult-now').then((_) => _loadDashboardData());
                  },
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.medication_rounded,
                  label: 'Prescriptions',
                  color: const Color(0xFFF59E0B),
                  backgroundImage: 'assets/records.png',
                  overlayColor: const Color(0xFF92400E), // deep amber
                  onTap: () {
                    final parentState = context.findAncestorStateOfType<_MainNavigationScreenState>();
                    if (parentState != null) {
                      parentState.setState(() => parentState._currentIndex = 3);
                    }
                  },
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.emergency_rounded,
                  label: 'Live Queue',
                  color: const Color(0xFFEF4444),
                  backgroundImage: 'assets/live queue.png',
                  overlayColor: const Color(0xFF9B1C1C), // deep crimson
                  onTap: () {
                    context.push('/patient/consult-now').then((_) => _loadDashboardData());
                  },
                ),
              ],
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CareChip(label: 'Care phases', icon: Icons.account_tree_outlined, onTap: () => context.push('/patient/phases')),
                _CareChip(label: 'Health journey', icon: Icons.timeline, onTap: () => context.push('/patient/journey')),
                _CareChip(label: 'Records vault', icon: Icons.folder_shared_outlined, onTap: () => context.push('/patient/records')),
                _CareChip(label: 'Health tracker', icon: Icons.monitor_heart_outlined, onTap: () => context.push('/patient/tracker')),
                _CareChip(label: 'Family', icon: Icons.family_restroom, onTap: () => context.push('/patient/family')),
                _CareChip(label: 'Care programs', icon: Icons.favorite_outline, onTap: () => context.push('/patient/programs')),
                _CareChip(label: 'Symptom helper', icon: Icons.psychology_outlined, onTap: () => context.push('/patient/symptom-helper')),
                _CareChip(label: 'Find a doctor', icon: Icons.medical_services_outlined, onTap: () => context.push('/patient/doctors')),
                _CareChip(label: 'Ghana network', icon: Icons.map_outlined, onTap: () => context.push('/patient/network')),
                _CareChip(label: 'Payments', icon: Icons.receipt_long_outlined, onTap: () => context.push('/patient/payments')),
                _CareChip(label: 'Insurance cover', icon: Icons.health_and_safety_outlined, onTap: () => context.push('/patient/coverage')),
                _CareChip(label: 'Membership', icon: Icons.workspace_premium_outlined, onTap: () => context.push('/patient/membership')),
                _CareChip(label: 'Follow-up', icon: Icons.event_available_outlined, onTap: () => context.push('/patient/followups')),
                _CareChip(label: 'Help', icon: Icons.support_agent_outlined, onTap: () => context.push('/patient/support')),
                _CareChip(label: 'Edit profile', icon: Icons.edit_outlined, onTap: () => context.push('/patient/edit-profile')),
                _CareChip(label: 'Consents', icon: Icons.verified_user_outlined, onTap: () => context.push('/patient/consents')),
                _CareChip(label: 'Medical profile', icon: Icons.badge_outlined, onTap: () => context.push('/patient/profile')),
              ],
            ),

            const SizedBox(height: 25),

            if (_openCareCount > 0) ...[
              _ActiveCareStrip(
                count: _openCareCount,
                items: _activeCare,
                onTap: () => context.push('/patient/journey'),
              ),
              const SizedBox(height: 16),
            ],

            // Next Appointment Card
            if (_nextAppointment != null) ...[
              AdminGlass(
                glow: AdminPalette.cyan,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AdminStatusChip(
                          label: _nextAppointment!.isTelemedicine ? 'VIDEO VISIT' : 'CLINICAL VISIT',
                          color: AdminPalette.cyan,
                        ),
                        const Spacer(),
                        _buildBadge(_nextAppointment!.status),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AdminPalette.cyan.withValues(alpha: 0.16),
                          child: Text(
                            _nextAppointment!.doctorName?.substring(0, 2).toUpperCase() ?? 'MD',
                            style: adminSans(color: AdminPalette.cyan, size: 13, weight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nextAppointment!.doctorName ?? 'Assigned Specialist',
                              style: adminSans(size: 16, weight: FontWeight.w800),
                            ),
                            Text(
                              'Medical Practitioner',
                              style: adminSans(size: 12, color: AdminPalette.mute),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: AdminPalette.gold,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_nextAppointment!.preferredDate}, ${_nextAppointment!.preferredTime}',
                              style: adminSans(size: 13, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                        if (_nextAppointment!.isTelemedicine &&
                            (_nextAppointment!.status == 'approved' ||
                                _nextAppointment!.status == 'consulting' ||
                                _nextAppointment!.status == 'queued') &&
                            _nextAppointment!.meetingLink != null)
                          FilledButton.icon(
                            onPressed: () => _openMeeting(_nextAppointment!),
                            icon: const Icon(Icons.videocam, size: 16),
                            label: Text(
                              'Join Room',
                              style: adminSans(weight: FontWeight.w800, size: 12, color: Colors.black),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AdminPalette.cyan,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                      ],
                    )
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 30),
            ],

            // Health Metrics Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Health Overview',
                  style: adminSans(size: 16, weight: FontWeight.w800),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AdminPalette.lime.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Synced',
                    style: GoogleFonts.roboto(
                      color: theme.colorScheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 15),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.1,
              children: [
                _buildMetricCard(
                  context,
                  title: 'Heart Rate',
                  value: '78 bpm',
                  status: 'Normal',
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFFEF4444),
                  accentColor: const Color(0xFFEF4444),
                  customWidget: Row(
                    children: [
                      const Icon(
                        Icons.show_chart_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Pulse graph sync',
                        style: GoogleFonts.roboto(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMetricCard(
                  context,
                  title: 'Sleep Tracker',
                  value: '7h 45m',
                  status: 'Optimal',
                  icon: Icons.dark_mode_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  accentColor: const Color(0xFF8B5CF6),
                  customWidget: LinearProgressIndicator(
                    value: 0.85,
                    backgroundColor: const Color(0xFF1E293B),
                    color: const Color(0xFF8B5CF6),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

            const SizedBox(height: 30),

            // Specialists Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Our Specialists',
                  style: adminSans(size: 16, weight: FontWeight.w800),
                ),
                TextButton(
                  onPressed: () => context.push('/patient/doctors'),
                  child: Text(
                    'See All',
                    style: adminSans(
                      color: AdminPalette.cyan,
                      size: 12,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 350.ms),

            const SizedBox(height: 15),

            // Doctors list from database
            _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : _doctors.isEmpty
                    ? Center(
                        child: Text(
                          'No doctors registered in portal.',
                          style: GoogleFonts.roboto(color: Colors.white30, fontSize: 13),
                        ),
                      )
                    : SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _doctors.length,
                          itemBuilder: (context, index) {
                            final doc = _doctors[index];
                            final fee = doc.consultationFee == null
                                ? 'Book'
                                : 'GHS ${doc.consultationFee!.toStringAsFixed(0)}';
                            return _buildDoctorAvatarCard(
                              context,
                              name: doc.name,
                              specialty: doc.specialization?.trim().isNotEmpty == true
                                  ? doc.specialization!
                                  : 'Clinician',
                              rating: fee,
                              isOnline: doc.isOnline,
                              initials: doc.name.substring(0, doc.name.length > 1 ? 2 : 1).toUpperCase(),
                              onTap: () => _openBook(doc),
                            );
                          },
                        ),
                      ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    String? backgroundImage,
    Color? overlayColor,
  }) {
    return Expanded(
      child: SizedBox(
        height: 96,
        child: AdminActionTile(
          title: label,
          subtitle: 'Open',
          icon: icon,
          color: color,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String status,
    required IconData icon,
    required Color iconColor,
    required Color accentColor,
    Widget? customWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.25),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: accentColor.withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Faint gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    accentColor.withOpacity(0.05),
                    Colors.transparent,
                    accentColor.withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(icon, color: iconColor, size: 20),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: adminSerif(size: 22, weight: FontWeight.w700, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.roboto(
                        fontSize: 9,
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (customWidget != null) ...[
                const SizedBox(height: 8),
                customWidget,
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorAvatarCard(
    BuildContext context, {
    required String name,
    required String specialty,
    required String rating,
    required bool isOnline,
    required String initials,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
      width: 135,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                      const Color(0xFF00D2C4),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF1E293B),
                  child: Text(
                    initials,
                    style: GoogleFonts.roboto(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              if (isOnline)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F172A),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withOpacity(0.7),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.roboto(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.secondary.withOpacity(0.15),
                  theme.colorScheme.primary.withOpacity(0.1),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.35), width: 1),
            ),
            child: Text(
              specialty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.roboto(
                fontSize: 9,
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                rating.startsWith('GHS') ? Icons.payments_outlined : Icons.event_available_rounded,
                color: const Color(0xFF00D2C4),
                size: 14,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  rating,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildBadge(String status) {
    Color color;
    switch (status) {
      case 'approved':
        color = const Color(0xFF22C55E);
        break;
      case 'completed':
        color = const Color(0xFF00D2C4);
        break;
      case 'cancelled':
        color = Colors.redAccent;
        break;
      case 'pending':
      default:
        color = const Color(0xFFFBBF24);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.roboto(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
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
                    ? 'Pay copay GHS ${_eligibility['copay'] ?? 50} (${_eligibility['payer_name'] ?? 'cover'})'
                    : 'Pay GHS ${_eligibility['consult_fee'] ?? _eligibility['copay'] ?? 50} with MoMo or card',
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
                  : 'Self pay · GHS ${_eligibility['consult_fee'] ?? 50}',
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
    if (_prescriptions.isEmpty) {
      return Center(
        child: Text('No active prescriptions registered.', style: GoogleFonts.roboto(color: Colors.white24, fontSize: 13)),
      );
    }

    return ListView.builder(
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

class _ActiveCareStrip extends StatelessWidget {
  const _ActiveCareStrip({
    required this.count,
    required this.items,
    required this.onTap,
  });

  final int count;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;

  String _line(Map<String, dynamic> e) {
    final title = e['title']?.toString() ?? 'Care item';
    final partner = e['partner_name']?.toString();
    final label = e['status_label']?.toString() ?? e['status']?.toString() ?? '';
    if (partner != null && partner.isNotEmpty) return '$title · $partner · $label';
    return '$title · $label';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AdminGlass(
          glow: const Color(0xFFF59E0B),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_hospital_outlined, color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active care · $count in progress',
                      style: adminSans(weight: FontWeight.w700, size: 14),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...items.take(3).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _line(e),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CareChip extends StatelessWidget {
  const _CareChip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AdminPalette.cyan),
      label: Text(label, style: adminSans(weight: FontWeight.w600, size: 12)),
      onPressed: onTap,
      backgroundColor: AdminPalette.glass,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    );
  }
}
