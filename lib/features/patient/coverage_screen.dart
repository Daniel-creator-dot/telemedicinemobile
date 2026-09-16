import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class CoverageScreen extends StatefulWidget {
  const CoverageScreen({super.key});

  @override
  State<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends State<CoverageScreen> {
  Map<String, dynamic> _eligibility = {};
  List<Map<String, dynamic>> _insurers = [];
  List<Map<String, dynamic>> _corporates = [];
  List<Map<String, dynamic>> _hints = [];
  Map<String, dynamic>? _checkResult;

  String _source = 'insurance';
  int? _payerId;
  final _memberKey = TextEditingController();
  bool _loading = true;
  bool _checking = false;
  bool _attaching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memberKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final care = context.read<CareRepository>();
      final elig = await care.eligibility();
      final payers = await care.billingPayers();
      if (!mounted) return;
      setState(() {
        _eligibility = elig;
        _insurers = ((payers['insurers'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _corporates = ((payers['corporates'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _hints = ((payers['demo_hints'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _payerId ??= _source == 'insurance'
            ? (_insurers.isNotEmpty ? _insurers.first['id'] as int? : null)
            : (_corporates.isNotEmpty ? _corporates.first['id'] as int? : null);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load coverage.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _payerOptions =>
      _source == 'insurance' ? _insurers : _corporates;

  Future<void> _check() async {
    final key = _memberKey.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _source == 'insurance' ? 'Enter a policy number.' : 'Enter a corporate staff ID.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _checking = true;
      _checkResult = null;
    });
    try {
      final result = await context.read<CareRepository>().checkEligibility(
            source: _source,
            memberKey: key,
            payerId: _payerId,
          );
      if (!mounted) return;
      setState(() {
        _checkResult = result;
        if (result['current'] is Map) {
          _eligibility = Map<String, dynamic>.from(result['current'] as Map);
        }
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check failed: $e')),
      );
    }
  }

  Future<void> _attach() async {
    final key = _memberKey.text.trim();
    if (key.isEmpty) return;
    setState(() => _attaching = true);
    try {
      final result = await context.read<CareRepository>().attachCoverage(
            source: _source,
            memberKey: key,
            payerId: _payerId,
          );
      if (!mounted) return;
      final elig = result['eligibility'] is Map
          ? Map<String, dynamic>.from(result['eligibility'] as Map)
          : await context.read<CareRepository>().eligibility();
      if (!mounted) return;
      setState(() {
        _eligibility = elig;
        _attaching = false;
        _checkResult = {
          'matched': true,
          'eligible': elig['eligible'] == true,
          'can_attach': false,
          'already_linked': true,
          'message': result['message']?.toString() ?? 'Coverage attached',
          'preview': result['preview'],
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            elig['eligible'] == true
                ? 'Covered · ${elig['payer_name']} · copay GHS ${elig['copay']}'
                : 'Coverage updated',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _attaching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach: $e')),
      );
    }
  }

  void _applyHint(Map<String, dynamic> hint) {
    final source = hint['source']?.toString() ?? 'insurance';
    setState(() {
      _source = source;
      _memberKey.text = hint['member_key']?.toString() ?? '';
      _checkResult = null;
      final options = source == 'insurance' ? _insurers : _corporates;
      _payerId = options.isNotEmpty ? options.first['id'] as int? : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final covered = _eligibility['eligible'] == true;
    final preview = _checkResult?['preview'] is Map
        ? Map<String, dynamic>.from(_checkResult!['preview'] as Map)
        : null;
    final canAttach = _checkResult?['can_attach'] == true;

    return Scaffold(
      backgroundColor: digiPaper,
      appBar: AppBar(
        title: Text('Insurance & cover', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: digiForest))
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: digiForest,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      Text(
                        'Check eligibility',
                        style: GoogleFonts.sourceSerif4(fontSize: 28, fontWeight: FontWeight.w600, height: 1.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verify insurance or corporate staff cover, then attach it so booking and Consult Now use the right copay.',
                        style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                      ),
                      const SizedBox(height: 20),
                      SectionLabel('On your chart now'),
                      const SizedBox(height: 8),
                      DigiCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  covered ? Icons.verified_outlined : Icons.money_outlined,
                                  color: covered ? digiForest : digiSlate,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    covered ? 'Covered' : 'Self pay',
                                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ),
                                Text(
                                  'GHS ${_eligibility['copay'] ?? 50}',
                                  style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              covered
                                  ? '${_eligibility['payer_name'] ?? 'Payer'} · ${_eligibility['plan_name'] ?? _eligibility['source'] ?? 'cover'}'
                                  : 'Full consult fee applies until you attach a scheme.',
                              style: GoogleFonts.dmSans(color: digiSlate),
                            ),
                            if ((_eligibility['policy_number'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'ID ${_eligibility['policy_number']}',
                                style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                              ),
                            ],
                            if (covered) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Covered amount GHS ${_eligibility['covered_amount'] ?? 0} · ${_eligibility['coverage_percent'] ?? 0}%',
                                style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SectionLabel('Verify a policy or staff ID'),
                      const SizedBox(height: 8),
                      DigiCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'insurance', label: Text('Insurance'), icon: Icon(Icons.health_and_safety_outlined, size: 16)),
                                ButtonSegment(value: 'corporate', label: Text('Corporate'), icon: Icon(Icons.business_outlined, size: 16)),
                              ],
                              selected: {_source},
                              onSelectionChanged: (s) {
                                setState(() {
                                  _source = s.first;
                                  _checkResult = null;
                                  final options = _payerOptions;
                                  _payerId = options.isNotEmpty ? options.first['id'] as int? : null;
                                });
                              },
                            ),
                            const SizedBox(height: 14),
                            if (_payerOptions.isNotEmpty)
                              InputDecorator(
                                decoration: InputDecoration(
                                  labelText: _source == 'insurance' ? 'Insurer' : 'Employer scheme',
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: _payerOptions.any((p) => p['id'] == _payerId)
                                        ? _payerId
                                        : _payerOptions.first['id'] as int?,
                                    items: _payerOptions
                                        .map(
                                          (p) => DropdownMenuItem<int>(
                                            value: p['id'] as int?,
                                            child: Text(
                                              '${p['name']}${p['plan_name'] != null ? ' · ${p['plan_name']}' : ''}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      _payerId = v;
                                      _checkResult = null;
                                    }),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _memberKey,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [UpperCaseTextFormatter()],
                              decoration: InputDecoration(
                                labelText: _source == 'insurance' ? 'Policy number' : 'Staff ID',
                                hintText: _source == 'insurance' ? 'e.g. DEMO-SHG-1001' : 'e.g. GPA-STAFF-9001',
                                border: const OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _check(),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _checking ? null : _check,
                              icon: _checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.search),
                              label: Text(_checking ? 'Checking…' : 'Check eligibility'),
                              style: FilledButton.styleFrom(
                                backgroundColor: digiForest,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_hints.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Demo IDs', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiSlate)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _hints
                              .map(
                                (h) => ActionChip(
                                  label: Text(h['member_key']?.toString() ?? ''),
                                  onPressed: () => _applyHint(h),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      if (_checkResult != null) ...[
                        const SizedBox(height: 20),
                        SectionLabel('Result'),
                        const SizedBox(height: 8),
                        DigiCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _checkResult!['eligible'] == true
                                        ? Icons.check_circle_outline
                                        : Icons.cancel_outlined,
                                    color: _checkResult!['eligible'] == true ? digiForest : Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _checkResult!['eligible'] == true ? 'Eligible / covered' : 'Not covered',
                                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _checkResult!['message']?.toString() ?? '',
                                style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
                              ),
                              if (preview != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  '${preview['payer_name'] ?? ''} · ${preview['plan_name'] ?? preview['source']}',
                                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Copay GHS ${preview['copay']} · cover ${preview['coverage_percent']}% · covered GHS ${preview['covered_amount']}',
                                  style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
                                ),
                                if ((preview['member_name'] ?? '').toString().isNotEmpty)
                                  Text(
                                    'Member ${preview['member_name']}',
                                    style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
                                  ),
                              ],
                              if (canAttach) ...[
                                const SizedBox(height: 14),
                                FilledButton(
                                  onPressed: _attaching ? null : _attach,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: digiForest,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(46),
                                  ),
                                  child: Text(_attaching ? 'Attaching…' : 'Attach to my account'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SectionLabel('Use cover on a visit'),
                      const SizedBox(height: 8),
                      DigiCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              covered
                                  ? 'Your next consult will collect copay GHS ${_eligibility['copay']} via Paystack (MoMo or card).'
                                  : 'Without attached cover, the full GHS ${_eligibility['consult_fee'] ?? 50} consult fee applies.',
                              style: GoogleFonts.dmSans(color: digiSlate, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => context.push('/patient/consult-now'),
                              icon: const Icon(Icons.videocam_outlined, size: 18),
                              label: const Text('Consult Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: digiForest,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/patient/payments'),
                              icon: const Icon(Icons.receipt_long_outlined, size: 18),
                              label: const Text('Payments & receipts'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => context.push('/patient/membership'),
                              child: const Text('Or join Classic · Premium · Gold · Diamond'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
