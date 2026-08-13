import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<CareRepository>().supportTickets();
      if (!mounted) return;
      setState(() {
        _tickets = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load support.';
        _loading = false;
      });
    }
  }

  Future<void> _open() async {
    final topic = TextEditingController(text: 'care');
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Message support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: topic, decoration: const InputDecoration(labelText: 'Topic (billing, visit, pharmacy…)')),
            TextField(controller: body, maxLines: 4, decoration: const InputDecoration(labelText: 'What happened?')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<CareRepository>().openSupportTicket({
        'topic': topic.text.trim(),
        'body': body.text.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    }
  }

  Future<void> _resolve(Map<String, dynamic> t) async {
    final id = t['id'];
    if (id is! num) return;
    await context.read<CareRepository>().updateSupportTicket(id.toInt(), {
      'status': 'resolved',
      'resolution': 'Resolved by operations',
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<Session>().user?.role.name;
    final staff = role == 'admin' || role == 'medical_ops';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        title: Text(staff ? 'Support desk' : 'Help', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
      ),
      floatingActionButton: staff
          ? null
          : FloatingActionButton.extended(
              onPressed: _open,
              backgroundColor: digiInk,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : _tickets.isEmpty
                  ? ClinicalEmptyState(
                      icon: Icons.support_agent_outlined,
                      title: staff ? 'No tickets' : 'We’re here',
                      message: staff
                          ? 'Patient and partner messages will appear here.'
                          : 'Ask about a visit, a bill, or a pharmacy collection. Clinical emergencies: use Consult Now or local emergency services.',
                      actionLabel: staff ? null : 'Write to support',
                      onAction: staff ? null : _open,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _tickets.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final t = _tickets[i];
                        return DigiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t['ticket_code'] ?? ''} · ${t['topic'] ?? ''}',
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(t['body']?.toString() ?? '', style: GoogleFonts.dmSans(height: 1.4)),
                              const SizedBox(height: 8),
                              Text(
                                '${t['status'] ?? 'open'} · ${t['full_name'] ?? t['user_name'] ?? ''}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
                              ),
                              if (staff && t['status']?.toString() != 'resolved')
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(onPressed: () => _resolve(t), child: const Text('Mark resolved')),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
