import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../../shared/widgets/home_care_commission.dart';
import '../nurse/nurse_job_alerts.dart';
import 'home_care_chat.dart';
import 'home_care_edit.dart';
import 'home_care_logic.dart';
import 'home_care_options.dart';
import 'home_care_repository.dart';
import 'home_care_share_actions.dart';

/// Opens one home-care job from the public Healynks share link.
class HomeCareLinkScreen extends StatefulWidget {
  const HomeCareLinkScreen({super.key, required this.token});

  final String token;

  @override
  State<HomeCareLinkScreen> createState() => _HomeCareLinkScreenState();
}

class _HomeCareLinkScreenState extends State<HomeCareLinkScreen> {
  HomeCareShareSnapshot? _snapshot;
  bool _loading = true;
  bool _taking = false;
  String? _error;
  String? _actionError;
  Session? _session;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    if (!homeCareShareTokenOk(widget.token)) {
      _loading = false;
      _error = 'This link does not match a home care request.';
      return;
    }
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<Session>();
    if (!identical(_session, session)) {
      _session?.removeListener(_onSession);
      _session = session;
      session.addListener(_onSession);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted && homeCareShareTokenOk(widget.token)) _load();
  }

  Future<void> _load() async {
    if (!homeCareShareTokenOk(widget.token)) return;
    final gen = ++_loadGen;
    try {
      final snapshot = await HomeCareRepository(
        context.read<ApiClient>(),
      ).openShare(widget.token);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } on HomeCareFailure catch (err) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = 'Could not open this home care request.';
      });
    }
  }

  String _loginPath() {
    final next = homeCareJobPath('/homecare/${widget.token}');
    if (next == null) return '/login';
    return Uri(path: '/login', queryParameters: {'next': next}).toString();
  }

  String _joinPath() {
    final next = homeCareJobPath('/homecare/${widget.token}');
    return Uri(
      path: '/join',
      queryParameters: {
        'as': 'nurse',
        if (next != null) 'next': next,
      },
    ).toString();
  }

  Future<void> _edit(HomeCareRequest request) async {
    final saved = await showHomeCareEditSheet(context, request);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    await _load();
  }

  Future<void> _take(HomeCareRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Take this request?'),
        content: const Text(healynksHomeCareCommission),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Take this request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _taking = true;
      _actionError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await HomeCareRepository(context.read<ApiClient>()).claim(request.id);
      if (!mounted) return;
      await _load();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'You took this request. Call the contact number when you are ready.',
          ),
        ),
      );
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      if (err.statusCode == 409 && !err.message.toLowerCase().contains('closed')) {
        await _load();
        messenger.showSnackBar(
          const SnackBar(content: Text('This job has been taken.')),
        );
        return;
      }
      setState(() => _actionError = err.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not take this request.');
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final signedIn = session.isAuthenticated;
    final role = session.user?.role.name;
    final nurse = role == 'nurse';
    return Scaffold(
      backgroundColor: healynksCanvas,
      appBar: signedIn
          ? RoleChrome(
              title: 'Home care',
              subtitle: session.user?.name ?? 'Healynks',
              onRefresh: _load,
              trailing: nurse ? const [NurseJobAlertButton()] : const [],
              onLogout: () async {
                await session.clear();
                if (context.mounted) context.go(_loginPath());
              },
            )
          : AppBar(
              backgroundColor: healynksCanvas,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              foregroundColor: healynksInk,
              title: Text('Home care', style: clinicalDisplay(20)),
            ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ClinicalCardSkeleton(),
                      SizedBox(height: 12),
                      ClinicalCardSkeleton(),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (_error != null)
                      DigiCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_error!, style: _body),
                            const SizedBox(height: 8),
                            TextButton(onPressed: _load, child: const Text('Try again')),
                          ],
                        ),
                      )
                    else if (_snapshot != null)
                      _snapshot!.limited || _snapshot!.request == null
                          ? HomeCareShareGuestCard(
                              title: _snapshot!.title,
                              location: _snapshot!.location,
                              status: _snapshot!.status,
                              taken: _snapshot!.taken,
                              careOptions: _snapshot!.careOptions,
                              customOption: _snapshot!.customOption,
                              message: _guestMessage(session, _snapshot!),
                              showActions: !signedIn,
                              onSignIn: () => context.go(_loginPath()),
                              onJoin: () => context.go(_joinPath()),
                            )
                          : HomeCareShareReviewCard(
                              request: _snapshot!.request!,
                              admin: role == 'admin',
                              showCommission: nurse,
                              showShareLink: role == 'admin' ||
                                  _snapshot!.request!.referredByMe ||
                                  _snapshot!.request!.referrerUserId?.toString() ==
                                      session.user?.id,
                              shareToken: widget.token,
                              taking: _taking,
                              error: _actionError,
                              onTake: nurse && _snapshot!.request!.canTake
                                  ? () => _take(_snapshot!.request!)
                                  : null,
                              onMessage: (nurse || role == 'admin')
                                  ? () => showHomeCareAdminChat(
                                      context,
                                      _snapshot!.request!,
                                    )
                                  : null,
                              onEdit: role == 'admin' ||
                                      (_snapshot!.request!.referredByMe &&
                                          _snapshot!.request!.isOpen)
                                  ? () => _edit(_snapshot!.request!)
                                  : null,
                            ),
                  ],
                ),
        ),
      ),
    );
  }

  String _guestMessage(Session session, HomeCareShareSnapshot snapshot) {
    final status = (session.user?.verificationStatus ?? '').toLowerCase();
    final nurse = session.user?.role.name == 'nurse';
    if (snapshot.pendingReview || (nurse && status == 'pending')) {
      return 'Healynks still has to approve your profile before you can take this job.';
    }
    if (!session.isAuthenticated) {
      return 'Sign in, or join as a nurse, to review this home care job.';
    }
    if (nurse && status == 'rejected') {
      return 'Your account was not approved, so you cannot take this job.';
    }
    return 'An approved nurse or home-care agency can take this job.';
  }
}

TextStyle get _body => GoogleFonts.plusJakartaSans(
  fontSize: 15,
  color: healynksInk,
  height: 1.45,
);

class HomeCareShareGuestCard extends StatelessWidget {
  const HomeCareShareGuestCard({
    super.key,
    required this.title,
    required this.status,
    required this.taken,
    required this.message,
    this.location,
    this.careOptions = const [],
    this.customOption,
    this.showActions = false,
    this.onSignIn,
    this.onJoin,
  });

  final String title;
  final String? location;
  final List<String> careOptions;
  final String? customOption;
  final String status;
  final bool taken;
  final String message;
  final bool showActions;
  final VoidCallback? onSignIn;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final closed = status == 'closed';
    final label = taken || status == 'claimed'
        ? 'Taken'
        : closed
        ? 'Closed'
        : 'Open';
    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: clinicalDisplay(22)),
          const SizedBox(height: 10),
          ClinicalStatusPill(
            label: label,
            tone: label == 'Open' ? ClinicalTone.gold : ClinicalTone.slate,
          ),
          if ((location ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(location!, style: _body),
          ],
          if (homeCareChipLabels(careOptions, customOption).isNotEmpty) ...[
            const SizedBox(height: 12),
            HomeCareOptionChips(options: careOptions, customOption: customOption),
          ],
          const SizedBox(height: 12),
          const HealynksHomeCareCommissionNote(),
          const SizedBox(height: 12),
          Text(message, style: _body),
          if (showActions) ...[
            const SizedBox(height: 16),
            ClinicalPrimaryButton(label: 'Sign in', onPressed: onSignIn),
            const SizedBox(height: 10),
            ClinicalSecondaryButton(
              label: 'Join as a nurse',
              onPressed: onJoin,
            ),
          ],
        ],
      ),
    );
  }
}

class HomeCareShareReviewCard extends StatelessWidget {
  const HomeCareShareReviewCard({
    super.key,
    required this.request,
    required this.admin,
    required this.showCommission,
    required this.showShareLink,
    required this.shareToken,
    this.taking = false,
    this.error,
    this.onTake,
    this.onMessage,
    this.onEdit,
  });

  final HomeCareRequest request;
  final bool admin;
  final bool showCommission;
  final bool showShareLink;
  final String shareToken;
  final bool taking;
  final String? error;
  final VoidCallback? onTake;
  final VoidCallback? onMessage;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final label = request.pillLabel(admin: admin);
    final tone = label == 'Sent' || request.mine
        ? ClinicalTone.forest
        : request.isOpen
        ? ClinicalTone.gold
        : ClinicalTone.slate;
    final detail = request.takenDetail(admin: admin);
    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.title, style: clinicalDisplay(22)),
          const SizedBox(height: 10),
          ClinicalStatusPill(label: label, tone: tone),
          if ((request.patientName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Patient · ${request.patientName}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: healynksInk,
              ),
            ),
          ],
          if ((request.location ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.location!, style: _body),
          ],
          if (request.optionChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            HomeCareOptionChips(
              options: request.careOptions,
              customOption: request.customOption,
            ),
          ],
          if ((request.contactPhone ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Contact phone',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: healynksMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(request.contactPhone!, style: _body),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _call(context, request.contactPhone!),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Call this number'),
              ),
            ),
          ],
          if ((request.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Note',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: healynksMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(request.note!, style: _body),
          ],
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: healynksInk,
                height: 1.35,
              ),
            ),
          ],
          if (showCommission) ...[
            const SizedBox(height: 12),
            const HealynksHomeCareCommissionNote(),
          ],
          if (showShareLink)
            HomeCareShareActions(
              token: shareToken,
              requestId: request.id,
              canReshare: request.isOpen && !request.taken,
            ),
          if ((error ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFB42318),
                height: 1.4,
              ),
            ),
          ],
          if (onTake != null) ...[
            const SizedBox(height: 12),
            ClinicalPrimaryButton(
              label: 'Take this request',
              loading: taking,
              loadingLabel: 'Taking…',
              onPressed: taking ? null : onTake,
            ),
          ],
          if (onEdit != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: taking ? null : onEdit,
                child: const Text('Edit'),
              ),
            ),
          if (onMessage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text(admin ? 'Messages' : 'Message admin'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call $phone from your phone.')),
      );
    }
  }
}
