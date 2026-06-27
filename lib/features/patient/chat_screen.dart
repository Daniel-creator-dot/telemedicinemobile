import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/chat_thread.dart';
import 'chat_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.thread});

  final ChatThread thread;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final userId = int.tryParse(context.read<Session>().user?.id ?? '') ?? 0;
    try {
      final repo = context.read<ChatRepository>();
      final list = await repo.getMessages(widget.thread.id, userId);
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final userId = int.tryParse(context.read<Session>().user?.id ?? '') ?? 0;
    setState(() => _sending = true);
    try {
      final repo = context.read<ChatRepository>();
      final msg = await repo.sendMessage(
        threadId: widget.thread.id,
        body: text,
        currentUserId: userId,
      );
      _controller.clear();
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(widget.thread.otherName),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Start a secure conversation with your doctor.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMessages,
                        color: theme.colorScheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return Align(
                              alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                                ),
                                decoration: BoxDecoration(
                                  color: msg.isMine
                                      ? theme.colorScheme.primary
                                      : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  msg.body,
                                  style: TextStyle(
                                    color: msg.isMine ? Colors.white : Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
