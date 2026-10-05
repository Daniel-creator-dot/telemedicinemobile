import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'home_care_logic.dart';
import 'home_care_repository.dart';

/// Android and iOS tests and devices get a Share label.
/// share_plus is not a dependency, so Share copies the same public URL.
bool homeCareOfferShareLabel() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

Future<void> copyHomeCareLink(BuildContext context, String url) async {
  try {
    await Clipboard.setData(ClipboardData(text: url));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not copy that link. Select it and copy it instead.'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copied.')),
  );
}

class HomeCareShareActions extends StatelessWidget {
  const HomeCareShareActions({
    super.key,
    required this.token,
    this.requestId,
    this.canReshare = false,
    this.reshare,
  });

  final String token;

  /// Set on an open job the admin or referring doctor can send again.
  final int? requestId;
  final bool canReshare;

  /// Test hook. Production posts to the reshare route.
  final Future<int> Function(int requestId)? reshare;

  @override
  Widget build(BuildContext context) {
    final url = homeCarePublicUrl(token);
    if (url == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Anyone with this link can sign in and assess the job.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.4,
            color: healynksMuted,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          url,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: healynksInk,
            height: 1.35,
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => copyHomeCareLink(context, url),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy link'),
            ),
            if (canReshare && requestId != null && requestId! > 0)
              _ReshareHomeCareButton(
                requestId: requestId!,
                reshare: reshare,
              ),
            if (homeCareOfferShareLabel())
              TextButton.icon(
                onPressed: () => copyHomeCareLink(context, url),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReshareHomeCareButton extends StatefulWidget {
  const _ReshareHomeCareButton({required this.requestId, this.reshare});

  final int requestId;
  final Future<int> Function(int requestId)? reshare;

  @override
  State<_ReshareHomeCareButton> createState() => _ReshareHomeCareButtonState();
}

class _ReshareHomeCareButtonState extends State<_ReshareHomeCareButton> {
  bool _sending = false;

  Future<void> _press() async {
    if (_sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send this job to nurses again?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send again'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final send = widget.reshare ??
          (int id) => HomeCareRepository(context.read<ApiClient>()).reshare(id);
      await send(widget.requestId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent to nurses again.')),
      );
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send this job to nurses again.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _sending ? null : _press,
      icon: const Icon(Icons.campaign_outlined, size: 18),
      label: Text(_sending ? 'Sending…' : 'Reshare'),
    );
  }
}
