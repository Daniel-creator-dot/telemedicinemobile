import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../models/auth_user.dart';
import '../doctor/consultation_dialog.dart';

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

  // Settings Controllers
  final _clinicName = TextEditingController();
  final _smsBaseUrl = TextEditingController();
  final _smsSenderId = TextEditingController();
  final _smsApiKey = TextEditingController();

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
      }
      _doctors = responses[3].data as List<dynamic>? ?? [];
      
      final analyticsData = responses[4].data;
      if (analyticsData != null) {
        _stats = analyticsData as Map<String, dynamic>;
      }
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAdminTopBar(session, theme, isDesktop),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                  : _error != null
                      ? Center(child: Text(_error!, style: GoogleFonts.roboto(color: Color(0xFF64748B))))
                      : _buildTabContent(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !isDesktop ? _buildAdminBottomNav() : null,
    );
  }

  Widget _adminHeaderTabItem(String label, int index, IconData icon) {
    final active = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00D2C4).withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFF00D2C4) : const Color(0xFF64748B),
              size: 15,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.roboto(
                color: active ? const Color(0xFF00D2C4) : const Color(0xFF64748B),
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminTopBar(Session session, ThemeData theme, bool isDesktop) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Color(0xFFF0FDFC)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFB2F5F0), width: 1.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: isDesktop
          ? Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00D2C4).withOpacity(0.12),
                    border: Border.all(
                      color: const Color(0xFF00D2C4).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: Color(0xFF00D2C4),
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
                      'Admin Portal',
                      style: GoogleFonts.roboto(
                        color: Color(0xFF00D2C4),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _adminHeaderTabItem('Dashboard', 0, Icons.dashboard_rounded),
                        _adminHeaderTabItem('Appointments', 1, Icons.calendar_month_rounded),
                        _adminHeaderTabItem('Queue', 2, Icons.checklist_rounded),
                        _adminHeaderTabItem('Doctors', 3, Icons.health_and_safety_rounded),
                        _adminHeaderTabItem('Reports', 4, Icons.bar_chart_rounded),
                        _adminHeaderTabItem('Staff', 5, Icons.people_rounded),
                        _adminHeaderTabItem('Settings', 6, Icons.settings_rounded),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00D2C4)),
                  onPressed: _loadData,
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFE6F9F8),
                      child: Text(
                        (session.user?.name ?? 'A')[0].toUpperCase(),
                        style: GoogleFonts.roboto(
                          color: Color(0xFF00D2C4),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.user?.name ?? 'Admin',
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
                  tooltip: 'Logout Session',
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
                    color: const Color(0xFF00D2C4).withOpacity(0.12),
                    border: Border.all(
                      color: const Color(0xFF00D2C4).withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: Color(0xFF00D2C4),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getTabTitle(),
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00D2C4)),
                  onPressed: _loadData,
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFFE6F9F8),
                  child: Text(
                    (session.user?.name ?? 'A')[0].toUpperCase(),
                    style: GoogleFonts.roboto(
                      color: Color(0xFF00D2C4),
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

  Widget _buildAdminBottomNav() {
    final items = [
      (0, Icons.dashboard_rounded, 'Home'),
      (2, Icons.checklist_rounded, 'Queue'),
      (1, Icons.calendar_month_rounded, 'Schedule'),
      (5, Icons.people_rounded, 'Staff'),
      (6, Icons.settings_rounded, 'Settings'),
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
              final active = _currentTab == item.$1;
              return GestureDetector(
                onTap: () => setState(() => _currentTab = item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF00D2C4).withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$2,
                        size: 20,
                        color: active ? const Color(0xFF00D2C4) : const Color(0xFF64748B),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: GoogleFonts.roboto(
                          fontSize: 9,
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: active ? const Color(0xFF00D2C4) : const Color(0xFF64748B),
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
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.10), color.withOpacity(0.04)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.28), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.roboto(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.roboto(
                color: color.withOpacity(0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTabTitle() {
    switch (_currentTab) {
      case 0: return 'System Overview';
      case 1: return 'Appointments Management';
      case 2: return 'Live Clinic Queue';
      case 3: return 'Doctor Schedules';
      case 4: return 'Reports & Analytics';
      case 5: return 'Staff Accounts';
      case 6:
      default: return 'System Configuration';
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
    
    // Simple mock workload data if empty
    final workloads = _stats['workload'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Welcome Banner using admin_bg.png
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D2C4).withOpacity(0.15),
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
                    'assets/branding/admin_bg.png',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0F172A).withOpacity(0.9),
                          const Color(0xFF00D2C4).withOpacity(0.4),
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
                          'Welcome Back,',
                          style: GoogleFonts.roboto(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.user?.name ?? 'Administrator',
                          style: GoogleFonts.roboto(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Clinic Operations Portal • System Administrator',
                            style: GoogleFonts.roboto(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.05),

          // ── Quick Actions Grid ──────────────────────────────────────────────
          Text(
            'Quick Actions',
            style: GoogleFonts.roboto(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 6,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: MediaQuery.of(context).size.width < 600 ? 1.5 : 1.8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _quickActionCard('Appointments', 'Manage bookings', Icons.calendar_month_rounded, const Color(0xFF8B5CF6), () => setState(() => _currentTab = 1)),
              _quickActionCard('Queue Manager', 'Patient statuses', Icons.checklist_rounded, const Color(0xFF00D2C4), () => setState(() => _currentTab = 2)),
              _quickActionCard('Doctors', 'Specialists schedules', Icons.health_and_safety_rounded, const Color(0xFF3B82F6), () => setState(() => _currentTab = 3)),
              _quickActionCard('Reports', 'Clinic analytics', Icons.bar_chart_rounded, const Color(0xFFF59E0B), () => setState(() => _currentTab = 4)),
              _quickActionCard('Staff Accounts', 'User registry', Icons.people_rounded, const Color(0xFF4F46E5), () => setState(() => _currentTab = 5)),
              _quickActionCard('SMS Settings', 'Clinic config', Icons.settings_rounded, const Color(0xFFF43F5E), () => setState(() => _currentTab = 6)),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 20),

          // Stat Counters Cards Grid
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: [
              _buildStatMetricCard('TODAY BOOKINGS', '${_stats['stats']?['today'] ?? 0}', Colors.blue),
              _buildStatMetricCard('PENDING SLOTS', '$pending', Colors.amber),
              _buildStatMetricCard('COMPLETED VISITS', '$completed', const Color(0xFF00D2C4)),
              _buildStatMetricCard('TOTAL BOOKINGS', '$total', const Color(0xFF8B5CF6)),
            ],
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 20),

          // Workload
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
                Text(
                  'Doctor Workloads (Today)',
                  style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 15),
                if (workloads.isEmpty)
                  Text('No stats compiled yet.', style: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 12))
                else
                  ...workloads.map((item) {
                    final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
                    final pct = (count / 20.0).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item['name']?.toString() ?? 'Specialist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$count slots',
                                style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct,
                              color: const Color(0xFF00D2C4),
                              backgroundColor: const Color(0xFFF1F5F9),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 20),

          // Wait Distribution
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
                Text(
                  'Wait Time Distribution',
                  style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _buildWaitBar('Under 15m', 0.70, const Color(0xFF22C55E)),
                const SizedBox(height: 8),
                _buildWaitBar('15 - 30m', 0.20, Colors.amber),
                const SizedBox(height: 8),
                _buildWaitBar('Over 30m', 0.10, Colors.redAccent),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 25),
        ],
      ),
    );
  }

  Widget _buildWaitBar(String label, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 10),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(pct * 100).toInt()}%',
              style: GoogleFonts.roboto(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            color: color,
            backgroundColor: const Color(0xFFF1F5F9),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildStatMetricCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), color.withOpacity(0.04), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 44,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.6)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF0F172A),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsTab() {
    if (_appointments.isEmpty) {
      return Center(child: Text('No appointments recorded.', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8))));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(),
      itemCount: _appointments.length,
      itemBuilder: (context, index) {
        final apt = _appointments[index];
        final isPending = apt.status == 'pending';
        final statusColor = _getStatusColor(apt.status);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Left accent strip
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              apt.fullName,
                              style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildBadge(apt.status),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Phone: ${apt.phoneNumber}  |  Specialist: ${apt.doctorName ?? "Unassigned"}',
                        style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.date_range, color: Color(0xFF8B5CF6), size: 14),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${apt.preferredDate} at ${apt.preferredTime}',
                              style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (apt.isTelemedicine) ...[
                            const SizedBox(width: 8),
                            Text('Telehealth Session', style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                      if (isPending) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _updateStatus(apt, 'cancelled'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                                  foregroundColor: Colors.redAccent,
                                  elevation: 2,
                                  shadowColor: Colors.redAccent.withOpacity(0.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.close_rounded, size: 16),
                                    const SizedBox(width: 6),
                                    Text('Cancel', style: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _updateStatus(apt, 'approved'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00D2C4),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: const Color(0xFF00D2C4).withOpacity(0.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_rounded, size: 16),
                                    const SizedBox(width: 6),
                                    Text('Approve', style: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
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
              Text('Active Specialists Profiles', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _openAddDoctorDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Doctor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  textStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _doctors.isEmpty
              ? Center(child: Text('No doctor profiles configured.', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _doctors.length,
                  itemBuilder: (context, index) {
                    final doc = _doctors[index];
                    final active = doc['is_active'] == true || doc['is_active'] == 1;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.12),
                            child: const Icon(Icons.person, color: Color(0xFF8B5CF6)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(doc['name']?.toString() ?? '', style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14)),
                                Text(doc['specialization']?.toString() ?? '', style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: ${doc['slot_duration']}m  |  Hours: ${doc['start_time']?.toString().substring(0, 5)} - ${doc['end_time']?.toString().substring(0, 5)}',
                                  style: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: active,
                            activeColor: const Color(0xFF00D2C4),
                            onChanged: (val) {
                              _toggleDoctorActive(doc['id'] as int, val);
                            },
                          ),
                        ],
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
            Icon(Icons.hourglass_empty, color: Color(0xFF64748B), size: 48),
            SizedBox(height: 10),
            Text('Clinic queue is empty.', style: GoogleFonts.roboto(color: Color(0xFF94A3B8))),
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
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text('${index + 1}', style: GoogleFonts.roboto(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apt.fullName,
                      style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Time: ${apt.preferredTime}  |  Specialist: ${apt.doctorName ?? "Unassigned"}',
                      style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 11),
                    ),
                    if (apt.isTelemedicine && apt.meetingLink != null) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _launchUrl(apt.meetingLink!),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.video_call_rounded, color: Color(0xFF00D2C4), size: 13),
                            SizedBox(width: 4),
                            Text('Join Meeting', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11, decoration: TextDecoration.underline)),
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
        );
      },
    );
  }

  Widget _buildQueueActionButton(Appointment apt, String status) {
    if (status == 'approved') {
      return ElevatedButton(
        onPressed: () => _updateStatus(apt, 'arrived'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        child: Text('Arrived', style: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    } else if (status == 'arrived') {
      return ElevatedButton(
        onPressed: () => _updateStatus(apt, 'consulting'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        child: Text('Consult', style: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold)),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening chat with ${apt.fullName}')),
              );
              // TODO: Implement actual chat functionality
            },
          ),
          ElevatedButton(
            onPressed: () => _updateStatus(apt, 'completed'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: Text('Complete', style: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trends and Attendance
          Row(
            children: [
              // Trends simple bar chart
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weekly Booking Trends', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 120,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: trends.isEmpty
                              ? [Center(child: Text('No analytics data', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8))))]
                              : trends.map((t) {
                                  final count = double.tryParse(t['count']?.toString() ?? '0') ?? 0.0;
                                  final maxCount = trends.map((item) => double.tryParse(item['count']?.toString() ?? '0') ?? 1.0).reduce((a, b) => a > b ? a : b);
                                  final heightPct = maxCount > 0 ? (count / maxCount) : 0.0;

                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text('${count.toInt()}', style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 9)),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: (heightPct * 80).clamp(5.0, 80.0),
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00D2C4),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(t['day']?.toString().toUpperCase() ?? '', style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 15),
              // Attendance Rate
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Text('Attendance Rate', style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        width: 70,
                        height: 70,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF8B5CF6), width: 3),
                        ),
                        child: Text(
                          '${(attendanceRate * 100).toInt()}%',
                          style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('VISITS METRIC', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 8)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // No-Show Cards
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
                Text('No-Show Analysis', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _buildNoShowSubCard('MISSED TOTAL', '${_stats['noShow']?['missed_total'] ?? 0}', Colors.redAccent),
                    const SizedBox(width: 12),
                    _buildNoShowSubCard('REPEAT OFFENDERS', '${_stats['noShow']?['repeated_offenders'] ?? 0}', Colors.amber),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNoShowSubCard(String title, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(val, style: GoogleFonts.roboto(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Registration Form
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Register Staff Member',
                  style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _formField(_regName, 'Full Name', Icons.person_outline),
                const SizedBox(height: 10),
                _formField(_regUsername, 'Username', Icons.account_circle_outlined),
                const SizedBox(height: 10),
                _formField(_regPassword, 'Password', Icons.lock_outline, obscureText: true),
                const SizedBox(height: 10),
                _formField(_regPhone, 'Phone (for alerts)', Icons.phone_android_outlined),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _regRole,
                  dropdownColor: Colors.white,
                  decoration: _deco('Staff Role', Icons.badge_outlined),
                  style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontSize: 13),
                  items: [
                    DropdownMenuItem(value: 'doctor', child: Text('Doctor / Specialist', style: GoogleFonts.roboto(color: Color(0xFF0F172A)))),
                    DropdownMenuItem(value: 'admin', child: Text('Administrator', style: GoogleFonts.roboto(color: Color(0xFF0F172A)))),
                    DropdownMenuItem(value: 'lab_technician', child: Text('Lab Technician', style: GoogleFonts.roboto(color: Color(0xFF0F172A)))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _regRole = v);
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _createUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2C4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Register Account', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 25),
          
          // User list
          Text('Staff Registry', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          _users.isEmpty
              ? Center(child: Text('No users found in registry.', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8))))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final u = _users[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.12),
                        child: Text(u.name.substring(0, u.name.length > 1 ? 2 : 1).toUpperCase(), style: GoogleFonts.roboto(color: Color(0xFF8B5CF6))),
                      ),
                      title: Text(u.name, style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('Username: ${u.username}  |  Role: ${u.role.label}', style: GoogleFonts.roboto(color: Color(0xFF64748B), fontSize: 11)),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SMS Gateway Settings', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            _formField(_clinicName, 'Clinic Display Name', Icons.home_work_outlined),
            const SizedBox(height: 10),
            _formField(_smsBaseUrl, 'Intek SMS Gateway URL', Icons.link_rounded),
            const SizedBox(height: 10),
            _formField(_smsSenderId, 'Sender ID (Sender Mask)', Icons.abc_outlined),
            const SizedBox(height: 10),
            _formField(_smsApiKey, 'Gateway Bearer API Token', Icons.key_rounded, obscureText: true),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2C4),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Save Gateway Config', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formField(TextEditingController controller, String hint, IconData icon, {bool obscureText = false}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: GoogleFonts.roboto(color: Color(0xFF0F172A), fontSize: 13),
      decoration: _deco(hint, icon),
    );
  }

  InputDecoration _deco(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 12),
      prefixIcon: Icon(icon, color: const Color(0xFF00D2C4), size: 18),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF00D2C4), width: 1.0),
      ),
    );
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
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.roboto(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  InputDecoration _inputDeco(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.roboto(color: Color(0xFF94A3B8), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.0),
      ),
    );
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
          backgroundColor: Colors.white,
          title: Text('Add New Doctor Profile', style: GoogleFonts.roboto(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: nameC, style: GoogleFonts.roboto(color: Color(0xFF0F172A)), decoration: _inputDeco('Full Name (e.g. Dr. Arthur)')),
                const SizedBox(height: 10),
                TextFormField(controller: specC, style: GoogleFonts.roboto(color: Color(0xFF0F172A)), decoration: _inputDeco('Specialization')),
                const SizedBox(height: 10),
                TextFormField(controller: durC, style: GoogleFonts.roboto(color: Color(0xFF0F172A)), decoration: _inputDeco('Slot Duration (min)'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                TextFormField(controller: startC, style: GoogleFonts.roboto(color: Color(0xFF0F172A)), decoration: _inputDeco('Start Time (e.g. 08:00)')),
                const SizedBox(height: 10),
                TextFormField(controller: endC, style: GoogleFonts.roboto(color: Color(0xFF0F172A)), decoration: _inputDeco('End Time (e.g. 17:00)')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D2C4), foregroundColor: Colors.black),
              child: const Text('ADD PROFILE'),
            )
          ],
        );
      },
    );
  }
}
