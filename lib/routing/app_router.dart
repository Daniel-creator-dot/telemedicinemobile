import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/doctor/doctor_home_screen.dart';
import '../features/lab_technician/lab_technician_home_screen.dart';
import '../main.dart'; // Contains MainNavigationScreen for Patients

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

      // Role authorization check
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

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/patient',
        builder: (context, state) => const MainNavigationScreen(),
      ),
      GoRoute(
        path: '/doctor',
        builder: (context, state) => const DoctorHomeScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
      ),
      GoRoute(
        path: '/lab-technician',
        builder: (context, state) => const LabTechnicianHomeScreen(),
      ),
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
  if (role == 'doctor') {
    return '/doctor';
  } else if (role == 'admin') {
    return '/admin';
  } else if (role == 'lab_technician') {
    return '/lab-technician';
  } else {
    return '/patient';
  }
}
