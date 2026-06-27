import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../core/notification_service.dart';
import '../../core/url_helper.dart';
import '../../models/appointment.dart';
import '../../models/auth_user.dart';
import 'appointment_utils.dart';
import 'book_appointment_dialog.dart';
import 'appointments_repository.dart';
// ==================== DASHBOARD VIEW ====================
class DashboardView extends StatefulWidget {
  const DashboardView({super.key, this.onSwitchTab});

  final void Function(int tab)? onSwitchTab;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  List<AuthUser> _doctors = [];
  Appointment? _nextAppointment;
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _loadDashboardData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AuthUser> get _filteredDoctors {
    if (_searchQuery.isEmpty) return _doctors;
    return _doctors.where((d) {
      return d.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  void _openBookingDialog({AuthUser? doctor, bool telemedicine = false}) {
    showDialog(
      context: context,
      builder: (_) => BookAppointmentDialog(
        initialDoctor: doctor,
        initialTelemedicine: telemedicine ? true : null,
      ),
    ).then((_) => _loadDashboardData());
  }

  void _showAllDoctorsSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Our Specialists',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _doctors.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = _doctors[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: const Color(0xFF1E293B),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                      child: Text(
                        doc.name.substring(0, doc.name.length > 1 ? 2 : 1).toUpperCase(),
                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(doc.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Clinical Specialist', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openBookingDialog(doctor: doc, telemedicine: true);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDashboardData() async {
    try {
      final repo = context.read<AppointmentsRepository>();
      final docs = await repo.getAvailableDoctors();
      final myApts = await repo.getMyAppointments();
      
      // Get the next scheduled approved/pending appointment
      final upcoming = myApts.where((a) => a.status == 'pending' || a.status == 'approved').toList()
        ..sort((a, b) => compareAppointmentDates(a.preferredDate, b.preferredDate));
      
      // Schedule notifications for upcoming telemedicine appointments
      final notificationService = NotificationService();
      await notificationService.scheduleAppointmentReminders(upcoming);
      
      setState(() {
        _doctors = docs;
        if (upcoming.isNotEmpty) {
          _nextAppointment = upcoming.first;
        } else {
          _nextAppointment = null;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load dashboard: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: theme.colorScheme.primary,
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
                    Text(
                      'Welcome back,',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    Text(
                      session.user?.name ?? 'Sarah Jenkins',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF1E293B),
                    child: Text(
                      session.user?.name.substring(0, session.user!.name.length > 1 ? 2 : 1).toUpperCase() ?? 'SJ',
                      style: const TextStyle(
                        color: Color(0xFF00D2C4),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF00D2C4).withOpacity(0.15),
                                  border: Border.all(color: const Color(0xFF00D2C4).withOpacity(0.4), width: 1.5),
                                ),
                                child: const Icon(Icons.public_rounded, color: Color(0xFF00D2C4), size: 16),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Digi Health',
                                style: TextStyle(
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
                            'Your Health in Safe Hands',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Access 24/7 medical consultation instantly',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  icon: Icon(
                    Icons.search_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  hintText: 'Search symptoms, specialists, clinics...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 24),

            // Quick Actions
            Text(
              'Quick Actions',
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ).animate().fadeIn(delay: 150.ms),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildQuickAction(
                  context,
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Book Visit',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _openBookingDialog(),
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.videocam_rounded,
                  label: 'Teleconsult',
                  color: const Color(0xFF00D2C4),
                  onTap: () => _openBookingDialog(telemedicine: true),
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.medication_rounded,
                  label: 'Prescriptions',
                  color: const Color(0xFFF59E0B),
                  onTap: () => widget.onSwitchTab?.call(3),
                ),
                const SizedBox(width: 10),
                _buildQuickAction(
                  context,
                  icon: Icons.emergency_rounded,
                  label: 'Emergency',
                  color: const Color(0xFFEF4444),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Emergency Call'),
                        content: const Text(
                          'Call Ghana National Ambulance (193)? Only use for medical emergencies.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                            child: const Text('Call 193'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      await launchPhoneCall('193', context: context);
                    }
                  },
                ),
              ],
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 25),

            // Next Appointment Card
            if (_nextAppointment != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.secondary.withOpacity(0.15),
                      theme.colorScheme.primary.withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.07),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.secondary.withOpacity(0.1),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _nextAppointment!.isTelemedicine ? Icons.videocam_rounded : Icons.local_hospital_rounded,
                                size: 14,
                                color: const Color(0xFF00D2C4),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _nextAppointment!.isTelemedicine ? 'VIDEO VISIT' : 'CLINICAL VISIT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF00D2C4),
                                ),
                              ),
                            ],
                          ),
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
                          backgroundColor: const Color(0xFF1E293B),
                          child: Text(
                            _nextAppointment!.doctorName?.substring(0, 2).toUpperCase() ?? 'MD',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nextAppointment!.doctorName ?? 'Assigned Specialist',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              'Medical Practitioner',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: Colors.white.withOpacity(0.1), height: 1),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: Color(0xFF8B5CF6),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_nextAppointment!.preferredDate}, ${_nextAppointment!.preferredTime}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (_nextAppointment!.isTelemedicine && _nextAppointment!.status == 'approved' && _nextAppointment!.meetingLink != null)
                          ElevatedButton.icon(
                            onPressed: () => launchExternalUrl(
                              _nextAppointment!.meetingLink!,
                              context: context,
                            ),
                            icon: const Icon(Icons.videocam, size: 16),
                            label: Text(
                              'Join Room',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
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
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Synced',
                    style: TextStyle(
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
                        style: TextStyle(
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
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                TextButton(
                  onPressed: _doctors.isEmpty ? null : _showAllDoctorsSheet,
                  child: Text(
                    'See All',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 350.ms),

            const SizedBox(height: 15),

            // Doctors list from database
            _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : _filteredDoctors.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No doctors registered in portal.'
                              : 'No specialists match your search.',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      )
                    : SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _filteredDoctors.length,
                          itemBuilder: (context, index) {
                            final doc = _filteredDoctors[index];
                            return GestureDetector(
                              onTap: () => _openBookingDialog(doctor: doc, telemedicine: true),
                              child: _buildDoctorAvatarCard(
                                context,
                                name: doc.name,
                                specialty: 'Clinical Specialist',
                                rating: '4.9',
                                isOnline: true,
                                initials: doc.name.substring(0, doc.name.length > 1 ? 2 : 1).toUpperCase(),
                              ),
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
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.03),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
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
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
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
                  style: TextStyle(
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
    );
  }

  Widget _buildDoctorAvatarCard(
    BuildContext context, {
    required String name,
    required String specialty,
    required String rating,
    required bool isOnline,
    required String initials,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.03),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isOnline)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F172A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            specialty,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 12),
              const SizedBox(width: 3),
              Text(
                rating,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          )
        ],
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
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
