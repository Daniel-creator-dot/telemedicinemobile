import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';

class RecordsVaultScreen extends StatefulWidget {
  const RecordsVaultScreen({super.key});

  @override
  State<RecordsVaultScreen> createState() => _RecordsVaultScreenState();
}

class _RecordsVaultScreenState extends State<RecordsVaultScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<CareRepository>().documentVault();
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Your records could not be loaded right now.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data[key] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _addDocument() async {
    final title = TextEditingController();
    final source = TextEditingController();
    final notes = TextEditingController();
    String kind = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add record metadata'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Files are not uploaded to this server. Add the title, source clinic, and notes so the record is findable.',
                  style: GoogleFonts.roboto(fontSize: 12, color: digiSlate),
                ),
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                DropdownButtonFormField<String>(
                  value: kind,
                  items: const [
                    DropdownMenuItem(value: 'letter', child: Text('Letter / summary')),
                    DropdownMenuItem(value: 'lab', child: Text('Laboratory')),
                    DropdownMenuItem(value: 'imaging', child: Text('Imaging')),
                    DropdownMenuItem(value: 'prescription', child: Text('Prescription')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setLocal(() => kind = v ?? 'other'),
                  decoration: const InputDecoration(labelText: 'Kind'),
                ),
                TextField(controller: source, decoration: const InputDecoration(labelText: 'Source (clinic, date)')),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || title.text.trim().isEmpty) return;
    await context.read<CareRepository>().addVaultDocument({
      'title': title.text.trim(),
      'kind': kind,
      'source_label': source.text.trim(),
      'notes': notes.text.trim(),
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Medical vault', style: GoogleFonts.roboto(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: digiInk,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: digiViolet,
          unselectedLabelColor: digiSlate,
          tabs: const [
            Tab(text: 'Rx'),
            Tab(text: 'Labs'),
            Tab(text: 'Imaging'),
            Tab(text: 'Letters'),
            Tab(text: 'Documents'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDocument,
        backgroundColor: digiViolet,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Add metadata'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    if (_data['storage_note'] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(_data['storage_note'].toString(), style: GoogleFonts.roboto(fontSize: 12, color: digiSlate)),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _VaultList(
                            items: _list('prescriptions'),
                            title: (m) => m['medication_name']?.toString() ?? 'Prescription',
                            subtitle: (m) => '${m['prescription_ref'] ?? ''} · ${m['dosage'] ?? ''} ${m['frequency'] ?? ''}',
                            empty: 'No electronic prescriptions yet.',
                          ),
                          _VaultList(
                            items: _list('labs'),
                            title: (m) => m['test_name']?.toString() ?? 'Laboratory',
                            subtitle: (m) => '${m['status'] ?? ''} · ${m['results'] ?? 'Awaiting result'}',
                            empty: 'No laboratory reports yet.',
                          ),
                          _VaultList(
                            items: _list('scans'),
                            title: (m) => m['scan_type']?.toString() ?? 'Imaging',
                            subtitle: (m) => '${m['status'] ?? ''} · ${m['results'] ?? 'Awaiting report'}',
                            empty: 'No imaging reports yet.',
                          ),
                          _VaultList(
                            items: _list('letters'),
                            title: (m) => m['doctor_name']?.toString() ?? 'Consultation summary',
                            subtitle: (m) => m['treatment_plan']?.toString() ?? m['patient_education']?.toString() ?? 'Completed visit',
                            empty: 'No clinical letters yet.',
                          ),
                          _VaultList(
                            items: _list('documents'),
                            title: (m) => m['title']?.toString() ?? 'Document',
                            subtitle: (m) => '${m['kind'] ?? ''} · ${m['source_label'] ?? ''} ${m['notes'] ?? ''}',
                            empty: 'No document metadata yet. Add a title and source — files are not stored here.',
                            onDelete: (m) async {
                              final id = m['id'];
                              if (id is int) {
                                await context.read<CareRepository>().deleteVaultDocument(id);
                                _load();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _VaultList extends StatelessWidget {
  const _VaultList({
    required this.items,
    required this.title,
    required this.subtitle,
    required this.empty,
    this.onDelete,
  });

  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) subtitle;
  final String empty;
  final Future<void> Function(Map<String, dynamic>)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ClinicalEmptyState(icon: Icons.folder_open_outlined, title: 'Nothing here yet', message: empty);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = items[i];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
          title: Text(title(m), style: GoogleFonts.roboto(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle(m), maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: onDelete == null
              ? null
              : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete!(m)),
        );
      },
    );
  }
}
