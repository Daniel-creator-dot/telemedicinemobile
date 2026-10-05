import 'dart:async';

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
import 'home_care_claimant.dart';
import 'home_care_edit.dart';
import 'home_care_logic.dart';
import 'home_care_options.dart';
import 'home_care_repository.dart';
import 'home_care_sent.dart';
import 'home_care_share_actions.dart';

/// Admin posts requests at `/admin/homecare`. Nurses and agencies work the board at `/nurse/homecare`.
class HomeCareScreen extends StatefulWidget {
  const HomeCareScreen({super.key, required this.admin});

  final bool admin;

  @override
  State<HomeCareScreen> createState() => _HomeCareScreenState();
}

class _HomeCareScreenState extends State<HomeCareScreen> {
  List<HomeCareRequest> _requests = [];
  bool _loading = true;
  String? _error;
  int? _busyId;
  int _loadGen = 0;
  Timer? _poll;
  final ScrollController _scroll = ScrollController();

  HomeCareRepository get _repo => HomeCareRepository(context.read<ApiClient>());

  @override
  void initState() {
    super.initState();
    HomeCareSentNotice.instance.addListener(_onSentNotice);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    HomeCareSentNotice.instance.removeListener(_onSentNotice);
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onSentNotice() {
    if (!mounted) return;
    final latest = HomeCareSentNotice.instance.latest;
    final pin = widget.admin && latest != null && HomeCareSentNotice.instance.visible;
    if (pin) {
      final already = _requests.any(
        (row) =>
            row.id == latest.id &&
            row.status == latest.status &&
            row.claimant?.phone == latest.claimant?.phone &&
            row.claimant?.name == latest.claimant?.name,
      );
      if (!already) {
        _loadGen++;
        setState(() {
          _requests = placeNewestHomeCareRequest(_requests, latest.markedSent());
          _loading = false;
          _error = null;
        });
        _scrollToTop();
        _load(silent: true);
        return;
      }
    }
    setState(() {});
  }

  /// Keeps the just-posted card current once a nurse takes that job.
  void _publishClaimedNotice(List<HomeCareRequest> list) {
    if (!widget.admin) return;
    final latest = HomeCareSentNotice.instance.latest;
    if (latest == null) return;
    for (final row in list) {
      if (row.id != latest.id) continue;
      final changed = row.status != latest.status ||
          row.taken != latest.taken ||
          row.claimant?.name != latest.claimant?.name ||
          row.claimant?.phone != latest.claimant?.phone;
      if (changed) HomeCareSentNotice.instance.replaceLatest(row);
      return;
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_loadGen;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.list();
      if (!mounted || gen != _loadGen) return;
      _publishClaimedNotice(list);
      setState(() {
        _requests = widget.admin
            ? pinJustPostedHomeCareRequest(
                list,
                HomeCareSentNotice.instance.latest,
              )
            : list;
        _loading = false;
        _error = null;
      });
    } on HomeCareFailure catch (err) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        if (!silent || _requests.isEmpty) _error = err.message;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        if (!silent || _requests.isEmpty) {
          _error = 'Could not load home care requests.';
        }
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await showAdminHomeCareCreateForm(context);
    if (created == null || !mounted) return;
    _scrollToTop();
  }

  Future<void> _close(HomeCareRequest request, {required bool cancel}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          cancel ? 'Cancel this request?' : 'Mark this request closed?',
        ),
        content: Text(
          cancel
              ? 'Nurses and home-care agencies will no longer be able to take it.'
              : 'The visit stays on the board as closed. The person who took it is still shown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(cancel ? 'Cancel request' : 'Mark closed'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.close(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancel ? 'Request cancelled.' : 'Request marked closed.',
          ),
        ),
      );
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _release(HomeCareRequest request) async {
    final confirmed = await confirmReleaseHomeCareJob(context);
    if (!confirmed || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.release(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You released this job. Someone else can take it.'),
        ),
      );
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reactivate(HomeCareRequest request) async {
    final confirmed = await confirmReactivateHomeCareJob(context);
    if (!confirmed || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.reactivate(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This job is open again. Nurses can take it.')),
      );
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(HomeCareRequest request) async {
    final saved = await showHomeCareEditSheet(context, request);
    if (saved == null || !mounted) return;
    HomeCareSentNotice.instance.replaceLatest(saved);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: healynksCanvas,
      appBar: RoleChrome(
        title: 'Home care',
        subtitle: widget.admin
            ? 'Post a request for a nurse or agency'
            : (session.user?.name ?? 'Caregiver'),
        trailing: widget.admin ? const [] : const [NurseJobAlertButton()],
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      bottomNavigationBar: widget.admin
          ? Material(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: ClinicalPrimaryButton(
                    label: 'New home care request',
                    onPressed: _openCreate,
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (widget.admin) ...[
              ClinicalPrimaryButton(
                label: 'New home care request',
                onPressed: _openCreate,
              ),
              const SizedBox(height: 22),
              Text('Posted requests', style: clinicalDisplay(22)),
              const SizedBox(height: 6),
              Text(
                'Open requests stay at the top. When someone takes one, you see their name and when they took it.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: healynksMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (HomeCareSentNotice.instance.visible) ...[
                HomeCareRequestSentBanner(
                  onDismiss: HomeCareSentNotice.instance.dismiss,
                ),
                const SizedBox(height: 12),
              ],
            ] else ...[
              Text('Open requests', style: clinicalDisplay(22)),
              const SizedBox(height: 6),
              Text(
                'Open visits are listed first. When someone takes one, the board shows that it has been taken.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: healynksMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _board(),
          ],
        ),
      ),
    );
  }

  Widget _board() {
    if (_loading) {
      return const Column(
        children: [
          ClinicalCardSkeleton(),
          SizedBox(height: 12),
          ClinicalCardSkeleton(),
        ],
      );
    }
    if (_error != null) {
      return _BoardNotice(message: _error!, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return _BoardNotice(
        title: widget.admin
            ? 'No home care requests yet'
            : 'No home care requests right now',
        message: widget.admin
            ? 'Post one when someone needs a nurse or a home-care agency to visit.'
            : 'When the clinic posts a visit, it will show up here for you to take.',
      );
    }
    return Column(
      children: [
        for (final request in _requests) ...[
          HomeCareRequestCard(
            request: request,
            admin: widget.admin,
            busy: _busyId == request.id,
            onTap: widget.admin || !request.canTake
                ? null
                : () => showHomeCareRequestSheet(
                    context,
                    request,
                    onClaimed: () => _load(silent: true),
                  ),
            onCancel: widget.admin && request.isOpen
                ? () => _close(request, cancel: true)
                : null,
            onClose: widget.admin && request.taken
                ? () => _close(request, cancel: false)
                : null,
            onRelease: !widget.admin && request.mine && request.taken
                ? () => _release(request)
                : null,
            onReactivate: widget.admin && !request.isOpen
                ? () => _reactivate(request)
                : null,
            onEdit: widget.admin ? () => _edit(request) : null,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Opens the admin create form. Returns the request when it was posted.
Future<HomeCareRequest?> showAdminHomeCareCreateForm(BuildContext context) async {
  final posted = await showModalBottomSheet<HomeCareRequest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      final height = MediaQuery.sizeOf(ctx).height;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: height * 0.92),
            child: const SingleChildScrollView(child: _AdminHomeCareCreateForm()),
          ),
        ),
      );
    },
  );
  if (posted != null) HomeCareSentNotice.instance.markSent(posted);
  return posted;
}

class _AdminHomeCareCreateForm extends StatefulWidget {
  const _AdminHomeCareCreateForm();

  @override
  State<_AdminHomeCareCreateForm> createState() => _AdminHomeCareCreateFormState();
}

class _AdminHomeCareCreateFormState extends State<_AdminHomeCareCreateForm> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _custom = TextEditingController();
  Set<String> _options = {};
  bool _posting = false;
  String? _formError;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _phone.dispose();
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    final location = _location.text.trim();
    final phone = _phone.text.trim();
    if (title.isEmpty || location.isEmpty || phone.isEmpty) {
      setState(
        () => _formError = 'Enter what is needed, the location, and a contact phone number.',
      );
      return;
    }
    setState(() {
      _posting = true;
      _formError = null;
    });
    try {
      final created = await HomeCareRepository(context.read<ApiClient>()).create(
        title: title,
        location: location,
        contactPhone: phone,
        note: _note.text,
        careOptions: _options.toList(),
        customOption: _custom.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created.markedSent());
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() => _formError = err.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _formError = 'Could not post this home care request.');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: healynksLine,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Text('New home care request', style: clinicalDisplay(22)),
          const SizedBox(height: 6),
          Text(
            'Say what care is needed, where, and the number the caregiver should call.',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: healynksMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: clinicalFieldDecoration(
              'What is needed',
              helper: 'For example, wound dressing or overnight watch',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            textCapitalization: TextCapitalization.sentences,
            decoration: clinicalFieldDecoration('Location', helper: 'Town, area, or address'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: clinicalFieldDecoration('Contact phone'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: clinicalFieldDecoration(
              'Note',
              helper: 'Optional. Timing, access, or what to bring.',
            ),
          ),
          const SizedBox(height: 12),
          HomeCareOptionFields(
            selected: _options,
            onChanged: (next) => setState(() => _options = next),
            custom: _custom,
          ),
          const SizedBox(height: 12),
          const HealynksHomeCareCommissionNote(),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFB42318), height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          ClinicalPrimaryButton(
            label: 'Post request',
            loading: _posting,
            loadingLabel: 'Posting…',
            onPressed: _posting ? null : _post,
          ),
        ],
      ),
    );
  }
}

/// Compact board on the nurse and agency home.
class HomeCareNurseSection extends StatefulWidget {
  const HomeCareNurseSection({super.key, this.reloadToken = 0});

  final int reloadToken;

  @override
  State<HomeCareNurseSection> createState() => _HomeCareNurseSectionState();
}

class _HomeCareNurseSectionState extends State<HomeCareNurseSection> {
  List<HomeCareRequest> _requests = [];
  bool _loading = true;
  String? _error;
  bool _locked = false;
  int? _busyId;
  Timer? _poll;

  HomeCareRepository get _repo => HomeCareRepository(context.read<ApiClient>());

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeCareNurseSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.list();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
        _error = null;
        _locked = false;
      });
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
        _locked = err.statusCode == 403;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load home care requests.';
        _locked = false;
      });
    }
  }

  Future<void> _release(HomeCareRequest request) async {
    final confirmed = await confirmReleaseHomeCareJob(context);
    if (!confirmed || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.release(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You released this job. Someone else can take it.'),
        ),
      );
      await _load();
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Home care', style: clinicalDisplay(22))),
            TextButton(
              onPressed: () => context.push('/nurse/homecare'),
              child: Text(
                'Open board',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: healynksBlue,
                ),
              ),
            ),
          ],
        ),
        Text(
          'Open visits come first. A taken request stays on the board with the name of who took it.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: healynksMuted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const ClinicalCardSkeleton()
        else if (_locked)
          DigiCard(
            child: Text(
              _error ??
                  'Home care requests open after Healynks approves your account.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: healynksInk,
                height: 1.45,
              ),
            ),
          )
        else if (_error != null)
          _BoardNotice(message: _error!, onRetry: _load)
        else if (_requests.isEmpty)
          const _BoardNotice(
            title: 'No home care requests right now',
            message: 'New visits from the clinic will show up here.',
          )
        else
          for (final request in _requests) ...[
            HomeCareRequestCard(
              request: request,
              admin: false,
              busy: _busyId == request.id,
              onTap: request.canTake
                  ? () => showHomeCareRequestSheet(
                      context,
                      request,
                      onClaimed: _load,
                    )
                  : null,
              onRelease: request.mine && request.taken
                  ? () => _release(request)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _BoardNotice extends StatelessWidget {
  const _BoardNotice({this.title, required this.message, this.onRetry});

  final String? title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: clinicalDisplay(18)),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: healynksInk,
              height: 1.45,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

class HomeCareRequestCard extends StatelessWidget {
  const HomeCareRequestCard({
    super.key,
    required this.request,
    required this.admin,
    this.onTap,
    this.onCancel,
    this.onClose,
    this.onRelease,
    this.onReactivate,
    this.onEdit,
    this.busy = false,
  });

  final HomeCareRequest request;
  final bool admin;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final VoidCallback? onRelease;
  final VoidCallback? onReactivate;
  final VoidCallback? onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final showPrivate = admin || request.isOpen || request.mine;
    final showRelease = onRelease != null && request.mine && request.taken && !request.isOpen;
    final showReactivate = onReactivate != null && admin && !request.isOpen;
    final label = request.pillLabel(admin: admin);
    final tone = label == 'Sent' || request.mine
        ? ClinicalTone.forest
        : request.isOpen
        ? ClinicalTone.gold
        : ClinicalTone.slate;
    final detail = request.takenDetail(admin: admin);
    final person = request.claimedByName?.trim() ?? '';
    final agency = request.claimedByAgency?.trim() ?? '';
    return DigiCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(request.title, style: clinicalDisplay(18))),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClinicalStatusPill(
                    label: label,
                    tone: tone,
                  ),
                  if (request.nearYou) ...[
                    const SizedBox(height: 6),
                    const _NearYouLabel(),
                  ],
                ],
              ),
            ],
          ),
          if (showPrivate && request.location != null) ...[
            const SizedBox(height: 8),
            Text(
              request.location!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: healynksInk,
                height: 1.4,
              ),
            ),
          ],
          if (request.optionChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            HomeCareOptionChips(
              options: request.careOptions,
              customOption: request.customOption,
            ),
          ],
          if (admin && request.patientName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Patient · ${request.patientName}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: healynksInk,
              ),
            ),
          ],
          if (admin && request.referrerName != null) ...[
            const SizedBox(height: 2),
            Text(
              'Referred by ${request.referrerName}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: healynksMuted,
              ),
            ),
          ],
          if (admin && request.contactPhone != null) ...[
            const SizedBox(height: 8),
            HomeCarePatientContactLine(phone: request.contactPhone!),
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
          if (admin && request.claimant != null)
            HomeCareClaimantBlock(claimant: request.claimant!),
          if (admin &&
              request.claimant == null &&
              person.isNotEmpty &&
              agency.isNotEmpty &&
              person != agency) ...[
            const SizedBox(height: 2),
            Text(
              person,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: healynksMuted,
              ),
            ),
          ],
          if (admin)
            HomeCareShareActions(
              token: request.shareToken ?? '',
              requestId: request.id,
              canReshare: request.isOpen && !request.taken,
            ),
          if (!admin) ...[
            const SizedBox(height: 10),
            const HealynksHomeCareCommissionNote(compact: true),
          ],
          if (!admin && request.canTake && onTap != null) ...[
            const SizedBox(height: 12),
            ClinicalPrimaryButton(label: 'Take this request', onPressed: onTap),
          ],
          if (onEdit != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : onEdit,
                child: const Text('Edit'),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showHomeCareAdminChat(context, request),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: Text(admin ? 'Messages' : 'Message admin'),
            ),
          ),
          if (showRelease || showReactivate || onCancel != null || onClose != null)
            Align(
              alignment: Alignment.centerLeft,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showRelease)
                          TextButton(
                            onPressed: onRelease,
                            child: const Text('Release this job'),
                          ),
                        if (showReactivate)
                          TextButton(
                            onPressed: onReactivate,
                            child: const Text('Reactivate'),
                          ),
                        if (onCancel != null || onClose != null)
                          TextButton(
                            onPressed: onCancel ?? onClose,
                            child: Text(
                              onCancel != null ? 'Cancel request' : 'Mark closed',
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _NearYouLabel extends StatelessWidget {
  const _NearYouLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE5F8F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Near you',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0C7A62),
          height: 1.2,
        ),
      ),
    );
  }
}

Future<void> showHomeCareRequestSheet(
  BuildContext context,
  HomeCareRequest request, {
  required Future<void> Function() onClaimed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TakeRequestSheet(request: request, onClaimed: onClaimed),
  );
}

class _TakeRequestSheet extends StatefulWidget {
  const _TakeRequestSheet({required this.request, required this.onClaimed});

  final HomeCareRequest request;
  final Future<void> Function() onClaimed;

  @override
  State<_TakeRequestSheet> createState() => _TakeRequestSheetState();
}

class _TakeRequestSheetState extends State<_TakeRequestSheet> {
  bool _taking = false;
  String? _error;

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Call $phone from your phone.')));
    }
  }

  Future<void> _take() async {
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
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await HomeCareRepository(
        context.read<ApiClient>(),
      ).claim(widget.request.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onClaimed();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'You took this request. Call the contact number when you are ready.',
          ),
        ),
      );
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      final takenBySomeoneElse =
          err.statusCode == 409 &&
          !err.message.toLowerCase().contains('closed');
      if (takenBySomeoneElse) {
        Navigator.of(context).pop();
        await widget.onClaimed();
        messenger.showSnackBar(
          const SnackBar(content: Text('This job has been taken.')),
        );
        return;
      }
      setState(() {
        _taking = false;
        _error = err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _taking = false;
        _error = 'Could not take this request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final showPrivate = request.isOpen || request.mine;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: healynksLine,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(request.title, style: clinicalDisplay(24)),
            if (request.optionChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              HomeCareOptionChips(
                options: request.careOptions,
                customOption: request.customOption,
              ),
            ],
            const SizedBox(height: 8),
            ClinicalStatusPill(
              label: request.isClosed
                  ? 'Closed'
                  : request.isOpen
                  ? 'Open'
                  : request.mine
                  ? 'You took this'
                  : 'Taken',
              tone: request.mine
                  ? ClinicalTone.forest
                  : request.isOpen
                  ? ClinicalTone.gold
                  : ClinicalTone.slate,
            ),
            const SizedBox(height: 16),
            if (!showPrivate)
              Text(
                '${request.claimerLine}. The contact details stay with the person who took it.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: healynksInk,
                  height: 1.45,
                ),
              )
            else ...[
              if (request.location != null)
                _detail('Location', request.location!),
              if (request.contactPhone != null) ...[
                _detail('Contact phone', request.contactPhone!),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _call(request.contactPhone!),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call this number'),
                  ),
                ),
              ],
              if (request.note != null) _detail('Note', request.note!),
              if (request.mine) ...[
                if (request.claimerName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      request.claimerName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: healynksInk,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'This visit is yours. Keep the number so you can reach them.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: healynksMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
            const HealynksHomeCareCommissionNote(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showHomeCareAdminChat(context, request),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Message admin'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFB42318),
                  height: 1.4,
                ),
              ),
            ],
            if (request.isOpen) ...[
              const SizedBox(height: 16),
              ClinicalPrimaryButton(
                label: 'Take this request',
                loading: _taking,
                loadingLabel: 'Taking…',
                onPressed: _taking ? null : _take,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: healynksMuted,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              color: healynksInk,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmReleaseHomeCareJob(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(homeCareReleaseConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Release this job'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<bool> confirmReactivateHomeCareJob(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(homeCareReactivateConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Reactivate'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
