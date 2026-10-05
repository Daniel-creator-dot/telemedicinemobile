import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';
import '../patient/notifications_inbox_screen.dart';

/// Badge on the nurse home and home-care board. Opens the existing notification list.
class NurseJobAlertButton extends StatefulWidget {
  const NurseJobAlertButton({super.key});

  @override
  State<NurseJobAlertButton> createState() => _NurseJobAlertButtonState();
}

class _NurseJobAlertButtonState extends State<NurseJobAlertButton> {
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final count = await context.read<CareRepository>().unreadNotificationCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications_none_rounded, color: digiForest),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const NotificationsInboxScreen(
              emptyMessage:
                  'New home care jobs will show up here. Tap one to open it.',
            ),
          ),
        );
        if (mounted) await _refresh();
      },
    );
  }
}
