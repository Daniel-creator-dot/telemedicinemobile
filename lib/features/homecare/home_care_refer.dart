import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../../shared/widgets/home_care_commission.dart';
import 'home_care_edit.dart';
import 'home_care_options.dart';
import 'home_care_repository.dart';
import 'home_care_sent.dart';
import 'home_care_share_actions.dart';

const homeCareDoctorEmpty = 'No home care referrals yet.';

/// Doctor home and the open visit. Lists referrals and opens the refer sheet.
class DoctorHomeCareSection extends StatefulWidget {
  const DoctorHomeCareSection({
    super.key,
    this.patientId,
    this.patientName,
    this.patientPhone,
    this.reloadToken = 0,
  });

  /// When set, the list is this patient's home care only.
  final int? patientId;
  final String? patientName;
  final String? patientPhone;
  final int reloadToken;

  @override
  State<DoctorHomeCareSection> createState() => _DoctorHomeCareSectionState();
}

class _DoctorHomeCareSectionState extends State<DoctorHomeCareSection> {
  List<HomeCareRequest> _requests = [];
  bool _loading = true;
  String? _error;
  int? _busyId;
  int _loadGen = 0;
  Timer? _poll;

  HomeCareRepository get _repo => HomeCareRepository(context.read<ApiClient>());

  int? get _patientId {
    final id = widget.patientId;
    if (id == null || id <= 0) return null;
    return id;
  }

  @override
  void initState() {
    super.initState();
    HomeCareSentNotice.instance.addListener(_onSentNotice);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _load(silent: true);
    });
  }

  void _onSentNotice() {
    if (!mounted) return;
    final latest = HomeCareSentNotice.instance.latest;
    if (latest != null && HomeCareSentNotice.instance.visible) {
      final patientId = _patientId;
      final belongs = patientId == null ||
          latest.patientId == null ||
          latest.patientId == patientId;
      if (belongs) {
        _loadGen++;
        setState(() {
          _requests = placeNewestHomeCareRequest(
            _requests,
            latest.markedSent(referred: true),
          );
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {});
      }
      _load(silent: true);
      return;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant DoctorHomeCareSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId || oldWidget.reloadToken != widget.reloadToken) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    HomeCareSentNotice.instance.removeListener(_onSentNotice);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_loadGen;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _repo.list(patientId: _patientId);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _requests = pinJustPostedHomeCareRequest(
          list,
          HomeCareSentNotice.instance.latest,
          referred: true,
          onlyPatientId: _patientId,
        );
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

  Future<void> _refer() async {
    final id = _patientId;
    final name = widget.patientName?.trim() ?? '';
    final created = await showDoctorHomeCareReferSheet(
      context,
      patient: id == null
          ? null
          : HomeCarePatientChoice(
              id: id,
              name: name.isEmpty ? 'This patient' : name,
              phone: widget.patientPhone,
            ),
      suggestedName: name,
      suggestedPhone: widget.patientPhone,
    );
    if (created == null || !mounted) return;
  }

  Future<void> _edit(HomeCareRequest request) async {
    if (!request.referredByMe || !request.isOpen) return;
    final saved = await showHomeCareEditSheet(context, request);
    if (saved == null || !mounted) return;
    HomeCareSentNotice.instance.replaceLatest(saved);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    await _load(silent: true);
  }

  Future<void> _addNote(HomeCareRequest request) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Timing, access, or what the nurse should know',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.addNote(request.id, text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note added to this home care request.')),
      );
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _close(HomeCareRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark this request closed?'),
        content: const Text(
          'The visit stays on the board as closed. The person who took it is still shown.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Mark closed')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = request.id);
    try {
      await _repo.close(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request marked closed.')),
      );
      await _load(silent: true);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: healynksCanvas,
        borderRadius: BorderRadius.circular(clinicalRadius),
        border: Border.all(color: healynksLine),
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Home care', style: clinicalDisplay(22)),
        const SizedBox(height: 6),
        Text(
          _patientId == null
              ? 'Refer a nurse for a patient you are managing, then follow the request here.'
              : 'Home care for this patient. Nurses and agencies can take an open referral.',
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: healynksMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        ClinicalPrimaryButton(
          label: 'Refer to home care',
          onPressed: _refer,
        ),
        const SizedBox(height: 14),
        if (HomeCareSentNotice.instance.visible) ...[
          HomeCareRequestSentBanner(onDismiss: HomeCareSentNotice.instance.dismiss),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const ClinicalCardSkeleton()
        else if (_error != null)
          DigiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: GoogleFonts.plusJakartaSans(color: const Color(0xFFB42318), height: 1.4)),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          )
        else
          HomeCareDoctorList(
            requests: _requests,
            showPatientName: _patientId == null,
            busyId: _busyId,
            onAddNote: _addNote,
            onClose: _close,
            onEdit: _edit,
          ),
      ],
      ),
    );
  }
}

class HomeCareDoctorList extends StatelessWidget {
  const HomeCareDoctorList({
    super.key,
    required this.requests,
    this.showPatientName = true,
    this.onAddNote,
    this.onClose,
    this.onEdit,
    this.busyId,
  });

  final List<HomeCareRequest> requests;
  final bool showPatientName;
  final Future<void> Function(HomeCareRequest request)? onAddNote;
  final Future<void> Function(HomeCareRequest request)? onClose;
  final Future<void> Function(HomeCareRequest request)? onEdit;
  final int? busyId;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return DigiCard(
        child: Text(
          homeCareDoctorEmpty,
          style: GoogleFonts.plusJakartaSans(fontSize: 15, height: 1.4, color: healynksInk),
        ),
      );
    }
    return Column(
      children: [
        for (final request in requests) ...[
          HomeCareDoctorRequestTile(
            request: request,
            showPatientName: showPatientName,
            busy: busyId == request.id,
            onAddNote: onAddNote == null ? null : () => onAddNote!(request),
            onClose: onClose == null || !request.referredByMe || request.isClosed
                ? null
                : () => onClose!(request),
            onEdit: onEdit == null || !request.referredByMe || !request.isOpen
                ? null
                : () => onEdit!(request),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class HomeCareDoctorRequestTile extends StatelessWidget {
  const HomeCareDoctorRequestTile({
    super.key,
    required this.request,
    this.showPatientName = true,
    this.onAddNote,
    this.onClose,
    this.onEdit,
    this.busy = false,
  });

  final HomeCareRequest request;
  final bool showPatientName;
  final VoidCallback? onAddNote;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final takenName = request.claimerName;
    final pill = request.pillLabel(admin: false);
    final sent = pill == 'Sent';
    return DigiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(request.title, style: clinicalDisplay(18))),
              const SizedBox(width: 8),
              ClinicalStatusPill(
                label: pill,
                tone: sent
                    ? ClinicalTone.forest
                    : request.isOpen
                    ? ClinicalTone.gold
                    : request.isClosed
                        ? ClinicalTone.slate
                        : ClinicalTone.forest,
              ),
            ],
          ),
          if (showPatientName && (request.patientName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.patientName!,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: healynksInk),
            ),
          ],
          if ((request.location ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(request.location!, style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.4, color: healynksInk)),
          ],
          if (request.optionChips.isNotEmpty) ...[
            const SizedBox(height: 8),
            HomeCareOptionChips(
              options: request.careOptions,
              customOption: request.customOption,
            ),
          ],
          if ((request.contactPhone ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(request.contactPhone!, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: healynksMuted)),
          ],
          if (request.taken && takenName.isNotEmpty && !pill.contains(takenName)) ...[
            const SizedBox(height: 8),
            Text(
              'Taken · $takenName',
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: healynksInk),
            ),
          ],
          if (request.isClosed && takenName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Taken · $takenName',
              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: healynksInk),
            ),
          ],
          if ((request.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.note!, style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.4, color: healynksMuted)),
          ],
          if (request.referredByMe) HomeCareShareActions(token: request.shareToken ?? ''),
          if (onEdit != null || onAddNote != null || onClose != null)
            busy
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Wrap(
                    children: [
                      if (onEdit != null)
                        TextButton(onPressed: onEdit, child: const Text('Edit')),
                      if (onAddNote != null)
                        TextButton(onPressed: onAddNote, child: const Text('Add a note')),
                      if (onClose != null)
                        TextButton(onPressed: onClose, child: const Text('Mark closed')),
                    ],
                  ),
        ],
      ),
    );
  }
}

Future<HomeCareRequest?> showDoctorHomeCareReferSheet(
  BuildContext context, {
  HomeCarePatientChoice? patient,
  String? suggestedName,
  String? suggestedPhone,
}) async {
  final sent = await showModalBottomSheet<HomeCareRequest>(
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
            child: SingleChildScrollView(
              child: _DoctorReferForm(
                lockedPatient: patient,
                suggestedName: suggestedName,
                suggestedPhone: suggestedPhone,
              ),
            ),
          ),
        ),
      );
    },
  );
  if (sent != null) HomeCareSentNotice.instance.markSent(sent);
  return sent;
}

class _DoctorReferForm extends StatefulWidget {
  const _DoctorReferForm({
    this.lockedPatient,
    this.suggestedName,
    this.suggestedPhone,
  });

  final HomeCarePatientChoice? lockedPatient;
  final String? suggestedName;
  final String? suggestedPhone;

  @override
  State<_DoctorReferForm> createState() => _DoctorReferFormState();
}

class _DoctorReferFormState extends State<_DoctorReferForm> {
  final _search = TextEditingController();
  final _location = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _custom = TextEditingController();
  Set<String> _options = {};
  Timer? _debounce;
  List<HomeCarePatientChoice> _results = [];
  HomeCarePatientChoice? _selected;
  bool _searching = false;
  bool _sending = false;
  String? _error;
  String? _appliedPhone;

  @override
  void initState() {
    super.initState();
    final locked = widget.lockedPatient;
    if (locked != null) {
      _selected = locked;
      _applyPhone(locked.phone);
    } else {
      final suggested = widget.suggestedPhone?.trim() ?? '';
      if (suggested.isNotEmpty) _applyPhone(suggested);
      final name = widget.suggestedName?.trim() ?? '';
      if (name.isNotEmpty) _search.text = name;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookup(_search.text);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _location.dispose();
    _phone.dispose();
    _title.dispose();
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _applyPhone(String? phone) {
    final next = phone?.trim() ?? '';
    if (next.isEmpty) return;
    if (_phone.text.trim().isEmpty || _phone.text.trim() == (_appliedPhone ?? '')) {
      _phone.text = next;
      _appliedPhone = next;
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _lookup(value));
  }

  Future<void> _lookup(String value) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final rows = await HomeCareRepository(context.read<ApiClient>()).searchPatients(value);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searching = false;
      });
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = err.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Could not search patients.';
      });
    }
  }

  Future<void> _send() async {
    final patient = _selected;
    final title = _title.text.trim();
    final location = _location.text.trim();
    final phone = _phone.text.trim();
    if (patient == null) {
      setState(() => _error = 'Choose the patient you are referring.');
      return;
    }
    if (title.isEmpty || location.isEmpty || phone.isEmpty) {
      setState(
        () => _error = 'Enter what the nurse should do, the location, and a contact phone number.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final created = await HomeCareRepository(context.read<ApiClient>()).create(
        title: title,
        location: location,
        contactPhone: phone,
        note: _note.text,
        patientId: patient.id,
        careOptions: _options.toList(),
        customOption: _custom.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created.markedSent(referred: true));
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send this home care referral.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.lockedPatient != null;
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
              decoration: BoxDecoration(color: healynksLine, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          Text('Refer to home care', style: clinicalDisplay(22)),
          const SizedBox(height: 6),
          Text(
            'A nurse or home-care agency can take this once it is open.',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: healynksMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (locked && _selected != null)
            DigiCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: healynksMuted)),
                  const SizedBox(height: 4),
                  Text(_selected!.name, style: clinicalDisplay(16)),
                  if ((_selected!.phone ?? '').isNotEmpty)
                    Text(_selected!.phone!, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: healynksMuted)),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _search,
              textCapitalization: TextCapitalization.words,
              onChanged: _onSearchChanged,
              decoration: clinicalFieldDecoration(
                'Patient',
                helper: 'Search by name or phone. Your recent patients appear first.',
              ),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Referring ${_selected!.name}',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: healynksInk),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_results.isNotEmpty && _selected == null)
              ..._results.map(
                (patient) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(patient.name, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  subtitle: (patient.phone ?? '').isEmpty ? null : Text(patient.phone!),
                  onTap: () => setState(() {
                    _selected = patient;
                    _results = [];
                    _applyPhone(patient.phone);
                  }),
                ),
              )
            else if (_search.text.trim().length >= 2 && _selected == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No patient matched that search.',
                  style: GoogleFonts.plusJakartaSans(color: healynksMuted),
                ),
              ),
          ],
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
            decoration: clinicalFieldDecoration(
              'Contact phone',
              helper: 'The number the nurse should call. The patient phone is filled in when the record has one.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: clinicalFieldDecoration(
              'What the nurse should do',
              helper: 'For example, wound dressing or blood pressure check',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: clinicalFieldDecoration('Note', helper: 'Optional. Timing, access, or what to bring.'),
          ),
          const SizedBox(height: 12),
          HomeCareOptionFields(
            selected: _options,
            onChanged: (next) => setState(() => _options = next),
            custom: _custom,
          ),
          const SizedBox(height: 12),
          const HealynksHomeCareCommissionNote(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.plusJakartaSans(color: const Color(0xFFB42318), height: 1.4)),
          ],
          const SizedBox(height: 16),
          ClinicalPrimaryButton(
            label: 'Refer to home care',
            loading: _sending,
            loadingLabel: 'Sending…',
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}
