import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'core/notification_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/patient/appointments_repository.dart';
import 'features/patient/care_repository.dart';
import 'routing/app_router.dart';
import 'shared/widgets/app_launch_carousel.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Firebase/notifications unavailable: $e');
  }

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
        Provider(create: (ctx) => CareRepository(ctx.read<ApiClient>())),
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
  String _loadingMessage = 'Opening Digi Health…';

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

    if (mounted) {
      setState(() => _loadingMessage = 'Preparing your care workspace…');
    }
    const minSplash = Duration(milliseconds: 1600);
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
