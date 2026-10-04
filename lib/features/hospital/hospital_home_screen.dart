import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../shared/widgets/clinical_ui.dart';
import '../patient/care_repository.dart';

class HospitalHomeScreen extends StatefulWidget {
  const HospitalHomeScreen({super.key});

  @override
  State<HospitalHomeScreen> createState() => _HospitalHomeScreenState();
}

class _HospitalHomeScreenState extends State<HospitalHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;
  String _inboundFilter = 'open';
  Timer? _poll;
  late final TabController _tabs;

  final _bedTotal = TextEditingController();
  final _bedAvail = TextEditingController();
  final _icuTotal = TextEditingController();
  final _icuAvail = TextEditingController();
  final _capacityNotes = TextEditingController();
  String _networkStatus = 'online';

  final _patientCode = TextEditingController();
  final _specialty = TextEditingController();
  final _reason = TextEditingController();
  int? _toOrgId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    _bedTotal.dispose();
    _bedAvail.dispose();
    _icuTotal.dispose();
    _icuAvail.dispose();
    _capacityNotes.dispose();
    _patientCode.dispose();
    _specialty.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await context.read<CareRepository>().hospitalDesk();
      if (!mounted) return;
      final cap = (data['capacity'] as Map?)?.cast<String, dynamic>() ?? {};
      _bedTotal.text = '${cap['bed_total'] ?? ''}';
      _bedAvail.text = '${cap['bed_available'] ?? ''}';
      _icuTotal.text = '${cap['icu_total'] ?? ''}';
      _icuAvail.text = '${cap['icu_available'] ?? ''}';
      _capacityNotes.text = cap['capacity_notes']?.toString() ?? '';
      _networkStatus = cap['network_status']?.toString() ?? 'online';
      final destinations = _asList(data['destinations']);
      if (_toOrgId == null && destinations.isNotEmpty) {
        _toOrgId = _idOf(destinations.first);
      }
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic> get _hospital =>
      (_data['hospital'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get _stats =>
      (_data['stats'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get _capacity =>
      (_data['capacity'] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _list(String key) => _asList(_data[key]);

  int _idOf(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is int) return id;
    return int.tryParse('$id') ?? 0;
  }

  List<Map<String, dynamic>> get _filteredInbound {
    final all = _list('inbound').isNotEmpty ? _list('inbound') : _list('referrals');
    switch (_inboundFilter) {
      case 'pending':
        return all.where((r) => (r['status']?.toString() ?? 'pending') == 'pending').toList();
      case 'active':
        return all
            .where((r) => ['accepted', 'in_progress'].contains(r['status']?.toString()))
            .toList();
      case 'done':
        return all
            .where((r) => ['completed', 'declined'].contains(r['status']?.toString()))
            .toList();
      case 'open':
        return all
            .where((r) => !['completed', 'declined'].contains(r['status']?.toString() ?? 'pending'))
            .toList();
      default:
        return all;
    }
  }

  Future<void> _updateReferral(Map r, String status, {String? notes}) async {
    final id = _idOf(Map<String, dynamic>.from(r));
    if (id == 0) return;
    try {
      await context.read<CareRepository>().updateReferral(id, {
        'status': status,
        'result_notes': ?notes,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Referral marked $status')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _complete(Map r) async {
    final notes = TextEditingController(text: r['result_notes']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Return referral outcome'),
        content: TextField(
          controller: notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Specialist / facility notes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true) return;
    await _updateReferral(r, 'completed', notes: notes.text.trim());
  }

  Future<void> _saveCapacity() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().updateHospitalCapacity({
        'bed_total': int.tryParse(_bedTotal.text.trim()),
        'bed_available': int.tryParse(_bedAvail.text.trim()),
        'icu_total': int.tryParse(_icuTotal.text.trim()),
        'icu_available': int.tryParse(_icuAvail.text.trim()),
        'network_status': _networkStatus,
        'capacity_notes': _capacityNotes.text.trim(),
      });
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Capacity published to the network')));
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Capacity update failed: $e')));
    }
  }

  Future<void> _createOutbound() async {
    if (_toOrgId == null || _reason.text.trim().isEmpty || _patientCode.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient code, destination, and reason are required')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CareRepository>().createHospitalOutbound({
        'patient_code': _patientCode.text.trim(),
        'to_org_id': _toOrgId,
        'specialty': _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
        'reason': _reason.text.trim(),
        'urgency': 'routine',
      });
      _patientCode.clear();
      _specialty.clear();
      _reason.clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Outbound transfer posted')));
      _tabs.animateTo(2);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Outbound failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final title = _hospital['name']?.toString().isNotEmpty == true
        ? _hospital['name'].toString()
        : 'Hospital network desk';
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: RoleChrome(
        title: title,
        subtitle: '${_hospital['region'] ?? 'Ghana'} · referrals · capacity · partners',
        onRefresh: _load,
        onLogout: () async {
          await session.clear();
          if (context.mounted) context.go('/login');
        },
      ),
      body: _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!, style: const TextStyle(fontSize: 12)),
                    actions: [
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                TabBar(
                  controller: _tabs,
                  labelColor: digiForest,
                  unselectedLabelColor: digiSlate,
                  indicatorColor: digiGold,
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Inbound'),
                    Tab(text: 'Outbound'),
                    Tab(text: 'Capacity'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _OverviewTab(
                        hospital: _hospital,
                        stats: _stats,
                        capacity: _capacity,
                        partners: _list('partners'),
                        note: _data['note']?.toString(),
                        onOpenInbound: () => _tabs.animateTo(1),
                        onOpenOutbound: () => _tabs.animateTo(2),
                        onOpenCapacity: () => _tabs.animateTo(3),
                      ),
                      _InboundTab(
                        rows: _filteredInbound,
                        filter: _inboundFilter,
                        onFilter: (f) => setState(() => _inboundFilter = f),
                        onUpdate: _updateReferral,
                        onComplete: _complete,
                      ),
                      _OutboundTab(
                        rows: _list('outbound'),
                        destinations: _list('destinations'),
                        patientCode: _patientCode,
                        specialty: _specialty,
                        reason: _reason,
                        toOrgId: _toOrgId,
                        onDestination: (id) => setState(() => _toOrgId = id),
                        onCreate: _createOutbound,
                      ),
                      _CapacityTab(
                        bedTotal: _bedTotal,
                        bedAvail: _bedAvail,
                        icuTotal: _icuTotal,
                        icuAvail: _icuAvail,
                        notes: _capacityNotes,
                        networkStatus: _networkStatus,
                        onStatus: (s) => setState(() => _networkStatus = s),
                        onSave: _saveCapacity,
                        partners: _list('partners'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.hospital,
    required this.stats,
    required this.capacity,
    required this.partners,
    required this.onOpenInbound,
    required this.onOpenOutbound,
    required this.onOpenCapacity,
    this.note,
  });

  final Map<String, dynamic> hospital;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> capacity;
  final List<Map<String, dynamic>> partners;
  final String? note;
  final VoidCallback onOpenInbound;
  final VoidCallback onOpenOutbound;
  final VoidCallback onOpenCapacity;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Network coordination',
          style: GoogleFonts.sourceSerif4(fontSize: 22, fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          '${hospital['town'] ?? hospital['region'] ?? 'Ghana'} · '
          '${capacity['network_status'] ?? hospital['network_status'] ?? 'online'} · '
          'occupancy ${capacity['occupancy_pct'] ?? stats['bed_occupancy_pct'] ?? 0}%',
          style: GoogleFonts.dmSans(color: digiSlate),
        ),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(note!, style: GoogleFonts.dmSans(fontSize: 13, color: digiSlate, height: 1.4)),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 150,
              child: StatTile(label: 'Inbound open', value: '${stats['inbound_open'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Pending accept', value: '${stats['inbound_pending'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'In progress', value: '${stats['inbound_in_progress'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Outbound open', value: '${stats['outbound_open'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(
                label: 'Beds free',
                value: '${stats['bed_available'] ?? 0}/${stats['bed_total'] ?? 0}',
                accent: digiGold,
              ),
            ),
            SizedBox(
              width: 150,
              child: StatTile(
                label: 'ICU free',
                value: '${stats['icu_available'] ?? 0}/${stats['icu_total'] ?? 0}',
              ),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Partners online', value: '${stats['partners_online'] ?? 0}'),
            ),
            SizedBox(
              width: 150,
              child: StatTile(label: 'Partners busy', value: '${stats['partners_busy'] ?? 0}'),
            ),
          ],
        ),
        if (partners.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Regional partner status',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
          ),
          const SizedBox(height: 8),
          ...partners.take(6).map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p['name'] ?? ''} · ${p['type'] ?? ''}',
                      style: GoogleFonts.dmSans(color: digiSlate),
                    ),
                  ),
                  Text(
                    (p['network_status'] ?? 'online').toString().toUpperCase(),
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _statusColor(p['network_status']?.toString()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: digiForest),
              onPressed: onOpenInbound,
              child: const Text('Inbound queue'),
            ),
            OutlinedButton(onPressed: onOpenOutbound, child: const Text('Send outbound')),
            OutlinedButton(onPressed: onOpenCapacity, child: const Text('Update capacity')),
          ],
        ),
      ],
    );
  }
}

class _InboundTab extends StatelessWidget {
  const _InboundTab({
    required this.rows,
    required this.filter,
    required this.onFilter,
    required this.onUpdate,
    required this.onComplete,
  });

  final List<Map<String, dynamic>> rows;
  final String filter;
  final ValueChanged<String> onFilter;
  final Future<void> Function(Map r, String status, {String? notes}) onUpdate;
  final Future<void> Function(Map r) onComplete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final f in const [
              ('open', 'Open'),
              ('pending', 'Pending'),
              ('active', 'Active'),
              ('done', 'Closed'),
              ('all', 'All'),
            ])
              FilterChip(
                label: Text(f.$2),
                selected: filter == f.$1,
                onSelected: (_) => onFilter(f.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const ClinicalEmptyState(
            icon: Icons.local_hospital_outlined,
            title: 'No inbound referrals',
            message: 'When a clinician refers a patient to this facility, the case will appear here.',
          )
        else
          ...rows.map((r) {
            final status = r['status']?.toString() ?? 'pending';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DigiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['referral_code']?.toString() ?? 'Referral',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: digiForest),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r['full_name'] ?? r['patient_name'] ?? ''} · ${r['patient_code'] ?? ''} · ${r['specialty'] ?? ''}',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${r['urgency'] ?? 'routine'} · $status'
                      '${r['from_doctor_name'] != null ? ' · from ${r['from_doctor_name']}' : ''}\n'
                      '${r['reason'] ?? r['clinical_summary'] ?? ''}',
                      style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.4),
                    ),
                    if ((r['result_notes'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Outcome: ${r['result_notes']}', style: GoogleFonts.dmSans(fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (status == 'pending')
                          FilledButton(
                            onPressed: () => onUpdate(r, 'accepted'),
                            child: const Text('Accept'),
                          ),
                        if (status == 'accepted' || status == 'pending')
                          FilledButton.tonal(
                            onPressed: () => onUpdate(r, 'in_progress'),
                            child: const Text('In progress'),
                          ),
                        if (status != 'completed' && status != 'declined')
                          FilledButton(
                            onPressed: () => onComplete(r),
                            child: const Text('Complete'),
                          ),
                        if (status == 'pending')
                          TextButton(
                            onPressed: () => onUpdate(r, 'declined'),
                            child: const Text('Decline'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _OutboundTab extends StatelessWidget {
  const _OutboundTab({
    required this.rows,
    required this.destinations,
    required this.patientCode,
    required this.specialty,
    required this.reason,
    required this.toOrgId,
    required this.onDestination,
    required this.onCreate,
  });

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> destinations;
  final TextEditingController patientCode;
  final TextEditingController specialty;
  final TextEditingController reason;
  final int? toOrgId;
  final ValueChanged<int> onDestination;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Post outbound transfer',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: patientCode,
          decoration: const InputDecoration(
            labelText: 'Patient code (e.g. DH-000001)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: destinations.any((d) => (d['id'] is int ? d['id'] : int.tryParse('${d['id']}')) == toOrgId)
              ? toOrgId
              : null,
          decoration: const InputDecoration(
            labelText: 'Destination facility',
            border: OutlineInputBorder(),
          ),
          items: destinations
              .map(
                (d) => DropdownMenuItem<int>(
                  value: d['id'] is int ? d['id'] as int : int.tryParse('${d['id']}') ?? 0,
                  child: Text('${d['name']} (${d['type']})'),
                ),
              )
              .where((i) => i.value != 0)
              .toList(),
          onChanged: (v) {
            if (v != null) onDestination(v);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: specialty,
          decoration: const InputDecoration(
            labelText: 'Specialty (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: digiForest),
          onPressed: onCreate,
          child: const Text('Send outbound referral'),
        ),
        const SizedBox(height: 20),
        Text(
          'Outbound ledger',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const ClinicalEmptyState(
            icon: Icons.call_made_outlined,
            title: 'No outbound transfers yet',
            message: 'Use the form above when this facility needs capacity or a specialty elsewhere.',
          )
        else
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DigiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['referral_code']?.toString() ?? 'Referral',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: digiForest),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r['full_name'] ?? r['patient_name'] ?? ''} · ${r['patient_code'] ?? ''}',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '→ ${r['to_org_name'] ?? 'Facility'} · ${r['specialty'] ?? ''} · ${r['status'] ?? 'pending'}\n'
                      '${r['reason'] ?? ''}',
                      style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CapacityTab extends StatelessWidget {
  const _CapacityTab({
    required this.bedTotal,
    required this.bedAvail,
    required this.icuTotal,
    required this.icuAvail,
    required this.notes,
    required this.networkStatus,
    required this.onStatus,
    required this.onSave,
    required this.partners,
  });

  final TextEditingController bedTotal;
  final TextEditingController bedAvail;
  final TextEditingController icuTotal;
  final TextEditingController icuAvail;
  final TextEditingController notes;
  final String networkStatus;
  final ValueChanged<String> onStatus;
  final VoidCallback onSave;
  final List<Map<String, dynamic>> partners;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Publish bed / ICU board',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 4),
        Text(
          'Stub capacity for network routing demos — not a live HIS feed.',
          style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: bedTotal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Beds total', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: bedAvail,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Beds free', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: icuTotal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ICU total', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: icuAvail,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ICU free', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: networkStatus,
          decoration: const InputDecoration(labelText: 'Facility status', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'online', child: Text('Online')),
            DropdownMenuItem(value: 'busy', child: Text('Busy')),
            DropdownMenuItem(value: 'offline', child: Text('Offline')),
          ],
          onChanged: (v) {
            if (v != null) onStatus(v);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: notes,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Capacity notes',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: digiForest),
          onPressed: onSave,
          child: const Text('Publish capacity'),
        ),
        const SizedBox(height: 24),
        Text(
          'Partner board',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: digiInk),
        ),
        const SizedBox(height: 8),
        if (partners.isEmpty)
          const ClinicalEmptyState(
            icon: Icons.hub_outlined,
            title: 'No regional partners',
            message: 'Partner pharmacies, labs, and hospitals in your region will list here.',
          )
        else
          ...partners.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DigiCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name']?.toString() ?? 'Partner',
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${p['type'] ?? ''} · ${p['town'] ?? p['region'] ?? ''}'
                            '${p['phone'] != null ? ' · ${p['phone']}' : ''}',
                            style: GoogleFonts.dmSans(color: digiSlate, fontSize: 12),
                          ),
                          if (p['type'] == 'hospital' && p['bed_total'] != null)
                            Text(
                              'Beds ${p['bed_available'] ?? '?'}/${p['bed_total']} · ICU ${p['icu_available'] ?? '?'}/${p['icu_total'] ?? '?'}',
                              style: GoogleFonts.dmSans(fontSize: 12, color: digiForest),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      (p['network_status'] ?? 'online').toString().toUpperCase(),
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: _statusColor(p['network_status']?.toString()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Color _statusColor(String? status) {
  switch (status) {
    case 'busy':
      return const Color(0xFFB45309);
    case 'offline':
      return const Color(0xFFB91C1C);
    default:
      return digiForest;
  }
}
