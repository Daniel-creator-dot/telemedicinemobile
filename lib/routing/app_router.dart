import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/doctor/doctor_home_screen.dart';
import '../features/lab_technician/lab_technician_home_screen.dart';
import '../features/nurse/nurse_home_screen.dart';
import '../features/ops/ops_home_screen.dart';
import '../features/pharmacy/pharmacy_home_screen.dart';
import '../features/imaging/imaging_home_screen.dart';
import '../features/corporate/corporate_home_screen.dart';
import '../features/insurance/insurance_home_screen.dart';
import '../features/finance/finance_home_screen.dart';
import '../features/hospital/hospital_home_screen.dart';
import '../features/consult/video_consult_screen.dart';
import '../features/patient/chat_screen.dart';
import '../features/patient/consult_now_screen.dart';
import '../features/patient/doctor_directory_screen.dart';
import '../features/patient/health_journey_screen.dart';
import '../features/patient/health_tracker_screen.dart';
import '../features/patient/edit_profile_screen.dart';
import '../features/patient/medical_profile_screen.dart';
import '../features/patient/care_programs_screen.dart';
import '../features/patient/family_screen.dart';
import '../features/patient/notifications_inbox_screen.dart';
import '../features/patient/patient_home_screen.dart';
import '../features/patient/records_vault_screen.dart';
import '../features/patient/symptom_helper_screen.dart';
import '../features/patient/national_network_screen.dart';
import '../features/patient/family_chart_screen.dart';
import '../features/patient/payments_screen.dart';
import '../features/patient/coverage_screen.dart';
import '../features/patient/membership_screen.dart';
import '../features/patient/phases_screen.dart';
import '../features/patient/support_screen.dart';
import '../features/patient/consents_screen.dart';
import '../features/patient/followups_screen.dart';
import '../features/ops/national_coverage_screen.dart';
import '../models/appointment.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter(Session session) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/login',
    refreshListenable: session,
    redirect: (context, state) {
      if (session.isRestoring) return null;
      final loggedIn = session.isAuthenticated;
      final loc = state.matchedLocation;
      final onAuth = loc == '/login' || loc == '/signup';

      if (!loggedIn) {
        return onAuth ? null : '/login';
      }

      if (onAuth) {
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
      if (path.startsWith('/hospital') && role != 'hospital' && role != 'admin' && role != 'medical_ops') {
        return _homePathFor(role);
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(
        path: '/patient',
        builder: (context, state) => const MainNavigationScreen(),
        routes: [
          GoRoute(path: 'edit-profile', builder: (context, state) => const EditProfileScreen()),
          GoRoute(path: 'profile', builder: (context, state) => const MedicalProfileScreen()),
          GoRoute(path: 'doctors', builder: (context, state) => const DoctorDirectoryScreen()),
          GoRoute(
            path: 'consult-now',
            builder: (context, state) {
              final extra = state.extra;
              final depId = extra is int ? extra : int.tryParse(extra?.toString() ?? '');
              return ConsultNowScreen(dependentPatientId: depId);
            },
          ),
          GoRoute(path: 'journey', builder: (context, state) => const HealthJourneyScreen()),
          GoRoute(path: 'records', builder: (context, state) => const RecordsVaultScreen()),
          GoRoute(path: 'family', builder: (context, state) => const FamilyScreen()),
          GoRoute(path: 'programs', builder: (context, state) => const CareProgramsScreen()),
          GoRoute(path: 'symptom-helper', builder: (context, state) => const SymptomHelperScreen()),
          GoRoute(path: 'network', builder: (context, state) => const NationalNetworkScreen()),
          GoRoute(path: 'payments', builder: (context, state) => const PaymentsScreen()),
          GoRoute(path: 'coverage', builder: (context, state) => const CoverageScreen()),
          GoRoute(path: 'membership', builder: (context, state) => const MembershipScreen()),
          GoRoute(path: 'phases', builder: (context, state) => const PhasesScreen()),
          GoRoute(path: 'support', builder: (context, state) => const SupportScreen()),
          GoRoute(path: 'consents', builder: (context, state) => const ConsentsScreen()),
          GoRoute(path: 'followups', builder: (context, state) => const FollowupsScreen()),
          GoRoute(
            path: 'family/:id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              final name = state.uri.queryParameters['name'];
              return FamilyChartScreen(patientId: id, name: name);
            },
          ),
          GoRoute(path: 'notifications', builder: (context, state) => const NotificationsInboxScreen()),
          GoRoute(path: 'tracker', builder: (context, state) => const HealthTrackerScreen()),
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
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
        routes: [
          GoRoute(path: 'support', builder: (context, state) => const SupportScreen()),
          GoRoute(path: 'network', builder: (context, state) => const NationalCoverageScreen()),
        ],
      ),
      GoRoute(path: '/lab-technician', builder: (context, state) => const LabTechnicianHomeScreen()),
      GoRoute(path: '/nurse', builder: (context, state) => const NurseHomeScreen()),
      GoRoute(
        path: '/ops',
        builder: (context, state) => const OpsHomeScreen(),
        routes: [
          GoRoute(path: 'network', builder: (context, state) => const NationalCoverageScreen()),
          GoRoute(path: 'support', builder: (context, state) => const SupportScreen()),
        ],
      ),
      GoRoute(path: '/pharmacy', builder: (context, state) => const PharmacyHomeScreen()),
      GoRoute(path: '/imaging', builder: (context, state) => const ImagingHomeScreen()),
      GoRoute(path: '/corporate', builder: (context, state) => const CorporateHomeScreen()),
      GoRoute(path: '/insurance', builder: (context, state) => const InsuranceHomeScreen()),
      GoRoute(path: '/finance', builder: (context, state) => const FinanceHomeScreen()),
      GoRoute(path: '/hospital', builder: (context, state) => const HospitalHomeScreen()),
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
    case 'hospital':
      return '/hospital';
    default:
      return '/patient';
  }
}
