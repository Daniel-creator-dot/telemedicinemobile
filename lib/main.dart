import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'core/notification_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/patient/appointments_repository.dart';
import 'features/patient/book_appointment_dialog.dart';
import 'routing/app_router.dart';
import 'models/appointment.dart';
import 'models/auth_user.dart';
import 'models/prescription.dart';
import 'models/consultation.dart';
import 'shared/widgets/app_launch_carousel.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Notification Service
  await NotificationService().initialize();

  final api = ApiClient();
  final session = Session(api);
  
  api.onUnauthorized = () => session.clear();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<Session>.value(value: session),
        Provider(create: (ctx) => AuthRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => AppointmentsRepository(ctx.read<ApiClient>())),
      ],
      child: const TelemedicineApp(),
    ),
  );
}

class TelemedicineApp extends StatefulWidget {
  const TelemedicineApp({super.key});

  @override
  State<TelemedicineApp> createState() => _TelemedicineAppState();
}

class _TelemedicineAppState extends State<TelemedicineApp> {
  late final GoRouter _router;
  bool _splashDone = false;
  String _loadingMessage = 'Securing medical tunnels…';

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _router = createAppRouter(session);
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    
    // Restore user session from secure storage
    await context.read<Session>().restore();

    // Rotate loading messages in sync with the 4-slide carousel
    // Each slide shows for ~3.4s, so we show all 4 before proceeding
    await Future.delayed(const Duration(milliseconds: 3400));
    if (mounted) {
      setState(() => _loadingMessage = 'Syncing health diagnostics…');
    }
    await Future.delayed(const Duration(milliseconds: 3400));
    if (mounted) {
      setState(() => _loadingMessage = 'Establishing HIPAA encryption…');
    }
    await Future.delayed(const Duration(milliseconds: 3400));
    if (mounted) {
      setState(() => _loadingMessage = 'Preparing your dashboard…');
    }

    // Wait for the 4th slide to be visible for ~2 seconds
    const minSplash = Duration(milliseconds: 13600); // 4 slides × 3.4s
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    if (mounted) {
      setState(() => _splashDone = true);
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Digi Health Telemedicine',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF8B5CF6), // Electric Violet
          secondary: Color(0xFF00D2C4), // Emerald Mint
          surface: Colors.white,
          background: Color(0xFFF8FAFC), // Light Slate
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.robotoTextTheme(
          ThemeData.light().textTheme.copyWith(
            titleLarge: GoogleFonts.roboto(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
            headlineMedium: GoogleFonts.roboto(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
            headlineLarge: GoogleFonts.roboto(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
            bodyLarge: GoogleFonts.roboto(
              color: const Color(0xFF0F172A),
            ),
            bodyMedium: GoogleFonts.roboto(
              color: const Color(0xFF0F172A),
            ),
            bodySmall: GoogleFonts.roboto(
              color: const Color(0xFF64748B),
            ),
            labelLarge: GoogleFonts.roboto(
              color: const Color(0xFF0F172A),
            ),
            labelMedium: GoogleFonts.roboto(
              color: const Color(0xFF64748B),
            ),
            labelSmall: GoogleFonts.roboto(
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ),
      routerConfig: _router,
      builder: (context, child) {
        return Consumer<Session>(
          builder: (context, session, _) {
            if (!_splashDone || session.isRestoring) {
              return AppLaunchCarousel(message: _loadingMessage);
            }
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardView(),
    const AppointmentsView(),
    const MessagesView(),
    const ProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: Container(
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
              children: List.generate(4, (index) {
                const icons = [
                  Icons.grid_view_rounded,
                  Icons.calendar_month_rounded,
                  Icons.chat_bubble_outline_rounded,
                  Icons.person_outline_rounded,
                ];
                const activeIcons = [
                  Icons.grid_view_rounded,
                  Icons.calendar_month_rounded,
                  Icons.chat_bubble_rounded,
                  Icons.person_rounded,
                ];
                const labels = ['Overview', 'Schedule', 'Chats', 'Profile'];
                final isActive = _currentIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF00D2C4)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? activeIcons[index] : icons[index],
                          color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels[index],
                          style: GoogleFonts.roboto(
                            color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
                            fontSize: 10,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
  List<AuthUser> _doctors = [];
  Appointment? _nextAppointment;
  bool _loading = true;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final repo = context.read<AppointmentsRepository>();
      final docs = await repo.getAvailableDoctors();
      final myApts = await repo.getMyAppointments();
      
      // Get the next scheduled approved/pending appointment
      final upcoming = myApts.where((a) => a.status == 'pending' || a.status == 'approved').toList();
      
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
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF00D2C4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: const Color(0xFF00D2C4).withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF1E293B),
                    child: Text(
                      session.user?.name.substring(0, session.user!.name.length > 1 ? 2 : 1).toUpperCase() ?? 'SJ',
                      style: GoogleFonts.roboto(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
                            'Your Health in Safe Hands',
                            style: GoogleFonts.roboto(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Access 24/7 medical consultation instantly',
                            style: GoogleFonts.roboto(
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isSearchFocused
                      ? const Color(0xFF00D2C4).withOpacity(0.6)
                      : const Color(0xFFE2E8F0),
                  width: _isSearchFocused ? 2 : 1,
                ),
                boxShadow: _isSearchFocused
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00D2C4).withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                onTap: () => setState(() => _isSearchFocused = true),
                onSubmitted: (_) => setState(() => _isSearchFocused = false),
                style: GoogleFonts.roboto(color: const Color(0xFF0F172A)),
                decoration: InputDecoration(
                  icon: Icon(
                    Icons.search_rounded,
                    color: _isSearchFocused
                        ? const Color(0xFF00D2C4)
                        : theme.colorScheme.primary,
                  ),
                  hintText: 'Search symptoms, specialists, clinics...',
                  hintStyle: GoogleFonts.roboto(
                    color: const Color(0xFF64748B),
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
                    showDialog(
                      context: context,
                      builder: (_) => const BookAppointmentDialog(),
                    ).then((_) => _loadDashboardData());
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
                    // Navigate to Messages tab where prescriptions are located
                    final parentState = context.findAncestorStateOfType<_MainNavigationScreenState>();
                    if (parentState != null) {
                      parentState.setState(() => parentState._currentIndex = 2);
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
                    // Navigate to Appointments tab to see queue status
                    final parentState = context.findAncestorStateOfType<_MainNavigationScreenState>();
                    if (parentState != null) {
                      parentState.setState(() => parentState._currentIndex = 1);
                    }
                  },
                );
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
                                style: GoogleFonts.roboto(
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
                            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
                            Text(
                              'Medical Practitioner',
                              style: GoogleFonts.roboto(
                                color: const Color(0xFF94A3B8),
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
                            onPressed: () {
                              // Launch Meeting Link
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Launching secure video room...')),
                              );
                            },
                            icon: const Icon(Icons.videocam, size: 16),
                            label: Text(
                              'Join Room',
                              style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 6,
                              shadowColor: theme.colorScheme.primary.withOpacity(0.45),
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
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'See All',
                    style: GoogleFonts.roboto(
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
                            return _buildDoctorAvatarCard(
                              context,
                              name: doc.name,
                              specialty: 'Clinical Specialist',
                              rating: '4.9',
                              isOnline: true,
                              initials: doc.name.substring(0, doc.name.length > 1 ? 2 : 1).toUpperCase(),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 85,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
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
                      : color.withOpacity(0.10),
                ),

                // Foreground content
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.roboto(
                          color: color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
  }) {
    final theme = Theme.of(context);

    return Container(
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
              const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
              const SizedBox(width: 4),
              Text(
                rating,
                style: GoogleFonts.roboto(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
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
      
      // Schedule notifications for telemedicine appointments
      final notificationService = NotificationService();
      await notificationService.scheduleAppointmentReminders(list);
      
      setState(() {
        _appointments = list;
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
    try {
      final repo = context.read<AppointmentsRepository>();
      await repo.payForAppointment(apt.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment Approved! Meeting link has been generated.')),
      );
      _fetchAppointments();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: ${e.toString()}')),
      );
    }
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
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
    final upcoming = _appointments.where((a) => a.status == 'pending' || a.status == 'approved').toList();
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
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  letterSpacing: -0.5,
                ),
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
            style: GoogleFonts.roboto(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
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
          
          if (apt.status == 'approved' && apt.isTelemedicine) ...[
            const SizedBox(height: 15),
            if (isUnpaid)
              ElevatedButton.icon(
                onPressed: () => _payCopay(apt),
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Pay Visit Copay (GHS 50.00)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            else if (apt.meetingLink != null)
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
              )
          ]
        ],
      ),
    );
  }
}

// ==================== MESSAGES VIEW ====================
class MessagesView extends StatelessWidget {
  const MessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secure Chats',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 26,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Direct, HIPAA-compliant chat tunnels with your doctors',
            style: GoogleFonts.roboto(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 25),
          
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildChatItem(
                  context,
                  initials: 'OC',
                  name: 'Dr. Olivia Carter',
                  lastMessage: 'Sure, we can check the dosage during our call today.',
                  time: '10:14 AM',
                  unreadCount: 2,
                ),
                _buildChatItem(
                  context,
                  initials: 'JD',
                  name: 'Dr. John Doe',
                  lastMessage: 'Your blood panel reports look completely healthy.',
                  time: 'Yesterday',
                  unreadCount: 0,
                ),
              ],
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
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.03),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
            child: Text(
              initials,
              style: GoogleFonts.roboto(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
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
                color: theme.colorScheme.primary,
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
      setState(() {
        _prescriptions = scripts;
        _consultations = logs;
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
            session.user?.name ?? 'Sarah Jenkins',
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
          Text(
            'Patient ID: #DH-${session.user?.id ?? "00"}-PORTAL',
            style: GoogleFonts.roboto(
              fontSize: 11,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 10),

          Expanded(
            child: _loadingData
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor: Colors.white38,
                          indicatorColor: theme.colorScheme.primary,
                          tabs: const [
                            Tab(text: 'My Prescriptions'),
                            Tab(text: 'Past Consultations'),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildPrescriptionsTab(),
                              _buildConsultationsTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          
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
                pr.medicationName,
                style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Dosage: ${pr.dosage ?? "-"}  |  Frequency: ${pr.frequency ?? "-"}  |  Duration: ${pr.duration ?? "-"}',
                style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11),
              ),
              if (pr.instructions != null && pr.instructions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Instructions: ${pr.instructions}',
                  style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
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
