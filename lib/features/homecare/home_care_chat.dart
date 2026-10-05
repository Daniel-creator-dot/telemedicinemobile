import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'home_care_logic.dart';
import 'home_care_repository.dart';

/// Opens the request thread without leaving the board.
/// A bottom sheet on a phone, a side panel on a wide screen.
Future<void> showHomeCareAdminChat(
  BuildContext context,
  HomeCareRequest request,
) {
  final wide = MediaQuery.sizeOf(context).width >= 840;
  if (wide) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close messages',
      barrierColor: const Color(0x660E1525),
      pageBuilder: (ctx, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.white,
            elevation: 16,
            child: SizedBox(
              width: 420,
              height: MediaQuery.sizeOf(ctx).height,
              child: HomeCareChatPanel(request: request),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.78;
      return SizedBox(
        height: height,
        child: HomeCareChatPanel(request: request),
      );
    },
  );
}

class HomeCareChatPanel extends StatefulWidget {
  const HomeCareChatPanel({
    super.key,
    required this.request,
    this.loadMessages,
    this.sendMessage,
    this.viewerId,
  });

  final HomeCareRequest request;

  /// Overrides the network call so the panel can be shown without a session.
  final Future<List<HomeCareMessage>> Function()? loadMessages;
  final Future<void> Function(String body)? sendMessage;
  final String? viewerId;

  @override
  State<HomeCareChatPanel> createState() => _HomeCareChatPanelState();
}

class _HomeCareChatPanelState extends State<HomeCareChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<HomeCareMessage> _messages = [];
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  HomeCareRepository get _repo => HomeCareRepository(context.read<ApiClient>());

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_sending) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final list = widget.loadMessages != null
          ? await widget.loadMessages!()
          : await _repo.messages(widget.request.id);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _jumpToEnd();
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load messages. Try again.';
      });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (widget.sendMessage != null) {
        await widget.sendMessage!(text);
      } else {
        await _repo.sendMessage(widget.request.id, text);
      }
      if (!mounted) return;
      _input.clear();
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send that message. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.loadMessages != null
        ? widget.viewerId
        : context.watch<Session>().user?.id;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Message admin', style: clinicalDisplay(18)),
                        const SizedBox(height: 2),
                        Text(
                          widget.request.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: healynksMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: healynksInk),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: healynksLine),
            Expanded(child: _thread(me)),
            const Divider(height: 1, color: healynksLine),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: clinicalFieldDecoration('Write the admin'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ClinicalPrimaryButton(
                    label: 'Send',
                    expand: false,
                    loading: _sending,
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thread(String? me) {
    if (_loading && _messages.isEmpty) {
      return Center(
        child: Text(
          'Loading messages…',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: healynksMuted,
          ),
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: healynksInk,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No messages yet. Write the admin about this request.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: healynksInk,
              height: 1.45,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length + (_error == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (_error != null && index == _messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFFB42318),
                height: 1.4,
              ),
            ),
          );
        }
        final message = _messages[index];
        final mine =
            message.senderId != null && message.senderId.toString() == me;
        final when = formatHomeCareWhen(message.createdAt);
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: mine ? const Color(0xFFEAF1FF) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: healynksLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${message.senderName} · ${homeCareRoleLabel(message.senderRole)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: healynksInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.body,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: healynksInk,
                    height: 1.4,
                  ),
                ),
                if (when != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    when,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: healynksMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
