import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/auth_user.dart';
import 'admin_chrome.dart';

class AdminUsersTab extends StatelessWidget {
  const AdminUsersTab({
    super.key,
    required this.users,
    required this.name,
    required this.username,
    required this.password,
    required this.phone,
    required this.role,
    required this.onRoleChanged,
    required this.onCreate,
    required this.fieldDecoration,
  });

  final List<AuthUser> users;
  final TextEditingController name;
  final TextEditingController username;
  final TextEditingController password;
  final TextEditingController phone;
  final String role;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onCreate;
  final InputDecoration Function(String, IconData) fieldDecoration;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Register staff', style: adminSerif(size: 20)),
                const SizedBox(height: 6),
                Text(
                  'Creates a login that can call authenticated staff APIs.',
                  style: adminSans(size: 12, color: AdminPalette.mute),
                ),
                const SizedBox(height: 14),
                TextField(controller: name, style: adminSans(), decoration: fieldDecoration('Full name', Icons.person_outline)),
                const SizedBox(height: 10),
                TextField(controller: username, style: adminSans(), decoration: fieldDecoration('Username', Icons.account_circle_outlined)),
                const SizedBox(height: 10),
                TextField(controller: password, obscureText: true, style: adminSans(), decoration: fieldDecoration('Password', Icons.lock_outline)),
                const SizedBox(height: 10),
                TextField(controller: phone, style: adminSans(), decoration: fieldDecoration('Phone (for alerts)', Icons.phone_android_outlined)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  dropdownColor: AdminPalette.surface,
                  style: adminSans(),
                  decoration: fieldDecoration('Staff role', Icons.badge_outlined),
                  items: const [
                    DropdownMenuItem(value: 'doctor', child: Text('Doctor / Specialist')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                    DropdownMenuItem(value: 'lab_technician', child: Text('Lab technician')),
                    DropdownMenuItem(value: 'nurse', child: Text('Nurse / Triage')),
                    DropdownMenuItem(value: 'medical_ops', child: Text('Medical operations')),
                    DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
                    DropdownMenuItem(value: 'imaging', child: Text('Imaging')),
                    DropdownMenuItem(value: 'corporate', child: Text('Corporate')),
                    DropdownMenuItem(value: 'insurance', child: Text('Insurance')),
                    DropdownMenuItem(value: 'finance', child: Text('Finance')),
                  ],
                  onChanged: (v) {
                    if (v != null) onRoleChanged(v);
                  },
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 20),
          Text('Staff registry', style: adminSerif(size: 18)),
          const SizedBox(height: 10),
          if (users.isEmpty)
            Text('No users returned from /api/users.', style: adminSans(color: AdminPalette.mute))
          else
            ...users.map(
              (u) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdminGlass(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AdminPalette.violet.withValues(alpha: 0.22),
                      child: Text(
                        u.name.isNotEmpty ? u.name.substring(0, 1).toUpperCase() : '?',
                        style: adminSans(weight: FontWeight.w800, color: AdminPalette.violet),
                      ),
                    ),
                    title: Text(u.name, style: adminSans(size: 14, weight: FontWeight.w800)),
                    subtitle: Text('${u.username} · ${u.role.label}', style: adminSans(size: 11, color: AdminPalette.mute)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
