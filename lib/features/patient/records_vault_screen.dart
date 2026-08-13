import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
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
    PlatformFile? picked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add to vault'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Attach a photo or PDF of a letter, lab, or scan (2 MB or less). It is stored in the clinic database with your chart.',
                  style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate),
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
                      withData: true,
                    );
                    if (result == null || result.files.isEmpty) return;
                    final file = result.files.first;
                    if ((file.size) > 2 * 1024 * 1024) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Choose a file of 2 MB or less.')),
                        );
                      }
                      return;
                    }
                    setLocal(() => picked = file);
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(picked == null ? 'Attach photo or PDF' : picked!.name),
                ),
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

    String? fileBase64;
    String? fileName;
    String? mime;
    if (picked != null) {
      final bytes = picked!.bytes ??
          (picked!.path != null && !kIsWeb ? await File(picked!.path!).readAsBytes() : null);
      if (bytes != null) {
        fileBase64 = base64Encode(bytes);
        fileName = picked!.name;
        mime = _mimeFor(picked!.extension, picked!.name);
      }
    }

    await context.read<CareRepository>().addVaultDocument({
      'title': title.text.trim(),
      'kind': kind,
      'source_label': source.text.trim(),
      'notes': notes.text.trim(),
      if (fileBase64 != null) 'file_base64': fileBase64,
      if (fileName != null) 'file_name': fileName,
      if (mime != null) 'mime_type': mime,
    });
    _load();
  }

  String _mimeFor(String? ext, String name) {
    final e = (ext ?? name.split('.').last).toLowerCase();
    switch (e) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _openFile(Map<String, dynamic> doc) async {
    final id = doc['id'];
    if (id is! int) return;
    try {
      final bytes = await context.read<CareRepository>().vaultFileBytes(id);
      if (!mounted) return;
      final mime = doc['mime_type']?.toString() ?? '';
      if (mime.startsWith('image/')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: InteractiveViewer(child: Image.memory(Uint8List.fromList(bytes))),
          ),
        );
        return;
      }
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Open this record on a phone to view the file.')),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final name = (doc['file_name']?.toString().isNotEmpty == true) ? doc['file_name'].toString() : 'record-$id';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file could not be opened.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiCanvas,
      appBar: AppBar(
        title: Text('Medical vault', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700)),
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
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add record'),
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
                        child: Text(_data['storage_note'].toString(), style: GoogleFonts.dmSans(fontSize: 12, color: digiSlate)),
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
                            subtitle: (m) {
                              final hasFile = m['has_file'] == true;
                              final size = m['byte_size'];
                              final sizeLabel = size is int ? ' · ${(size / 1024).toStringAsFixed(0)} KB' : '';
                              return '${m['kind'] ?? ''} · ${m['file_name'] ?? m['source_label'] ?? ''}$sizeLabel${hasFile ? '' : ' · notes only'}';
                            },
                            empty: 'No documents yet. Attach a photo or PDF of a letter, lab, or scan.',
                            onOpen: (m) async {
                              if (m['has_file'] == true) await _openFile(m);
                            },
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
    this.onOpen,
  });

  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) subtitle;
  final String empty;
  final Future<void> Function(Map<String, dynamic>)? onDelete;
  final Future<void> Function(Map<String, dynamic>)? onOpen;

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8DC))),
          leading: Icon(
            m['has_file'] == true ? Icons.insert_drive_file_outlined : Icons.notes_outlined,
            color: digiViolet,
          ),
          title: Text(title(m), style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle(m), maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: onOpen == null ? null : () => onOpen!(m),
          trailing: onDelete == null
              ? null
              : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete!(m)),
        );
      },
    );
  }
}
