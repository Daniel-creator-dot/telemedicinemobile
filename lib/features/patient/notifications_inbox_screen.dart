import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final care = context.read<CareRepository>();
      final items = await care.myNotifications();
      await care.markNotificationsRead();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const ClinicalEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'You are up to date',
                  message: 'Appointment, pharmacy, lab and referral updates will appear here.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: const Icon(Icons.notifications_active_outlined, color: digiViolet),
                        title: Text(
                          n['title']?.toString() ?? 'Update',
                          style: GoogleFonts.roboto(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(n['message']?.toString() ?? ''),
                      );
                    },
                  ),
                ),
    );
  }
}
