import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/doctor/doctor_home_screen.dart';
import '../features/lab_technician/lab_technician_home_screen.dart';
import '../features/nurse/nurse_home_screen.dart';
import '../features/ops/ops_home_screen.dart';
import '../features/pharmacy/pharmacy_home_screen.dart';
import '../features/imaging/imaging_home_screen.dart';
import '../features/corporate/corporate_home_screen.dart';
import '../features/insurance/insurance_home_screen.dart';
import '../features/finance/finance_home_screen.dart';
import '../features/consult/video_consult_screen.dart';
import '../features/patient/chat_screen.dart';
import '../features/patient/consult_now_screen.dart';
import '../features/patient/doctor_directory_screen.dart';
import '../features/patient/medical_profile_screen.dart';
import '../main.dart';
import '../models/appointment.dart';

GoRouter createAppRouter(Session session) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: session,
    redirect: (context, state) {
      if (session.isRestoring) return null;
      final loggedIn = session.isAuthenticated;
      final onLogin = state.matchedLocation == '/login';

      if (!loggedIn) {
        return onLogin ? null : '/login';
      }

      if (onLogin) {
        return _homePathFor(session.user!.role.name);
      }

      final role = session.user!.role.name;
      final path = state.matchedLocation;
      if (path.startsWith('/patient') && role != 'patient') {
        return _homePathFor(role);
      }
      if (path.startsWith('/doctor') && role != 'doctor') {
        return _homePathFor(role);
      }
      if (path.startsWith('/admin') && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/lab-technician') && role != 'lab_technician') {
        return _homePathFor(role);
      }
      if (path.startsWith('/nurse') && role != 'nurse' && role != 'medical_ops' && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/ops') && role != 'medical_ops' && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/pharmacy') && role != 'pharmacy' && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/imaging') && role != 'imaging' && role != 'admin' && role != 'lab_technician') {
        return _homePathFor(role);
      }
      if (path.startsWith('/corporate') && role != 'corporate' && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/insurance') && role != 'insurance' && role != 'admin') {
        return _homePathFor(role);
      }
      if (path.startsWith('/finance') && role != 'finance' && role != 'admin') {
        return _homePathFor(role);
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/patient',
        builder: (context, state) => const MainNavigationScreen(),
        routes: [
          GoRoute(path: 'profile', builder: (context, state) => const MedicalProfileScreen()),
          GoRoute(path: 'doctors', builder: (context, state) => const DoctorDirectoryScreen()),
          GoRoute(path: 'consult-now', builder: (context, state) => const ConsultNowScreen()),
          GoRoute(
            path: 'chat',
            builder: (context, state) {
              final apt = state.extra;
              if (apt is Appointment) return ClinicalChatScreen(appointment: apt);
              return const Scaffold(body: Center(child: Text('No consultation selected')));
            },
          ),
          GoRoute(
            path: 'video',
            builder: (context, state) {
              final apt = state.extra;
              if (apt is Appointment) return VideoConsultScreen(appointment: apt);
              return const Scaffold(body: Center(child: Text('No consultation selected')));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/doctor',
        builder: (context, state) => const DoctorHomeScreen(),
        routes: [
          GoRoute(
            path: 'video',
            builder: (context, state) {
              final apt = state.extra;
              if (apt is Appointment) {
                return VideoConsultScreen(appointment: apt, isClinician: true);
              }
              return const Scaffold(body: Center(child: Text('No consultation selected')));
            },
          ),
        ],
      ),
      GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreen()),
      GoRoute(path: '/lab-technician', builder: (context, state) => const LabTechnicianHomeScreen()),
      GoRoute(path: '/nurse', builder: (context, state) => const NurseHomeScreen()),
      GoRoute(path: '/ops', builder: (context, state) => const OpsHomeScreen()),
      GoRoute(path: '/pharmacy', builder: (context, state) => const PharmacyHomeScreen()),
      GoRoute(path: '/imaging', builder: (context, state) => const ImagingHomeScreen()),
      GoRoute(path: '/corporate', builder: (context, state) => const CorporateHomeScreen()),
      GoRoute(path: '/insurance', builder: (context, state) => const InsuranceHomeScreen()),
      GoRoute(path: '/finance', builder: (context, state) => const FinanceHomeScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          state.error?.toString() ?? 'Route not found',
          style: GoogleFonts.roboto(color: Colors.white),
        ),
      ),
    ),
  );
}

String _homePathFor(String role) {
  switch (role) {
    case 'doctor':
      return '/doctor';
    case 'admin':
      return '/admin';
    case 'lab_technician':
      return '/lab-technician';
    case 'nurse':
      return '/nurse';
    case 'medical_ops':
      return '/ops';
    case 'pharmacy':
      return '/pharmacy';
    case 'imaging':
      return '/imaging';
    case 'corporate':
      return '/corporate';
    case 'insurance':
      return '/insurance';
    case 'finance':
      return '/finance';
    default:
      return '/patient';
  }
}
