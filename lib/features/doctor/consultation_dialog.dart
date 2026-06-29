import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/appointment.dart';

class ConsultationDialog extends StatefulWidget {
  const ConsultationDialog({super.key, required this.appointment});

  final Appointment appointment;

  @override
  State<ConsultationDialog> createState() => _ConsultationDialogState();
}

class _ConsultationDialogState extends State<ConsultationDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKeyVitals = GlobalKey<FormState>();
  final _formKeyAssess = GlobalKey<FormState>();

  // Vitals
  final _vitalsBp = TextEditingController();
  final _vitalsTemp = TextEditingController();
  final _vitalsPulse = TextEditingController();
  final _vitalsWeight = TextEditingController();
  final _vitalsHeight = TextEditingController();
  final _vitalsSpo2 = TextEditingController();

  // Assessment
  final _chiefComplaint = TextEditingController();
  final _symptoms = TextEditingController();
  final _diagnosis = TextEditingController();
  final _clinicalNotes = TextEditingController();
  final _followUpDate = TextEditingController();

  // Labs, Scans, Rx Lists
  List<dynamic> _labs = [];
  List<dynamic> _scans = [];
  List<dynamic> _prescriptions = [];

  bool _loading = true;
  bool _saving = false;
  int _patientId = 0;
  dynamic _consultation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _vitalsBp.dispose();
    _vitalsTemp.dispose();
    _vitalsPulse.dispose();
    _vitalsWeight.dispose();
    _vitalsHeight.dispose();
    _vitalsSpo2.dispose();
    _chiefComplaint.dispose();
    _symptoms.dispose();
    _diagnosis.dispose();
    _clinicalNotes.dispose();
    _followUpDate.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();

      // 1. Get patient_id from appointment list
      final appointmentsRes = await api.dio.get<List<dynamic>>('/api/appointments');
      if (appointmentsRes.data != null) {
        final matches = appointmentsRes.data!.where((json) => json['id'] == widget.appointment.id);
        if (matches.isNotEmpty) {
          _patientId = matches.first['patient_id'] as int? ?? 0;
        }
      }

      // 2. Fetch consultation details, labs, scans, and prescriptions concurrently
      final responses = await Future.wait([
        api.dio.get<List<dynamic>>('/api/consultations/${widget.appointment.id}').catchError((_) => Response<List<dynamic>>(requestOptions: RequestOptions(), data: [])),
        api.dio.get<List<dynamic>>('/api/labs', queryParameters: {'patient_id': _patientId}).catchError((_) => Response<List<dynamic>>(requestOptions: RequestOptions(), data: [])),
        api.dio.get<List<dynamic>>('/api/scans', queryParameters: {'patient_id': _patientId}).catchError((_) => Response<List<dynamic>>(requestOptions: RequestOptions(), data: [])),
        api.dio.get<List<dynamic>>('/api/prescriptions').catchError((_) => Response<List<dynamic>>(requestOptions: RequestOptions(), data: [])),
      ]);

      // Parse Consultation
      final consData = responses[0].data;
      if (consData != null && consData.isNotEmpty) {
        _consultation = consData.first;
        _chiefComplaint.text = _consultation['chief_complaint']?.toString() ?? '';
        _symptoms.text = _consultation['symptoms']?.toString() ?? '';
        _diagnosis.text = _consultation['diagnosis']?.toString() ?? '';
        _clinicalNotes.text = _consultation['clinical_notes']?.toString() ?? '';
        _followUpDate.text = _consultation['follow_up_date'] != null
            ? _consultation['follow_up_date'].toString().split('T')[0]
            : '';
        _vitalsBp.text = _consultation['vitals_bp']?.toString() ?? '';
        _vitalsTemp.text = _consultation['vitals_temp']?.toString() ?? '';
        _vitalsPulse.text = _consultation['vitals_pulse']?.toString() ?? '';
        _vitalsWeight.text = _consultation['vitals_weight']?.toString() ?? '';
        _vitalsHeight.text = _consultation['vitals_height']?.toString() ?? '';
        _vitalsSpo2.text = _consultation['vitals_spo2']?.toString() ?? '';
      }

      // Parse Labs, Scans, Rx
      setState(() {
        _labs = responses[1].data ?? [];
        _scans = responses[2].data ?? [];
        
        final allRx = responses[3].data ?? [];
        _prescriptions = allRx.where((r) => r['appointment_id'] == widget.appointment.id).toList();
        
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveConsultation({String status = 'in_progress'}) async {
    setState(() => _saving = true);
    try {
      final api = context.read<ApiClient>();
      final payload = {
        'appointment_id': widget.appointment.id,
        'patient_id': _patientId,
        'chief_complaint': _chiefComplaint.text.trim(),
        'symptoms': _symptoms.text.trim(),
        'diagnosis': _diagnosis.text.trim(),
        'clinical_notes': _clinicalNotes.text.trim(),
        'vitals_bp': _vitalsBp.text.trim(),
        'vitals_temp': _vitalsTemp.text.trim(),
        'vitals_pulse': _vitalsPulse.text.trim(),
        'vitals_weight': _vitalsWeight.text.trim(),
        'vitals_height': _vitalsHeight.text.trim(),
        'vitals_spo2': _vitalsSpo2.text.trim(),
        'follow_up_date': _followUpDate.text.trim().isEmpty ? null : _followUpDate.text.trim(),
        'status': status,
      };

      if (_consultation != null) {
        final res = await api.dio.put<Map<String, dynamic>>('/api/consultations/${_consultation['id']}', data: payload);
        _consultation = res.data;
      } else {
        final res = await api.dio.post<Map<String, dynamic>>('/api/consultations', data: payload);
        _consultation = res.data;
      }

      if (status == 'completed') {
        // Also update appointment status
        await api.dio.patch<Map<String, dynamic>>(
          '/api/appointments/${widget.appointment.id}/status',
          data: {'status': 'completed'},
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved successfully.')),
        );
        _loadAllData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save consultation: ${e.toString()}')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _orderLab(String testName, String testType, String urgency) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/labs',
        data: {
          'appointment_id': widget.appointment.id,
          'patient_id': _patientId,
          'consultation_id': _consultation?['id'],
          'test_name': testName,
          'test_type': testType,
          'urgency': urgency,
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lab test ordered successfully.')),
      );
      _loadAllData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to order lab: ${e.toString()}')),
      );
    }
  }

  Future<void> _requestScan(String scanType, String bodyPart, String indication, String urgency) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/scans',
        data: {
          'appointment_id': widget.appointment.id,
          'patient_id': _patientId,
          'consultation_id': _consultation?['id'],
          'scan_type': scanType,
          'body_part': bodyPart,
          'clinical_indication': indication,
          'urgency': urgency,
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan request submitted successfully.')),
      );
      _loadAllData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit scan order: ${e.toString()}')),
      );
    }
  }

  Future<void> _addMedication(String name, String dosage, String freq, String duration, String instructions) async {
    try {
      final api = context.read<ApiClient>();
      await api.dio.post<Map<String, dynamic>>(
        '/api/prescriptions',
        data: {
          'appointment_id': widget.appointment.id,
          'patient_id': _patientId,
          'consultation_id': _consultation?['id'],
          'medication_name': name,
          'dosage': dosage,
          'frequency': freq,
          'duration': duration,
          'instructions': instructions,
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prescription medication added.')),
      );
      _loadAllData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add prescription: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 600;

    final dialogContent = Scaffold(
      backgroundColor: const Color(0xFF070A13),
      resizeToAvoidBottomInset: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Workspace Header Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.secondary.withOpacity(0.2),
                  theme.colorScheme.primary.withOpacity(0.08),
                ],
              ),
              borderRadius: isMobile ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consultation Workspace',
                        style: GoogleFonts.roboto(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, color: Colors.white54, size: 13),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.appointment.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.roboto(color: Colors.white60, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.access_time_rounded, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            widget.appointment.preferredTime,
                            style: GoogleFonts.roboto(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tabs Bar — scrollable icon+label style
          Container(
            color: const Color(0xFF0D1117),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF00D2C4),
              unselectedLabelColor: Colors.white38,
              indicatorColor: const Color(0xFF00D2C4),
              indicatorWeight: 2,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              labelStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: GoogleFonts.roboto(fontSize: 12),
              tabs: [
                const Tab(
                  icon: Icon(Icons.monitor_heart_outlined, size: 16),
                  text: 'Vitals',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                const Tab(
                  icon: Icon(Icons.assignment_outlined, size: 16),
                  text: 'Assess',
                  iconMargin: EdgeInsets.only(bottom: 2),
                ),
                Tab(
                  iconMargin: const EdgeInsets.only(bottom: 2),
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.biotech_outlined, size: 16),
                      if (_labs.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D2C4).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${_labs.length}', style: GoogleFonts.roboto(fontSize: 9, color: Color(0xFF00D2C4), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  text: 'Labs',
                ),
                Tab(
                  iconMargin: const EdgeInsets.only(bottom: 2),
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.document_scanner_outlined, size: 16),
                      if (_scans.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${_scans.length}', style: GoogleFonts.roboto(fontSize: 9, color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  text: 'Scans',
                ),
                Tab(
                  iconMargin: const EdgeInsets.only(bottom: 2),
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.medication_outlined, size: 16),
                      if (_prescriptions.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${_prescriptions.length}', style: GoogleFonts.roboto(fontSize: 9, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  text: 'Rx',
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildVitalsTab(),
                _buildAssessmentTab(),
                _buildLabsTab(),
                _buildScansTab(),
                _buildRxTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _saveConsultation(status: 'in_progress'),
                  icon: const Icon(Icons.drafts_outlined, size: 16),
                  label: const Text('Save Draft'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _saveConsultation(status: 'completed'),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Complete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Dialog(
      backgroundColor: const Color(0xFF070A13),
      insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(28),
      ),
      child: ClipRRect(
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(28),
        child: SizedBox(
          width: isMobile ? media.size.width : 600,
          height: isMobile ? media.size.height : 800,
          child: _loading
              ? const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4))),
                )
              : dialogContent,
        ),
      ),
    );
  }

  Widget _buildVitalsTab() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    final bpField = _vitalsField(_vitalsBp, 'Blood Pressure', '120/80', 'mmHg');
    final tempField = _vitalsField(_vitalsTemp, 'Temperature', '36.5', '°C');
    final pulseField = _vitalsField(_vitalsPulse, 'Pulse Rate', '72', 'bpm');
    final spo2Field = _vitalsField(_vitalsSpo2, 'SpO2 Level', '98', '%');
    final weightField = _vitalsField(_vitalsWeight, 'Weight', '70', 'kg');
    final heightField = _vitalsField(_vitalsHeight, 'Height', '170', 'cm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyVitals,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Patient Health Vitals',
              style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 15),
            if (isMobile) ...[
              bpField,
              const SizedBox(height: 12),
              tempField,
              const SizedBox(height: 12),
              pulseField,
              const SizedBox(height: 12),
              spo2Field,
              const SizedBox(height: 12),
              weightField,
              const SizedBox(height: 12),
              heightField,
            ] else ...[
              Row(
                children: [
                  Expanded(child: bpField),
                  const SizedBox(width: 10),
                  Expanded(child: tempField),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: pulseField),
                  const SizedBox(width: 10),
                  Expanded(child: spo2Field),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: weightField),
                  const SizedBox(width: 10),
                  Expanded(child: heightField),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyAssess,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Clinical Diagnosis Details',
              style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _chiefComplaint,
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
              decoration: _inputDeco('Chief Complaint (e.g. Headache for 3 days)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _symptoms,
              maxLines: 2,
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
              decoration: _inputDeco('Observed Symptoms'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _diagnosis,
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
              decoration: _inputDeco('Final Medical Diagnosis'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _clinicalNotes,
              maxLines: 3,
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
              decoration: _inputDeco('Clinical Notes & Advice'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _followUpDate,
              style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
              decoration: _inputDeco('Follow-up Date (YYYY-MM-DD)'),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ordered Laboratory Tests', style: GoogleFonts.roboto(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
              ElevatedButton.icon(
                onPressed: _openAddLabDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Order Lab'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _labs.isEmpty
              ? Center(child: Text('No laboratory requests issued.', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _labs.length,
                  itemBuilder: (context, index) {
                    final lab = _labs[index];
                    final isDone = lab['status']?.toString().toLowerCase() == 'completed';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(lab['test_name']?.toString() ?? '', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                lab['status']?.toString().toUpperCase() ?? 'PENDING',
                                style: GoogleFonts.roboto(color: isDone ? const Color(0xFF00D2C4) : Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Urgency: ${lab['urgency']}  |  Type: ${lab['test_type']}', style: GoogleFonts.roboto(color: Colors.white38, fontSize: 10)),
                          if (lab['results'] != null) ...[
                            const SizedBox(height: 6),
                            Text('Findings: ${lab['results']}', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11)),
                          ]
                        ],
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildScansTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ordered Imaging Scans', style: GoogleFonts.roboto(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
              ElevatedButton.icon(
                onPressed: _openAddScanDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Request Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _scans.isEmpty
              ? Center(child: Text('No scan requests issued.', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _scans.length,
                  itemBuilder: (context, index) {
                    final scan = _scans[index];
                    final isDone = scan['status']?.toString().toLowerCase() == 'completed';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${scan['scan_type']?.toString().toUpperCase() ?? ''} — ${scan['body_part'] ?? ""}',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              Text(
                                scan['status']?.toString().toUpperCase() ?? 'PENDING',
                                style: GoogleFonts.roboto(color: isDone ? const Color(0xFF00D2C4) : Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Indication: ${scan['clinical_indication'] ?? "N/A"}', style: GoogleFonts.roboto(color: Colors.white38, fontSize: 10)),
                          if (scan['results'] != null) ...[
                            const SizedBox(height: 6),
                            Text('Findings: ${scan['results']}', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11)),
                          ]
                        ],
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _buildRxTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Prescribed Medications', style: GoogleFonts.roboto(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
              ElevatedButton.icon(
                onPressed: _openAddRxDialog,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Drug'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: GoogleFonts.roboto(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _prescriptions.isEmpty
              ? Center(child: Text('No medications prescribed yet.', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 12)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _prescriptions.length,
                  itemBuilder: (context, index) {
                    final rx = _prescriptions[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rx['medication_name']?.toString() ?? '', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Dosage: ${rx['dosage']}  |  Freq: ${rx['frequency']}  |  Duration: ${rx['duration']}', style: GoogleFonts.roboto(color: Colors.white54, fontSize: 11)),
                          if (rx['instructions'] != null && rx['instructions'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Advise: ${rx['instructions']}', style: GoogleFonts.roboto(color: Color(0xFF8B5CF6), fontSize: 10, fontStyle: FontStyle.italic)),
                          ]
                        ],
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  Widget _vitalsField(TextEditingController controller, String label, String hint, String suffix) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.roboto(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.roboto(color: Colors.white54, fontSize: 11),
        hintText: hint,
        hintStyle: GoogleFonts.roboto(color: Colors.white24, fontSize: 11),
        suffixText: suffix,
        suffixStyle: GoogleFonts.roboto(color: Colors.white24, fontSize: 11),
        filled: true,
        fillColor: Colors.white.withOpacity(0.02),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.04)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF00D2C4), width: 1.0),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.roboto(color: Colors.white30, fontSize: 12),
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
    );
  }

  void _openAddLabDialog() {
    final nameC = TextEditingController();
    String type = 'blood';
    String urgency = 'routine';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Order Laboratory Test', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameC,
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    decoration: _inputDeco('Test Name (e.g. FBC, Lipid Profile)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: const Color(0xFF0F172A),
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    iconEnabledColor: const Color(0xFF00D2C4),
                    decoration: _inputDeco('Sample Type'),
                    items: [
                      DropdownMenuItem(value: 'blood', child: Text('Blood Sample', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'urine', child: Text('Urine Sample', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'stool', child: Text('Stool Sample', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'other', child: Text('Other Sample', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: urgency,
                    dropdownColor: const Color(0xFF0F172A),
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    iconEnabledColor: const Color(0xFF00D2C4),
                    decoration: _inputDeco('Urgency Level'),
                    items: [
                      DropdownMenuItem(value: 'routine', child: Text('Routine Urgency', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent Urgency', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'stat', child: Text('STAT / Immediate', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => urgency = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCEL', style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameC.text.trim().isNotEmpty) {
                    _orderLab(nameC.text.trim(), type, urgency);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                child: const Text('ORDER TEST'),
              )
            ],
          );
        });
      },
    );
  }

  void _openAddScanDialog() {
    final partC = TextEditingController();
    final indC = TextEditingController();
    String type = 'x-ray';
    String urgency = 'routine';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Request Imaging Scan', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: const Color(0xFF0F172A),
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    iconEnabledColor: const Color(0xFF00D2C4),
                    decoration: _inputDeco('Scan Type'),
                    items: [
                      DropdownMenuItem(value: 'x-ray', child: Text('X-Ray', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'mri', child: Text('MRI Scan', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'ct', child: Text('CT Scan', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'ultrasound', child: Text('Ultrasound', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'ecg', child: Text('ECG / EKG', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'other', child: Text('Other Imaging', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: partC,
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    decoration: _inputDeco('Body Part / Region (e.g. Chest)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: indC,
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    decoration: _inputDeco('Clinical Indication (Reason)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: urgency,
                    dropdownColor: const Color(0xFF0F172A),
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                    iconEnabledColor: const Color(0xFF00D2C4),
                    decoration: _inputDeco('Urgency Level'),
                    items: [
                      DropdownMenuItem(value: 'routine', child: Text('Routine Urgency', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'urgent', child: Text('Urgent Urgency', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                      DropdownMenuItem(value: 'stat', child: Text('STAT / Immediate', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => urgency = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCEL', style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (partC.text.trim().isNotEmpty) {
                    _requestScan(type, partC.text.trim(), indC.text.trim(), urgency);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                child: const Text('REQUEST SCAN'),
              )
            ],
          );
        });
      },
    );
  }

  void _openAddRxDialog() {
    final nameC = TextEditingController();
    final doseC = TextEditingController();
    final freqC = TextEditingController();
    final durC = TextEditingController();
    final instC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Prescribe Medication', style: GoogleFonts.roboto(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: nameC, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13), decoration: _inputDeco('Medication Name')),
                const SizedBox(height: 10),
                TextFormField(controller: doseC, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13), decoration: _inputDeco('Dosage (e.g. 500mg)')),
                const SizedBox(height: 10),
                TextFormField(controller: freqC, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13), decoration: _inputDeco('Frequency (e.g. 3x Daily)')),
                const SizedBox(height: 10),
                TextFormField(controller: durC, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13), decoration: _inputDeco('Duration (e.g. 7 Days)')),
                const SizedBox(height: 10),
                TextFormField(controller: instC, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13), decoration: _inputDeco('Special Instructions (Optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameC.text.trim().isNotEmpty && doseC.text.trim().isNotEmpty) {
                  _addMedication(nameC.text.trim(), doseC.text.trim(), freqC.text.trim(), durC.text.trim(), instC.text.trim());
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D2C4),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                textStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              child: const Text('ADD DRUG'),
            )
          ],
        );
      },
    );
  }
}
