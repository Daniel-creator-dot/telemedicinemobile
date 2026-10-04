import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/api_client.dart';
import 'core/brand.dart';
import 'core/session.dart';
import 'core/notification_service.dart';
import 'features/auth/auth_repository.dart';
import 'features/patient/appointments_repository.dart';
import 'features/patient/care_repository.dart';
import 'routing/app_router.dart';
import 'shared/widgets/app_launch_carousel.dart';
import 'shared/widgets/clinical_ui.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

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

  unawaited(_initPush());
}

Future<void> _initPush() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 6));
    await NotificationService().initialize().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Firebase/notifications unavailable: $e');
  }
}

class TelemedicineApp extends StatefulWidget {
  const TelemedicineApp({super.key});

  @override
  State<TelemedicineApp> createState() => _TelemedicineAppState();
}

class _TelemedicineAppState extends State<TelemedicineApp> {
  late final GoRouter _router;
  bool _splashDone = false;
  String _loadingMessage = 'Opening ${AppBrand.name}…';

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _router = createAppRouter(session);
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    
    try {
      await context.read<Session>().restore().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Session restore timed out or failed: $e');
    }

    if (mounted) {
      setState(() => _loadingMessage = 'Preparing your care workspace…');
    }
    const minSplash = Duration(milliseconds: 3000);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }

    if (mounted) {
      setState(() => _splashDone = true);
      NotificationService().flushPendingNavigation();
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
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: healynksBlue,
          secondary: healynksTeal,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: healynksInk,
          onSurface: healynksInk,
        ),
        scaffoldBackgroundColor: healynksCanvas,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: healynksInk,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: clinicalDisplay(20),
        ),
        textTheme: GoogleFonts.dmSansTextTheme(
          ThemeData.light().textTheme.copyWith(
            headlineLarge: clinicalDisplay(32),
            headlineMedium: clinicalDisplay(26),
            titleLarge: clinicalDisplay(20),
            bodyLarge: GoogleFonts.dmSans(color: healynksInk, height: 1.45),
            bodyMedium: GoogleFonts.dmSans(color: healynksInk, height: 1.4),
            bodySmall: GoogleFonts.dmSans(color: healynksMuted),
            labelLarge: GoogleFonts.dmSans(color: healynksInk, fontWeight: FontWeight.w600),
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
