import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../models/auth_user.dart';
import '../consult/open_video_consult.dart';
import '../doctor/consultation_dialog.dart';
import '../patient/chat_screen.dart';
import 'admin_chrome.dart';
import 'admin_settings_tab.dart';
import 'admin_users_tab.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTab = 0; // 0: Overview, 1: Appointments, 2: Queue, 3: Doctors, 4: Reports, 5: Staff Registry, 6: Settings

  List<Appointment> _appointments = [];
  List<AuthUser> _users = [];
  List<dynamic> _doctors = [];
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _stats = {
    'stats': {'total': 0, 'today': 0, 'pending': 0, 'completed': 0},
    'trends': [],
    'workload': [],
    'noShow': {'missed_total': 0, 'repeated_offenders': 0}
  };
  
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _opsSummary;

  // Settings Controllers
  final _clinicName = TextEditingController();
  final _smsBaseUrl = TextEditingController();
  final _smsSenderId = TextEditingController();
  final _smsApiKey = TextEditingController();
  final _paystackPublicKey = TextEditingController();
  final _paystackSecretKey = TextEditingController();

  // Create User Controllers
  final _regName = TextEditingController();
  final _regUsername = TextEditingController();
  final _regPassword = TextEditingController();
  final _regPhone = TextEditingController();
  String _regRole = 'doctor';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _clinicName.dispose();
    _smsBaseUrl.dispose();
    _smsSenderId.dispose();
    _smsApiKey.dispose();
    _paystackPublicKey.dispose();
    _paystackSecretKey.dispose();
    _regName.dispose();
    _regUsername.dispose();
    _regPassword.dispose();
    _regPhone.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      
      // Concurrently fetch all dependencies to match web portal's Promise.all
      final responses = await Future.wait([
        api.dio.get<List<dynamic>>('/api/appointments'),
        api.dio.get<List<dynamic>>('/api/users'),
        api.dio.get<Map<String, dynamic>>('/api/settings'),
        api.dio.get<List<dynamic>>('/api/doctors'),
        api.dio.get<Map<String, dynamic>>('/api/analytics/dashboard').catchError((_) => Response<Map<String, dynamic>>(requestOptions: RequestOptions(), data: {})),
      ]);

      if (responses[0].data != null) {
        _appointments = (responses[0].data as List<dynamic>).map((json) => Appointment.fromJson(json as Map<String, dynamic>)).toList();
      }
      if (responses[1].data != null) {
        _users = (responses[1].data as List<dynamic>).map((json) => AuthUser.fromJson(json as Map<String, dynamic>)).toList();
      }
      if (responses[2].data != null) {
        _settings = responses[2].data as Map<String, dynamic>;
        _clinicName.text = _settings['clinic_name']?.toString() ?? '';
        _smsBaseUrl.text = _settings['sms_base_url']?.toString() ?? '';
        _smsSenderId.text = _settings['sms_sender_id']?.toString() ?? '';
        _smsApiKey.text = _settings['sms_api_key']?.toString() ?? '';
        _paystackPublicKey.text = _settings['paystack_public_key']?.toString() ?? '';
        _paystackSecretKey.text = _settings['paystack_secret_key']?.toString() ?? '';
      }
      _doctors = responses[3].data as List<dynamic>? ?? [];
      
      final analyticsData = responses[4].data;
      if (analyticsData != null) {
        _stats = analyticsData as Map<String, dynamic>;
      }
      try {
        final ops = await api.dio.get<Map<String, dynamic>>('/api/admin/ops-summary');
        _opsSummary = ops.data;
      } catch (_) {}
    } catch (e) {
      setState(() => _error = 'Failed to sync database details: ${e.toString()}');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appointment marked as $status.')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: ${e.toString()}')),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.patch<Map<String, dynamic>>(
        '/api/settings',
        data: {
          'clinic_name': _clinicName.text.trim(),
          'sms_base_url': _smsBaseUrl.text.trim(),
          'sms_sender_id': _smsSenderId.text.trim(),
          'sms_api_key': _smsApiKey.text.trim(),
          'paystack_public_key': _paystackPublicKey.text.trim(),
          'paystack_secret_key': _paystackSecretKey.text.trim(),
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully.')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
      );
    }
  }

  Future<void> _createUser() async {
    if (_regName.text.isEmpty || _regUsername.text.isEmpty || _regPassword.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, Username and Password are required.')),
      );
      return;
    }
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/users',
        data: {
          'name': _regName.text.trim(),
          'username': _regUsername.text.trim(),
          'password': _regPassword.text,
          'phone_number': _regPhone.text.trim(),
          'role': _regRole,
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account for ${_regName.text} successfully created.')),
      );
      _regName.clear();
      _regUsername.clear();
      _regPassword.clear();
      _regPhone.clear();
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create account: ${e.toString()}')),
      );
    }
  }

  Future<void> _toggleDoctorActive(int id, bool isActive) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.patch<Map<String, dynamic>>(
        '/api/doctors/$id/status',
        data: {'is_active': isActive},
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update doctor status: ${e.toString()}')),
      );
    }
  }

  Future<void> _createDoctor(String name, String spec, int duration, String start, String end) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/doctors',
        data: {
          'name': name,
          'specialization': spec,
          'slot_duration': duration,
          'start_time': start,
          'end_time': end,
          'is_active': true,
          'working_days': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor profile created.')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create doctor: ${e.toString()}')),
      );
    }
  }

  Future<void> _openMeeting(Appointment apt) async {
    await openVideoConsult(context, apt, isClinician: true);
  }

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAdminTopBar(session, isDesktop),
              Expanded(
                child: _loading
                    ? const AdminOrbitLoader()
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(_error!, textAlign: TextAlign.center, style: adminSans(color: AdminPalette.rose)),
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: KeyedSubtree(
                              key: ValueKey(_currentTab),
                              child: _buildTabContent(),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: !isDesktop ? _buildAdminBottomNav() : null,
    );
  }

  Widget _adminHeaderTabItem(String label, int index, IconData icon) {
    final active = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: active
              ? const LinearGradient(colors: [AdminPalette.cyan, Color(0xFF1AA89C)])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? Colors.black : AdminPalette.mute, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: adminSans(
                size: 12,
                weight: FontWeight.w800,
                color: active ? Colors.black : AdminPalette.mute,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminTopBar(Session session, bool isDesktop) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: AdminGlass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: isDesktop
            ? Row(
                children: [
                  _brandMark(),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _adminHeaderTabItem('Command', 0, Icons.auto_awesome_rounded),
                          _adminHeaderTabItem('Bookings', 1, Icons.calendar_month_rounded),
                          _adminHeaderTabItem('Live queue', 2, Icons.graphic_eq_rounded),
                          _adminHeaderTabItem('Clinicians', 3, Icons.health_and_safety_rounded),
                          _adminHeaderTabItem('Pulse', 4, Icons.insights_rounded),
                          _adminHeaderTabItem('Staff', 5, Icons.people_rounded),
                          _adminHeaderTabItem('Systems', 6, Icons.tune_rounded),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AdminPalette.cyan),
                    onPressed: _loadData,
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AdminPalette.cyan.withValues(alpha: 0.18),
                    child: Text(
                      (session.user?.name ?? 'A')[0].toUpperCase(),
                      style: adminSans(size: 13, weight: FontWeight.w800, color: AdminPalette.cyan),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(session.user?.name ?? 'Admin', style: adminSans(size: 13, weight: FontWeight.w700)),
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
                  _brandMark(compact: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getTabTitle(), style: adminSerif(size: 16, weight: FontWeight.w700)),
                        Text('Command centre', style: adminSans(size: 11, color: AdminPalette.cyan, weight: FontWeight.w700, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.refresh_rounded, color: AdminPalette.cyan), onPressed: _loadData),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AdminPalette.cyan.withValues(alpha: 0.18),
                    child: Text(
                      (session.user?.name ?? 'A')[0].toUpperCase(),
                      style: adminSans(size: 12, weight: FontWeight.w800, color: AdminPalette.cyan),
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

  Widget _brandMark({bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(AppBrand.logoAsset, width: 36, height: 36, fit: BoxFit.cover),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppBrand.name, style: adminSerif(size: 15, weight: FontWeight.w700)),
              Text('OPS NIGHT', style: adminSans(size: 9, weight: FontWeight.w800, color: AdminPalette.gold, letterSpacing: 1.4)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdminBottomNav() {
    final items = [
      (0, Icons.auto_awesome_rounded, 'Command'),
      (2, Icons.graphic_eq_rounded, 'Queue'),
      (1, Icons.calendar_month_rounded, 'Book'),
      (5, Icons.people_rounded, 'Staff'),
      (6, Icons.tune_rounded, 'Systems'),
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
                BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: items.map((item) {
                final active = _currentTab == item.$1;
                return GestureDetector(
                  onTap: () => setState(() => _currentTab = item.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: active ? const LinearGradient(colors: [AdminPalette.cyan, Color(0xFF1AA89C)]) : null,
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
    VoidCallback onTap,
  ) {
    return AdminActionTile(title: title, subtitle: subtitle, icon: icon, color: color, onTap: onTap);
  }

  String _getTabTitle() {
    switch (_currentTab) {
      case 0: return 'Command';
      case 1: return 'Bookings';
      case 2: return 'Live queue';
      case 3: return 'Clinicians';
      case 4: return 'Pulse';
      case 5: return 'Staff';
      case 6:
      default: return 'Systems';
    }
  }

  Widget _buildTabContent() {
    switch (_currentTab) {
      case 0: return _buildOverviewTab();
      case 1: return _buildAppointmentsTab();
      case 2: return _buildQueueTab();
      case 3: return _buildDoctorsTab();
      case 4: return _buildReportsTab();
      case 5: return _buildUsersTab();
      case 6:
      default: return _buildSettingsTab();
    }
  }

  Widget _buildOverviewTab() {
    final session = context.read<Session>();
    final total = _appointments.length;
    final pending = _appointments.where((a) => a.status == 'pending').length;
    final completed = _appointments.where((a) => a.status == 'completed').length;
    final liveQueue = _appointments.where((a) => ['approved', 'arrived', 'waiting', 'consulting'].contains(a.status.toLowerCase())).length;
    final workloads = _stats['workload'] as List<dynamic>? ?? [];
    final narrow = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 188,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: AdminPalette.cyan.withValues(alpha: 0.22), blurRadius: 28, offset: const Offset(0, 14))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/branding/admin_bg.png', fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xF2000A12), Color(0x88071C28), Color(0x3300D2C4)],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AdminLiveDot(),
                            const SizedBox(width: 8),
                            Text('LIVE OPS', style: adminSans(size: 11, weight: FontWeight.w800, color: AdminPalette.lime, letterSpacing: 1.6)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: AdminPalette.cyan.withValues(alpha: 0.4)),
                              ),
                              child: Text('$liveQueue in queue', style: adminSans(size: 11, weight: FontWeight.w700, color: AdminPalette.cyan)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text('Command centre', style: adminSans(size: 13, color: AdminPalette.gold, weight: FontWeight.w700, letterSpacing: 0.4)),
                        Text(
                          session.user?.name ?? 'Administrator',
                          style: adminSerif(size: 30, weight: FontWeight.w700, letterSpacing: -0.6),
                        ),
                        const SizedBox(height: 6),
                        Text('Ghana network Â· clinic, partners, cover', style: adminSans(size: 12, color: AdminPalette.mute)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic),

          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              AdminKpiCard(label: 'Today', value: '${_stats['stats']?['today'] ?? 0}', icon: Icons.bolt_rounded, color: AdminPalette.blue),
              AdminKpiCard(label: 'Pending', value: '$pending', icon: Icons.hourglass_top_rounded, color: AdminPalette.gold),
              AdminKpiCard(label: 'Completed', value: '$completed', icon: Icons.verified_rounded, color: AdminPalette.cyan),
              AdminKpiCard(label: 'All bookings', value: '$total', icon: Icons.hub_rounded, color: AdminPalette.violet),
            ],
          ).animate().fadeIn(delay: 80.ms, duration: 450.ms),
          const SizedBox(height: 22),

          Text('Launch pad', style: adminSerif(size: 20)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: narrow ? 2 : 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: narrow ? 1.38 : 1.55,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _quickActionCard('Bookings', 'Manage visits', Icons.calendar_month_rounded, AdminPalette.violet, () => setState(() => _currentTab = 1)),
              _quickActionCard('Live queue', 'Floor status', Icons.graphic_eq_rounded, AdminPalette.cyan, () => setState(() => _currentTab = 2)),
              _quickActionCard('Clinicians', 'Rosters', Icons.health_and_safety_rounded, AdminPalette.blue, () => setState(() => _currentTab = 3)),
              _quickActionCard('Pulse', 'Analytics', Icons.insights_rounded, AdminPalette.gold, () => setState(() => _currentTab = 4)),
              _quickActionCard('Staff', 'Registry', Icons.people_rounded, AdminPalette.violet, () => setState(() => _currentTab = 5)),
              _quickActionCard('Systems', 'SMS & pay', Icons.tune_rounded, AdminPalette.rose, () => setState(() => _currentTab = 6)),
              _quickActionCard('Support', 'Desk tickets', Icons.support_agent_rounded, AdminPalette.lime, () => context.push('/admin/support')),
              _quickActionCard('Nation', 'Coverage', Icons.public_rounded, AdminPalette.gold, () => context.push('/admin/network')),
            ],
          ).animate().fadeIn(duration: 420.ms, delay: 140.ms).slideY(begin: 0.06, end: 0),
          const SizedBox(height: 22),

          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Clinician load', style: adminSerif(size: 18)),
                const SizedBox(height: 4),
                Text('Todayâ€™s booked slots across specialists', style: adminSans(size: 12, color: AdminPalette.mute)),
                const SizedBox(height: 16),
                if (workloads.isEmpty)
                  Text('No workload compiled yet.', style: adminSans(color: AdminPalette.mute))
                else
                  ...workloads.map((item) {
                    final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
                    final pct = (count / 20.0).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AdminGlowBar(
                        label: item['name']?.toString() ?? 'Specialist',
                        pct: pct,
                        color: AdminPalette.cyan,
                        trailing: '$count slots',
                      ),
                    );
                  }),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 14),

          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wait bands', style: adminSerif(size: 18)),
                const SizedBox(height: 14),
                _buildWaitBar('Under 15m', 0.70, AdminPalette.lime),
                const SizedBox(height: 12),
                _buildWaitBar('15 â€“ 30m', 0.20, AdminPalette.gold),
                const SizedBox(height: 12),
                _buildWaitBar('Over 30m', 0.10, AdminPalette.rose),
              ],
            ),
          ).animate().fadeIn(delay: 280.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
        ],
      ),
    );
  }

  Widget _buildWaitBar(String label, double pct, Color color) {
    return AdminGlowBar(label: label, pct: pct, color: color);
  }

  Widget _buildAppointmentsTab() {
    if (_appointments.isEmpty) {
      return Center(child: Text('No appointments recorded.', style: adminSans(color: AdminPalette.mute)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _appointments.length,
      itemBuilder: (context, index) {
        final apt = _appointments[index];
        final isPending = apt.status == 'pending';
        final statusColor = _getStatusColor(apt.status);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AdminGlass(
            glow: statusColor,
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: isPending ? 148 : 108,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
                    boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 12)],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(apt.fullName, style: adminSans(size: 15, weight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                            ),
                            _buildBadge(apt.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${apt.phoneNumber}  Â·  ${apt.doctorName ?? "Unassigned"}',
                          style: adminSans(size: 12, color: AdminPalette.mute),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, color: AdminPalette.gold, size: 14),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${apt.preferredDate} Â· ${apt.preferredTime}',
                                style: adminSans(size: 12, color: AdminPalette.mute),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (apt.isTelemedicine)
                              Text('Telehealth', style: adminSans(size: 11, weight: FontWeight.w800, color: AdminPalette.cyan)),
                          ],
                        ),
                        if (isPending) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _updateStatus(apt, 'cancelled'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AdminPalette.rose,
                                    side: const BorderSide(color: AdminPalette.rose),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text('Cancel', style: adminSans(size: 12, weight: FontWeight.w700, color: AdminPalette.rose)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _updateStatus(apt, 'approved'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AdminPalette.cyan,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text('Approve', style: adminSans(size: 12, weight: FontWeight.w800, color: Colors.black)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: (40 * index).ms, duration: 320.ms).slideX(begin: 0.04),
        );
      },
    );
  }

  Widget _buildDoctorsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Active specialists', style: adminSerif(size: 18)),
              FilledButton.icon(
                onPressed: _openAddDoctorDialog,
                icon: const Icon(Icons.add, size: 16, color: Colors.black),
                label: Text('Add', style: adminSans(size: 12, weight: FontWeight.w800, color: Colors.black)),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminPalette.cyan,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _doctors.isEmpty
              ? Center(child: Text('No doctor profiles configured.', style: adminSans(color: AdminPalette.mute)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _doctors.length,
                  itemBuilder: (context, index) {
                    final doc = _doctors[index];
                    final active = doc['is_active'] == true || doc['is_active'] == 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AdminGlass(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AdminPalette.violet.withValues(alpha: 0.2),
                            child: const Icon(Icons.person, color: AdminPalette.violet),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(doc['name']?.toString() ?? '', style: adminSans(size: 14, weight: FontWeight.w800)),
                                Text(doc['specialization']?.toString() ?? '', style: adminSans(size: 12, color: AdminPalette.mute)),
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: ${doc['slot_duration']}m  Â·  ${doc['start_time']?.toString().substring(0, 5)} â€“ ${doc['end_time']?.toString().substring(0, 5)}',
                                  style: adminSans(size: 11, color: AdminPalette.mute),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: active,
                            activeTrackColor: AdminPalette.cyan,
                            onChanged: (val) {
                              _toggleDoctorActive(doc['id'] as int, val);
                            },
                          ),
                        ],
                      ),
                    ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQueueTab() {
    // Queue filter: active appointments (approved, arrived, waiting, consulting)
    final queue = _appointments.where((a) => ['approved', 'arrived', 'waiting', 'consulting'].contains(a.status.toLowerCase())).toList();

    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.graphic_eq_rounded, color: AdminPalette.cyan, size: 48),
            SizedBox(height: 10),
            Text('Clinic queue is empty.', style: adminSans(color: AdminPalette.mute)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final apt = queue[index];
        final stat = apt.status.toLowerCase();
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AdminGlass(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AdminPalette.violet, AdminPalette.cyan]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${index + 1}', style: adminSans(size: 13, weight: FontWeight.w800, color: Colors.black)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apt.fullName,
                      style: adminSans(size: 14, weight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${apt.preferredTime}  Â·  ${apt.doctorName ?? "Unassigned"}',
                      style: adminSans(size: 11, color: AdminPalette.mute),
                    ),
                    if (apt.isVideoConsult && apt.hasMeetingLink) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _openMeeting(apt),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.video_call_rounded, color: AdminPalette.cyan, size: 13),
                            SizedBox(width: 4),
                            Text('Join meeting', style: adminSans(size: 11, weight: FontWeight.w700, color: AdminPalette.cyan)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildBadge(stat),
                  const SizedBox(height: 8),
                  _buildQueueActionButton(apt, stat),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildQueueActionButton(Appointment apt, String status) {
    if (status == 'approved') {
      return ElevatedButton(
        onPressed: () => _updateStatus(apt, 'arrived'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        child: Text('Arrived', style: adminSans(size: 11, weight: FontWeight.w800, color: Colors.white)),
      );
    } else if (status == 'arrived') {
      return ElevatedButton(
        onPressed: () => _updateStatus(apt, 'consulting'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        child: Text('Consult', style: adminSans(size: 11, weight: FontWeight.w800, color: Colors.white)),
      );
    } else if (status == 'consulting') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.assignment, color: Color(0xFF00D2C4), size: 18),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => ConsultationDialog(appointment: apt),
              ).then((_) => _loadData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble, color: Color(0xFF8B5CF6), size: 18),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ClinicalChatScreen(appointment: apt)),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => _updateStatus(apt, 'completed'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: Text('Complete', style: adminSans(size: 11, weight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildReportsTab() {
    final trends = _stats['trends'] as List<dynamic>? ?? [];
    final total = double.tryParse(_stats['stats']?['total']?.toString() ?? '0') ?? 0.0;
    final completed = double.tryParse(_stats['stats']?['completed']?.toString() ?? '0') ?? 0.0;
    final attendanceRate = total > 0 ? (completed / total) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly booking pulse', style: adminSerif(size: 18)),
                const SizedBox(height: 16),
                AdminTrendChart(trends: trends),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 14),
          AdminGlass(
            child: Row(
              children: [
                AdminRingMetric(label: 'Attendance', pct: attendanceRate, color: AdminPalette.violet),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visit completion', style: adminSans(size: 13, weight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        'Share of booked visits that reached a completed consult.',
                        style: adminSans(size: 12, color: AdminPalette.mute, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No-show analysis', style: adminSerif(size: 18)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildNoShowSubCard('Missed total', '${_stats['noShow']?['missed_total'] ?? 0}', AdminPalette.rose),
                    const SizedBox(width: 12),
                    _buildNoShowSubCard('Repeat risk', '${_stats['noShow']?['repeated_offenders'] ?? 0}', AdminPalette.gold),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoShowSubCard(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: adminSans(size: 10, weight: FontWeight.w800, color: AdminPalette.mute, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text(val, style: adminSerif(size: 26, weight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return AdminUsersTab(
      users: _users,
      name: _regName,
      username: _regUsername,
      password: _regPassword,
      phone: _regPhone,
      role: _regRole,
      onRoleChanged: (v) => setState(() => _regRole = v),
      onCreate: _createUser,
      fieldDecoration: _deco,
    );
  }

  Widget _buildSettingsTab() {
    return AdminSettingsTab(
      clinicName: _clinicName,
      smsBaseUrl: _smsBaseUrl,
      smsSenderId: _smsSenderId,
      smsApiKey: _smsApiKey,
      paystackPublicKey: _paystackPublicKey,
      paystackSecretKey: _paystackSecretKey,
      onSave: _saveSettings,
      fieldDecoration: _deco,
      opsSummary: _opsSummary,
    );
  }

  InputDecoration _deco(String hint, IconData icon) {
    return adminFieldDeco(hint, icon);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF22C55E);
      case 'completed':
        return const Color(0xFF00D2C4);
      case 'arrived':
        return Colors.blue;
      case 'consulting':
        return const Color(0xFF8B5CF6);
      case 'cancelled':
        return Colors.redAccent;
      case 'pending':
      default:
        return const Color(0xFFFBBF24);
    }
  }

  Widget _buildBadge(String status) {
    return AdminStatusChip(label: status, color: _getStatusColor(status));
  }

  InputDecoration _inputDeco(String hintText) {
    return adminFieldDeco(hintText, Icons.edit_outlined);
  }

  void _openAddDoctorDialog() {
    final nameC = TextEditingController();
    final specC = TextEditingController();
    final durC = TextEditingController(text: '15');
    final startC = TextEditingController(text: '08:00');
    final endC = TextEditingController(text: '17:00');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AdminPalette.surface,
          title: Text('Add clinician', style: adminSerif(size: 20)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: nameC, style: adminSans(), decoration: _inputDeco('Full name (e.g. Dr. Arthur)')),
                const SizedBox(height: 10),
                TextFormField(controller: specC, style: adminSans(), decoration: _inputDeco('Specialization')),
                const SizedBox(height: 10),
                TextFormField(controller: durC, style: adminSans(), decoration: _inputDeco('Slot duration (min)'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                TextFormField(controller: startC, style: adminSans(), decoration: _inputDeco('Start time (e.g. 08:00)')),
                const SizedBox(height: 10),
                TextFormField(controller: endC, style: adminSans(), decoration: _inputDeco('End time (e.g. 17:00)')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: adminSans(weight: FontWeight.w700, color: AdminPalette.mute)),
            ),
            FilledButton(
              onPressed: () {
                if (nameC.text.trim().isNotEmpty && specC.text.trim().isNotEmpty) {
                  _createDoctor(
                    nameC.text.trim(),
                    specC.text.trim(),
                    int.tryParse(durC.text) ?? 15,
                    startC.text.trim(),
                    endC.text.trim(),
                  );
                  Navigator.pop(context);
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AdminPalette.cyan, foregroundColor: Colors.black),
              child: const Text('Add profile'),
            )
          ],
        );
      },
    );
  }
}
