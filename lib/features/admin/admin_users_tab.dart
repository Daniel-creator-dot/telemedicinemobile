import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/auth_user.dart';

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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                Text('Register staff', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Creates a login that can call the authenticated staff APIs.', style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 12)),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: fieldDecoration('Full name', Icons.person_outline)),
                const SizedBox(height: 10),
                TextField(controller: username, decoration: fieldDecoration('Username', Icons.account_circle_outlined)),
                const SizedBox(height: 10),
                TextField(controller: password, obscureText: true, decoration: fieldDecoration('Password', Icons.lock_outline)),
                const SizedBox(height: 10),
                TextField(controller: phone, decoration: fieldDecoration('Phone (for alerts)', Icons.phone_android_outlined)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
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
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2C4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Staff registry', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          if (users.isEmpty)
            Text('No users returned from /api/users.', style: GoogleFonts.roboto(color: const Color(0xFF94A3B8)))
          else
            ...users.map(
              (u) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  child: Text(
                    u.name.isNotEmpty ? u.name.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF8B5CF6)),
                  ),
                ),
                title: Text(u.name, style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('${u.username} · ${u.role.label}', style: GoogleFonts.roboto(color: const Color(0xFF64748B), fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}
