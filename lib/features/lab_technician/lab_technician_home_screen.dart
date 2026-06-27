import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

class LabTechnicianHomeScreen extends StatefulWidget {
  const LabTechnicianHomeScreen({super.key});

  @override
  State<LabTechnicianHomeScreen> createState() => _LabTechnicianHomeScreenState();
}

class _LabTechnicianHomeScreenState extends State<LabTechnicianHomeScreen> {
  int _currentTab = 0; // 0: Labs, 1: Scans
  String _filter = 'pending'; // pending, processing, completed, all

  List<dynamic> _labs = [];
  List<dynamic> _scans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      
      final labRes = await api.dio.get<List<dynamic>>('/api/labs');
      final scanRes = await api.dio.get<List<dynamic>>('/api/scans');
      
      setState(() {
        _labs = labRes.data ?? [];
        _scans = scanRes.data ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load diagnostic requests: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _submitResults(int id, String status, String results, String notes) async {
    try {
      final api = context.read<ApiClient>();
      final path = _currentTab == 0 ? '/api/labs/$id' : '/api/scans/$id';
      
      await api.dio.put<Map<String, dynamic>>(
        path,
        data: {
          'status': status,
          'results': results,
          'result_notes': notes,
        },
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Results submitted successfully.')),
      );
      _fetchData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit results: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);

    // Filter lists
    final currentList = _currentTab == 0 ? _labs : _scans;
    final filteredList = currentList.where((item) {
      if (_filter == 'all') return true;
      if (_filter == 'processing') {
        // Scans use 'scheduled' status, labs use 'sample_collected' or 'processing'
        final status = item['status']?.toString().toLowerCase();
        return status == 'processing' || status == 'sample_collected' || status == 'scheduled';
      }
      return item['status']?.toString().toLowerCase() == _filter;
    }).toList();

    // Counts
    final pendingLabs = _labs.where((l) => l['status']?.toString().toLowerCase() == 'pending').length;
    final pendingScans = _scans.where((s) => s['status']?.toString().toLowerCase() == 'pending').length;
    
    final processingLabs = _labs.where((l) {
      final st = l['status']?.toString().toLowerCase();
      return st == 'processing' || st == 'sample_collected';
    }).length;
    final processingScans = _scans.where((s) {
      final st = s['status']?.toString().toLowerCase();
      return st == 'processing' || st == 'scheduled';
    }).length;

    final completedLabs = _labs.where((l) => l['status']?.toString().toLowerCase() == 'completed').length;
    final completedScans = _scans.where((s) => s['status']?.toString().toLowerCase() == 'completed').length;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Sidebar Navigation (for desktop/web responsiveness)
            if (MediaQuery.of(context).size.width >= 700)
              _buildSidebar(session, theme, pendingLabs, pendingScans),
            
            // Main Content Area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mobile Header
                  if (MediaQuery.of(context).size.width < 700)
                    _buildMobileHeader(session, theme),

                  // Portal Header & Tab Selector
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentTab == 0 ? 'Laboratory Portal' : 'Imaging & Scans',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 24,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              _currentTab == 0 ? 'Review and record blood, urine, or stool samples' : 'Upload scan, MRI, CT, or ECG details',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFF00D2C4)),
                          onPressed: _fetchData,
                        ),
                      ],
                    ),
                  ),

                  // Quick Navigation Tabs (only visible on mobile layout)
                  if (MediaQuery.of(context).size.width < 700)
                    Container(
                      color: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildMobileTabButton(0, Icons.biotech, 'Lab Orders', pendingLabs),
                          _buildMobileTabButton(1, Icons.radar, 'Imaging Scans', pendingScans),
                        ],
                      ),
                    ),

                  const SizedBox(height: 10),

                  // Stats Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 2.2,
                      children: [
                        _buildStatCard('PENDING', _currentTab == 0 ? pendingLabs : pendingScans, Colors.amber, const Color(0xFF1E293B)),
                        _buildStatCard('PROCESSING', _currentTab == 0 ? processingLabs : processingScans, Colors.blue, const Color(0xFF1E293B)),
                        _buildStatCard('COMPLETED', _currentTab == 0 ? completedLabs : completedScans, const Color(0xFF00D2C4), const Color(0xFF1E293B)),
                        _buildStatCard('TOTAL ORDERS', currentList.length, Colors.white, const Color(0xFF1E293B)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Filters & Controls Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip('pending', 'Pending'),
                                const SizedBox(width: 8),
                                _buildFilterChip('processing', 'Processing'),
                                const SizedBox(width: 8),
                                _buildFilterChip('completed', 'Completed'),
                                const SizedBox(width: 8),
                                _buildFilterChip('all', 'All Logs'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  // Main List
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                        : _error != null
                            ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
                            : filteredList.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(_currentTab == 0 ? Icons.biotech_outlined : Icons.radar_outlined, color: Colors.white24, size: 48),
                                        const SizedBox(height: 10),
                                        Text(
                                          'No $_filter requests found.',
                                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: filteredList.length,
                                    itemBuilder: (context, index) {
                                      final item = filteredList[index];
                                      return _buildRequestCard(item);
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(Session session, ThemeData theme, int pendingL, int pendingS) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.biotech, color: Color(0xFF00D2C4), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Digi Health',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'LAB PORTAL',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),
          _buildSidebarItem(0, Icons.biotech, 'Lab Requests', pendingL),
          _buildSidebarItem(1, Icons.radar, 'Imaging Scans', pendingS),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.secondary.withOpacity(0.12),
                    child: Text(
                      session.user?.name.substring(0, 1).toUpperCase() ?? 'L',
                      style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.user?.name ?? 'Lab Technician',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Technician',
                          style: TextStyle(color: Colors.white30, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                    onPressed: () async {
                      await session.clear();
                      if (mounted) context.go('/login');
                    },
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String title, int badgeCount) {
    final active = _currentTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => setState(() => _currentTab = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00D2C4).withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? const Color(0xFF00D2C4) : Colors.white60, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: active ? const Color(0xFF00D2C4) : Colors.white60,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileHeader(Session session, ThemeData theme) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.biotech, color: Color(0xFF00D2C4), size: 24),
              const SizedBox(width: 8),
              Text(
                'CSAA LAB PORTAL',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                child: Text(
                  session.user?.name.substring(0, 1).toUpperCase() ?? 'L',
                  style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                onPressed: () async {
                  await session.clear();
                  if (mounted) context.go('/login');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabButton(int index, IconData icon, String label, int badgeCount) {
    final active = _currentTab == index;
    return InkWell(
      onTap: () => setState(() => _currentTab = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: active ? const Color(0xFF00D2C4) : Colors.white60, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF00D2C4) : Colors.white60,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterVal, String label) {
    final active = _filter == filterVal;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (val) {
        if (val) setState(() => _filter = filterVal);
      },
      selectedColor: const Color(0xFF00D2C4).withOpacity(0.2),
      backgroundColor: const Color(0xFF0F172A),
      labelStyle: TextStyle(
        color: active ? const Color(0xFF00D2C4) : Colors.white54,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: active ? const Color(0xFF00D2C4) : Colors.white.withOpacity(0.05)),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildRequestCard(dynamic item) {
    final status = item['status']?.toString().toLowerCase() ?? 'pending';
    final urgency = item['urgency']?.toString().toLowerCase() ?? 'routine';
    final isCompleted = status == 'completed';

    Color urgencyColor;
    if (urgency == 'stat') {
      urgencyColor = Colors.redAccent;
    } else if (urgency == 'urgent') {
      urgencyColor = Colors.amber;
    } else {
      urgencyColor = Colors.white54;
    }

    Color statusColor;
    switch (status) {
      case 'completed':
        statusColor = const Color(0xFF00D2C4);
        break;
      case 'processing':
      case 'scheduled':
      case 'sample_collected':
        statusColor = Colors.blue;
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        break;
      case 'pending':
      default:
        statusColor = Colors.amber;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item['patient_name']?.toString() ?? 'Walk-in Patient',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_currentTab == 0 ? Icons.biotech : Icons.radar, size: 16, color: const Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _currentTab == 0
                      ? (item['test_name']?.toString() ?? 'Lab Test')
                      : '${item['scan_type']?.toString().toUpperCase() ?? "SCAN"} — ${item['body_part']?.toString() ?? "General"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_currentTab == 0 && item['test_type'] != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                'Type: ${item['test_type']}',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ),
          ] else if (_currentTab == 1 && item['clinical_indication'] != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                'Indication: ${item['clinical_indication']}',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: urgencyColor.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      urgency.toUpperCase(),
                      style: TextStyle(color: urgencyColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.person_pin, size: 14, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    item['requested_by']?.toString() ?? item['doctor_name']?.toString() ?? 'Requested by MD',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () => _openEnterResultsDialog(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCompleted ? Colors.white.withOpacity(0.04) : const Color(0xFF00D2C4),
                  foregroundColor: isCompleted ? Colors.white70 : Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text(
                  isCompleted ? 'View Results' : 'Enter Results',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ).animate().fadeIn(duration: 250.ms),
    );
  }

  void _openEnterResultsDialog(dynamic item) {
    final status = item['status']?.toString().toLowerCase() ?? 'pending';
    final isCompleted = status == 'completed';

    showDialog(
      context: context,
      builder: (context) {
        return EnterResultsDialog(
          item: item,
          isCompleted: isCompleted,
          currentTab: _currentTab,
          onSubmit: (updatedStatus, results, notes) {
            _submitResults(item['id'] as int, updatedStatus, results, notes);
          },
        );
      },
    );
  }
}

class EnterResultsDialog extends StatefulWidget {
  const EnterResultsDialog({
    super.key,
    required this.item,
    required this.isCompleted,
    required this.currentTab,
    required this.onSubmit,
  });

  final dynamic item;
  final bool isCompleted;
  final int currentTab;
  final Function(String status, String results, String notes) onSubmit;

  @override
  State<EnterResultsDialog> createState() => _EnterResultsDialogState();
}

class _EnterResultsDialogState extends State<EnterResultsDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _status;
  final _resultsController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.item['status']?.toString().toLowerCase() ?? 'pending';
    // Fallback if status is invalid for lab updates
    if (_status == 'pending') {
      _status = widget.currentTab == 0 ? 'sample_collected' : 'scheduled';
    }
    _resultsController.text = widget.item['results']?.toString() ?? '';
    _notesController.text = widget.item['result_notes']?.toString() ?? '';
  }

  @override
  void dispose() {
    _resultsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.isCompleted ? 'View Diagnostic Results' : 'Submit Lab Findings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // Patient Details Spotlight
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PATIENT NAME',
                        style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      Text(
                        widget.item['patient_name']?.toString() ?? 'Walk-in Patient',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.currentTab == 0
                            ? 'Test Required: ${widget.item['test_name']}'
                            : 'Scan Required: ${widget.item['scan_type']?.toString().toUpperCase()} - ${widget.item['body_part']}',
                        style: const TextStyle(color: Color(0xFF00D2C4), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (widget.isCompleted) ...[
                  // Read-only Results View
                  const Text(
                    'DIAGNOSTIC FINDINGS',
                    style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D2C4).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00D2C4).withOpacity(0.2)),
                    ),
                    child: Text(
                      widget.item['results']?.toString() ?? 'No results recorded.',
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ),
                  if (widget.item['result_notes'] != null && widget.item['result_notes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 15),
                    const Text(
                      'ADDITIONAL OBSERVER NOTES',
                      style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        widget.item['result_notes'].toString(),
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                  const SizedBox(height: 25),
                  Text(
                    'Recorded by ${widget.item['completed_by'] ?? "System"} on ${widget.item['completed_at'] != null ? widget.item['completed_at'].toString().split('T')[0] : "N/A"}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  // Interactive Fields
                  const Text(
                    'UPDATE STATUS',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _status,
                    dropdownColor: const Color(0xFF0F172A),
                    decoration: _inputDeco(''),
                    items: widget.currentTab == 0
                        ? const [
                            DropdownMenuItem(value: 'sample_collected', child: Text('Sample Collected', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'processing', child: Text('Processing Sample', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'completed', child: Text('Completed & Approved', style: TextStyle(color: Colors.white))),
                          ]
                        : const [
                            DropdownMenuItem(value: 'scheduled', child: Text('Scheduled', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'processing', child: Text('Processing / Scanning', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'completed', child: Text('Completed & Approved', style: TextStyle(color: Colors.white))),
                          ],
                    onChanged: (v) {
                      if (v != null) setState(() => _status = v);
                    },
                  ),
                  const SizedBox(height: 15),

                  const Text(
                    'DIAGNOSTIC FINDINGS',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _resultsController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Enter test details or results (e.g. Hemoglobin 14.2 g/dL)...'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Please enter results findings' : null,
                  ),
                  const SizedBox(height: 15),

                  const Text(
                    'OBSERVER NOTES (OPTIONAL)',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Enter additional diagnostic observations...'),
                  ),
                  const SizedBox(height: 25),

                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSubmit(_status, _resultsController.text.trim(), _notesController.text.trim());
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D2C4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('SUBMIT DIAGNOSTICS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withOpacity(0.02),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.04)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
      ),
    );
  }
}
