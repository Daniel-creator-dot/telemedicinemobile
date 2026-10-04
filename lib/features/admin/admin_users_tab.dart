import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/auth_user.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'admin_chrome.dart';

class PendingSignup {
  const PendingSignup({
    required this.userId,
    required this.kind,
    required this.name,
    required this.phone,
    required this.detail,
    this.region,
    this.town,
    this.createdAt,
  });

  final int userId;
  final String kind;
  final String name;
  final String phone;
  final String detail;
  final String? region;
  final String? town;
  final String? createdAt;
}

List<PendingSignup> parsePendingSignups(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final out = <PendingSignup>[];

  void addAll(dynamic rawList, String kind) {
    if (rawList is! List) return;
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = int.tryParse(map['user_id']?.toString() ?? '');
      if (id == null) continue;
      final detail = kind == 'agency'
          ? (map['agency_name']?.toString() ?? 'Nurse agency')
          : (map['specialty']?.toString() ?? 'Doctor');
      out.add(
        PendingSignup(
          userId: id,
          kind: kind,
          name: map['name']?.toString() ?? '',
          phone: map['phone']?.toString() ?? '',
          detail: detail,
          region: map['region']?.toString(),
          town: map['town']?.toString(),
          createdAt: map['created_at']?.toString(),
        ),
      );
    }
  }

  addAll(data['doctors'], 'doctor');
  addAll(data['agencies'], 'agency');
  return out;
}

String formatSignupWhen(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = dt.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
}

class AdminUsersTab extends StatelessWidget {
  const AdminUsersTab({
    super.key,
    required this.users,
    required this.signups,
    required this.decidingUserId,
    required this.onDecide,
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
  final List<PendingSignup> signups;
  final int? decidingUserId;
  final void Function(int userId, String decision) onDecide;
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
          _pendingReview(),
          const SizedBox(height: 20),
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
                    subtitle: Text(
                      '${u.username} · ${u.role.label}${_reviewFlag(u.verificationStatus)}',
                      style: adminSans(size: 11, color: AdminPalette.mute),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _reviewFlag(String? status) {
    switch (status) {
      case 'pending':
        return ' · Pending review';
      case 'rejected':
        return ' · Not approved';
      default:
        return '';
    }
  }

  Widget _pendingReview() {
    final doctors = signups.where((s) => s.kind == 'doctor').toList();
    final agencies = signups.where((s) => s.kind == 'agency').toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: digiPaper,
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: digiLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ClinicalPageHeader(
            title: 'Pending review',
            subtitle: 'Doctors and nurse agencies waiting for a decision.',
          ),
          if (signups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Nobody is waiting for review.',
                style: GoogleFonts.dmSans(fontSize: 14, color: digiSlate),
              ),
            )
          else ...[
            if (doctors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Doctors', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiSlate)),
              ...doctors.map(_signupTile),
            ],
            if (agencies.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Nurse agencies', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: digiSlate)),
              ...agencies.map(_signupTile),
            ],
          ],
        ],
      ),
    ).animate().fadeIn(duration: 240.ms);
  }

  Widget _signupTile(PendingSignup signup) {
    final busy = decidingUserId == signup.userId;
    final place = [signup.region, signup.town].where((part) => part != null && part.trim().isNotEmpty).join(' · ');
    final when = formatSignupWhen(signup.createdAt);
    final headline = signup.kind == 'agency' && signup.detail.isNotEmpty ? signup.detail : signup.name;
    final bits = <String>[
      if (signup.kind == 'agency' && signup.name.isNotEmpty) signup.name,
      if (signup.kind == 'doctor' && signup.detail.isNotEmpty) signup.detail,
      if (place.isNotEmpty) place,
      if (signup.phone.isNotEmpty) signup.phone,
      if (when.isNotEmpty) when,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(clinicalRadius),
          border: Border.all(color: digiLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  headline.isEmpty ? 'Signup' : headline,
                  style: GoogleFonts.sourceSerif4(fontSize: 18, fontWeight: FontWeight.w600, color: digiInk),
                ),
                const ClinicalStatusPill(label: 'Pending review', tone: ClinicalTone.gold),
              ],
            ),
            if (bits.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(bits.join(' · '), style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => onDecide(signup.userId, 'approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: digiForest,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: digiForest.withValues(alpha: 0.35),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(clinicalRadius)),
                  ),
                  child: Text(busy ? 'Saving…' : 'Approve'),
                ),
                TextButton(
                  onPressed: busy ? null : () => onDecide(signup.userId, 'reject'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF8C3A2F)),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
