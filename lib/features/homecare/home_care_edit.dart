import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'home_care_options.dart';
import 'home_care_repository.dart';

/// Admin edit, and a referring doctor's edit while the request is still open.
Future<HomeCareRequest?> showHomeCareEditSheet(
  BuildContext context,
  HomeCareRequest request,
) {
  return showModalBottomSheet<HomeCareRequest>(
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
              child: _HomeCareEditForm(request: request),
            ),
          ),
        ),
      );
    },
  );
}

class _HomeCareEditForm extends StatefulWidget {
  const _HomeCareEditForm({required this.request});

  final HomeCareRequest request;

  @override
  State<_HomeCareEditForm> createState() => _HomeCareEditFormState();
}

class _HomeCareEditFormState extends State<_HomeCareEditForm> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _phone;
  late final TextEditingController _note;
  late final TextEditingController _custom;
  late Set<String> _options;
  bool _saving = false;
  String? _error;

  bool get _full => widget.request.isOpen && !widget.request.taken;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    _title = TextEditingController(text: request.title);
    _location = TextEditingController(text: request.location ?? '');
    _phone = TextEditingController(text: request.contactPhone ?? '');
    _note = TextEditingController(text: request.note ?? '');
    _custom = TextEditingController(text: request.customOption ?? '');
    _options = request.careOptions.toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _phone.dispose();
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final location = _location.text.trim();
    final phone = _phone.text.trim();
    if (title.isEmpty || location.isEmpty || phone.isEmpty) {
      setState(
        () => _error = 'Enter what is needed, the location, and a contact phone number.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await HomeCareRepository(context.read<ApiClient>()).update(
        id: widget.request.id,
        title: title,
        location: location,
        contactPhone: phone,
        note: _note.text,
        careOptions: _options.toList(),
        customOption: _custom.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on HomeCareFailure catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save this home care request.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
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
          Text('Edit home care request', style: clinicalDisplay(22)),
          const SizedBox(height: 6),
          Text(
            _full
                ? 'Update what is needed, where it is, and the care options. Saving keeps this the same request.'
                : 'You can correct the contact phone and the note. The caregiver who took this request stays assigned.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: healynksMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (_full) ...[
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
          ] else ...[
            Text(request.title, style: clinicalDisplay(18)),
            if ((request.location ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                request.location!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: healynksInk,
                  height: 1.4,
                ),
              ),
            ],
          ],
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
          if (_full)
            HomeCareOptionFields(
              selected: _options,
              onChanged: (next) => setState(() => _options = next),
              custom: _custom,
            )
          else
            HomeCareOptionChips(
              options: request.careOptions,
              customOption: request.customOption,
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
          const SizedBox(height: 16),
          ClinicalPrimaryButton(
            label: 'Save',
            loading: _saving,
            loadingLabel: 'Saving…',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
