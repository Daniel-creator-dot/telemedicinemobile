import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/appointment.dart';
import '../../models/chat_message.dart';
import 'care_repository.dart';

class ClinicalChatScreen extends StatefulWidget {
  const ClinicalChatScreen({super.key, required this.appointment});
  final Appointment appointment;

  @override
  State<ClinicalChatScreen> createState() => _ClinicalChatScreenState();
}

class _ClinicalChatScreenState extends State<ClinicalChatScreen> {
  final _input = TextEditingController();
  List<ChatMessage> _messages = [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final care = context.read<CareRepository>();
      final list = await care.getChat(widget.appointment.id);
      if (mounted) setState(() => _messages = list);
      // Mark thread read after a successful fetch so badges clear when opened.
      unawaited(care.markChatRead(widget.appointment.id));
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      await context.read<CareRepository>().sendChat(widget.appointment.id, text);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<Session>().user?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chat · ${widget.appointment.doctorName ?? widget.appointment.fullName}',
          style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final mine = m.senderId.toString() == me;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: mine ? const Color(0xFF8B5CF6) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.senderName, style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.black54)),
                        Text(m.body, style: TextStyle(color: mine ? Colors.white : const Color(0xFF0F172A))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(hintText: 'Secure clinical message'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(onPressed: _send, icon: const Icon(Icons.send, color: Color(0xFF8B5CF6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
