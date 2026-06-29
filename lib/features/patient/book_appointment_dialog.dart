import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/session.dart';
import '../../core/notification_service.dart';
import '../../models/auth_user.dart';
import 'appointments_repository.dart';

class BookAppointmentDialog extends StatefulWidget {
  const BookAppointmentDialog({super.key});

  @override
  State<BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<BookAppointmentDialog> {
  int _currentStep = 0; // 0: Basic Info, 1: Details, 2: Review, 3: Success

  final _formKeyBasic = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phoneNumber = TextEditingController();
  final _email = TextEditingController();
  final _nationwideId = TextEditingController();
  final _department = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  
  // Dependant List
  final List<TextEditingController> _dependantsControllers = [];

  List<AuthUser> _doctors = [];
  AuthUser? _selectedDoctor;
  String _selectedService = '';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isTelemedicine = false;
  bool _loadingDoctors = true;
  bool _submitting = false;

  // Booked result details for success screen
  String _bookedId = '';
  String _bookingTimeStr = '';

  final List<String> _services = [
    'Physio',
    'Dietician',
    'Surgical',
    'Psychiatry',
    'Urology',
    'Physician specialties',
    'Dental',
    'Ent',
    'Eye',
    'Pediatric',
    'ANC/Gynae'
  ];

  @override
  void initState() {
    super.initState();
    _loadDoctorsAndSession();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phoneNumber.dispose();
    _email.dispose();
    _nationwideId.dispose();
    _department.dispose();
    _reason.dispose();
    _notes.dispose();
    for (var c in _dependantsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadDoctorsAndSession() {
    // Fill session data
    final session = context.read<Session>();
    if (session.isAuthenticated && session.user != null) {
      _fullName.text = session.user!.name;
      _phoneNumber.text = session.user!.username; // typically username or phone
      _email.text = ''; // optional
      _isTelemedicine = true; // default for verified patient telemedicine sessions
    }

    // Fetch doctors
    context.read<AppointmentsRepository>().getAvailableDoctors().then((list) {
      setState(() {
        _doctors = list;
        _loadingDoctors = false;
      });
    }).catchError((_) {
      setState(() => _loadingDoctors = false);
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00D2C4),
              onPrimary: Colors.black,
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00D2C4),
              surface: Color(0xFF0F172A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submitBooking() async {
    setState(() => _submitting = true);
    try {
      final repo = context.read<AppointmentsRepository>();
      final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final timeStr = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';

      final deps = _dependantsControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

      final apt = await repo.bookAppointment(
        fullName: _fullName.text,
        phoneNumber: _phoneNumber.text,
        email: _email.text,
        preferredDate: dateStr,
        preferredTime: timeStr,
        reason: _reason.text,
        doctorId: _selectedDoctor != null ? int.tryParse(_selectedDoctor!.id) : null,
        service: _selectedService,
        isTelemedicine: _isTelemedicine,
        nationwideId: _nationwideId.text,
        whoIsComing: deps,
        department: _department.text,
        notes: _notes.text,
      );

      // Schedule notifications for telemedicine appointment
      if (_isTelemedicine) {
        final notificationService = NotificationService();
        await notificationService.scheduleAppointmentReminder(apt);
        await notificationService.scheduleMeetingStartNotification(apt);
      }

      final now = DateTime.now();
      setState(() {
        _bookedId = apt.appointmentId ?? 'GP-${apt.id}-CONF';
        _bookingTimeStr = '${now.month}/${now.day}/${now.year} ${TimeOfDay.fromDateTime(now).format(context)}';
        _currentStep = 3; // Go to Success Screen
        _submitting = false;
      });
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: ${e.toString()}')),
      );
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_formKeyBasic.currentState!.validate()) {
        setState(() => _currentStep = 1);
      }
    } else if (_currentStep == 1) {
      if (_selectedDate == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select preferred date & time.')),
        );
        return;
      }
      setState(() => _currentStep = 2);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_currentStep / 3.0).clamp(0.0, 1.0);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner/Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentStep == 3 ? 'Appointment Booked!' : 'Pre-Booking System',
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_currentStep != 3)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.check, color: Color(0xFF00D2C4), size: 20),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                ],
              ),
            ),

            // Progress bar
            if (_currentStep < 3)
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withOpacity(0.04),
                color: const Color(0xFF00D2C4),
                minHeight: 3,
              ),

            // Dialog Step Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildStepContent(),
                ),
              ),
            ),

            // Navigation buttons footer
            if (_currentStep < 3)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _currentStep == 0 ? null : _prevStep,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        disabledForegroundColor: Colors.white24,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : (_currentStep == 2 ? _submitBooking : _nextStep),
                      icon: _submitting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Icon(_currentStep == 2 ? Icons.check : Icons.chevron_right),
                      label: Text(_submitting ? 'Processing...' : (_currentStep == 2 ? 'Confirm' : 'Next')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D2C4),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: GoogleFonts.roboto(fontWeight: FontWeight.bold),
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

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildBasicInfoStep();
      case 1: return _buildDetailsStep();
      case 2: return _buildReviewStep();
      case 3:
      default: return _buildSuccessStep();
    }
  }

  Widget _buildBasicInfoStep() {
    return Form(
      key: _formKeyBasic,
      child: Column(
        key: const ValueKey('basic-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Basic Patient Profile', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fullName,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Patient Full Name', Icons.person_outline),
            validator: (v) => v == null || v.trim().isEmpty ? 'Please enter patient full name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneNumber,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Contact Phone Number', Icons.phone_outlined),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Email Address (Optional)', Icons.mail_outline),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nationwideId,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Nationwide Membership No.', Icons.badge_outlined),
            validator: (v) => v == null || v.trim().isEmpty ? 'Nationwide membership no. is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _department,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Office/Department (Optional)', Icons.business_outlined),
          ),
          const SizedBox(height: 20),

          // Dependant / Who is coming
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dependants / Who is coming?', style: GoogleFonts.roboto(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _dependantsControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add, size: 14, color: Color(0xFF00D2C4)),
                label: Text('Add Dependant', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_dependantsControllers.isEmpty)
            Text('No dependants added. Leave empty if coming alone.', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 11, fontStyle: FontStyle.italic))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _dependantsControllers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dependantsControllers[index],
                          style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                          decoration: _fieldDeco('Dependant Name', Icons.person_outline),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                        onPressed: () {
                          setState(() {
                            _dependantsControllers[index].dispose();
                            _dependantsControllers.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      key: const ValueKey('details-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Preferred Dates & Specialties', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),

        // Date Picker
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Color(0xFF8B5CF6), size: 16),
                const SizedBox(width: 12),
                Text(
                  _selectedDate == null
                      ? 'Choose Appointment Date'
                      : 'Selected Date: ${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
                  style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Time Picker
        InkWell(
          onTap: _selectTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: Color(0xFF8B5CF6), size: 16),
                const SizedBox(width: 12),
                Text(
                  _selectedTime == null
                      ? 'Choose Preferred Time'
                      : 'Selected Time: ${_selectedTime!.format(context)}',
                  style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),

        // Specialty dropdown
        DropdownButtonFormField<String>(
          value: _selectedService.isEmpty ? null : _selectedService,
          dropdownColor: const Color(0xFF0F172A),
          decoration: _fieldDeco('Specialty Service Specialty', Icons.healing_outlined),
          items: _services
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedService = v);
          },
        ),
        const SizedBox(height: 12),

        // Doctor assigned dropdown
        _loadingDoctors
            ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(color: Color(0xFF00D2C4))))
            : DropdownButtonFormField<AuthUser>(
                value: _selectedDoctor,
                dropdownColor: const Color(0xFF0F172A),
                decoration: _fieldDeco('Doctor to see (Optional)', Icons.badge_outlined),
                items: _doctors
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.name, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDoctor = v),
              ),
        const SizedBox(height: 15),

        // Telehealth Mode
        SwitchListTile(
          title: Text('Telemedicine (Video Call)', style: GoogleFonts.roboto(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          subtitle: Text('Consult online instead of physical clinic visit', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 11)),
          value: _isTelemedicine,
          activeColor: const Color(0xFF00D2C4),
          contentPadding: EdgeInsets.zero,
          onChanged: (val) => setState(() => _isTelemedicine = val),
        ),
        const SizedBox(height: 12),

        // Complaint reason
        TextFormField(
          controller: _reason,
          maxLines: 2,
          style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
          decoration: _fieldDeco('Symptoms / Reason for appointment', Icons.chat_bubble_outline),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final dateStr = _selectedDate != null ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}' : '';
    final timeStr = _selectedTime != null ? _selectedTime!.format(context) : '';
    final deps = _dependantsControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

    return Column(
      key: const ValueKey('review-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Confirm Reservation Details', style: GoogleFonts.roboto(color: Color(0xFF00D2C4), fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(2),
            },
            children: [
              _buildTableRow('Full Name', _fullName.text),
              _buildTableRow('Phone No', _phoneNumber.text),
              _buildTableRow('Nationwide ID', _nationwideId.text),
              _buildTableRow('Who is coming', deps.isEmpty ? 'Self' : 'Self + ${deps.join(", ")}'),
              _buildTableRow('Preferred Date', dateStr),
              _buildTableRow('Preferred Time', timeStr),
              _buildTableRow('Consult Type', _isTelemedicine ? 'Telehealth (Online Video)' : 'Physical Clinic Visit'),
              _buildTableRow('Service Dept', _selectedService.isEmpty ? 'General' : _selectedService),
              _buildTableRow('Doctor to see', _selectedDoctor?.name ?? 'General Specialist'),
              _buildTableRow('Complaint', _reason.text),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildTableRow(String label, String val) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label, style: GoogleFonts.roboto(color: Colors.white30, fontSize: 11)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(val, style: GoogleFonts.roboto(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey('success-step'),
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF00D2C4), size: 60)
            .animate()
            .scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 15),
        Text(
          'Booking Confirmed!',
          style: GoogleFonts.roboto(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Your appointment has been successfully recorded in the portal. Please save your verification code below.',
          style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // Animated Card ID
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF00D2C4).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('CSAA TELEMEDICINE', style: GoogleFonts.roboto(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const Icon(Icons.shield, color: Color(0xFF00D2C4), size: 16),
                ],
              ),
              const SizedBox(height: 15),
              Text('APPOINTMENT VERIFICATION CODE', style: GoogleFonts.roboto(color: Colors.white38, fontSize: 8)),
              const SizedBox(height: 2),
              SelectableText(
                _bookedId,
                style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STATUS', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 8)),
                      Text('CONFIRMED', style: GoogleFonts.roboto(color: const Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('VERIFICATION DATE', style: GoogleFonts.roboto(color: Colors.white30, fontSize: 8)),
                      Text(_bookingTimeStr, style: GoogleFonts.roboto(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

        const SizedBox(height: 25),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D2C4),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('DISMISS', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  InputDecoration _fieldDeco(String hintText, IconData prefixIcon) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.roboto(color: Colors.white24, fontSize: 12),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF00D2C4), size: 16),
      filled: true,
      fillColor: Colors.white.withOpacity(0.02),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.04)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.0),
      ),
    );
  }
}
