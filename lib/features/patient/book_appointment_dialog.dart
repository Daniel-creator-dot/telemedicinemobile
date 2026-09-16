import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/session.dart';
import '../../core/notification_service.dart';
import '../../models/doctor_profile.dart';
import 'appointments_repository.dart';
import 'care_repository.dart';

class BookAppointmentDialog extends StatefulWidget {
  const BookAppointmentDialog({
    super.key,
    this.preselectedDoctorId,
    this.preselectedDoctorName,
    this.preselectedSpecialty,
    this.dependentPatientId,
    this.dependentName,
  });

  final int? preselectedDoctorId;
  final String? preselectedDoctorName;
  final String? preselectedSpecialty;
  final int? dependentPatientId;
  final String? dependentName;

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

  final List<TextEditingController> _dependantsControllers = [];

  List<DoctorProfile> _doctors = [];
  DoctorProfile? _selectedDoctor;
  String _selectedService = 'general consultation';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  List<String> _slots = [];
  String? _selectedSlot;
  String? _slotsHint;
  int? _resolvedDoctorId;
  bool _isTelemedicine = true;
  bool _loadingDoctors = true;
  bool _loadingSlots = false;
  bool _submitting = false;
  bool _autoAdvancingDate = false;

  String _bookedId = '';
  String _bookingTimeStr = '';

  final List<String> _services = [
    'general consultation',
    'specialist consultation',
    'follow-up',
    'prescription review',
    'laboratory-result review',
    'imaging-result review',
    'chronic disease review',
    'second medical opinion',
    'other',
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
    for (final c in _dependantsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadDoctorsAndSession() {
    final session = context.read<Session>();
    if (session.isAuthenticated && session.user != null) {
      _fullName.text = widget.dependentName?.trim().isNotEmpty == true
          ? widget.dependentName!
          : session.user!.name;
      _phoneNumber.text = session.user!.phoneNumber ?? session.user!.username;
      _email.text = session.user!.email ?? '';
      _nationwideId.text = session.user!.patientCode ?? '';
      _isTelemedicine = true;
    }

    final specialty = widget.preselectedSpecialty?.trim().toLowerCase();
    if (specialty != null && _services.contains(specialty)) {
      _selectedService = specialty;
    }

    _selectedDate = DateTime.now();

    context.read<CareRepository>().getDirectory().then((list) {
      if (!mounted) return;
      DoctorProfile? selected;
      if (widget.preselectedDoctorId != null) {
        for (final d in list) {
          if (d.id == widget.preselectedDoctorId) {
            selected = d;
            break;
          }
        }
        if (selected == null) {
          selected = DoctorProfile(
            id: widget.preselectedDoctorId!,
            name: widget.preselectedDoctorName ?? 'Doctor',
            specialization: widget.preselectedSpecialty,
          );
          list = [...list, selected];
        }
      } else if (list.isNotEmpty) {
        selected = list.first;
      }

      setState(() {
        _doctors = list;
        _selectedDoctor = selected;
        _resolvedDoctorId = selected?.id;
        _loadingDoctors = false;
      });
      _loadSlots();
    }).catchError((_) {
      if (mounted) setState(() => _loadingDoctors = false);
    });
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  List<String> _fallbackSlotsFor(DateTime date) {
    if (date.weekday == DateTime.sunday) return const [];
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final out = <String>[];
    for (var h = 9; h < 17; h++) {
      for (final m in const [0, 30]) {
        if (isToday && (h < now.hour || (h == now.hour && m <= now.minute))) continue;
        out.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
      }
    }
    return out;
  }

  Future<void> _loadSlots({bool allowAutoAdvance = true}) async {
    if (_selectedDoctor == null || _selectedDate == null) {
      setState(() {
        _slots = [];
        _selectedSlot = null;
        _slotsHint = null;
      });
      return;
    }
    final doctorId = _selectedDoctor!.id;
    setState(() {
      _loadingSlots = true;
      if (allowAutoAdvance) _slotsHint = null;
    });
    try {
      final result = await context.read<CareRepository>().getSlots(doctorId, _dateStr(_selectedDate!));
      if (!mounted) return;

      var slots = result.slots;
      var hint = _slotsHint;
      if (slots.isEmpty && allowAutoAdvance && !_autoAdvancingDate) {
        final next = _parseDate(result.nextAvailableDate);
        if (next != null && _dateStr(next) != _dateStr(_selectedDate!)) {
          _autoAdvancingDate = true;
          setState(() {
            _selectedDate = next;
            _selectedSlot = null;
            _selectedTime = null;
            _slotsHint = 'No open slots on the previous date — showing ${_dateStr(next)}.';
          });
          await _loadSlots(allowAutoAdvance: false);
          _autoAdvancingDate = false;
          return;
        }
      }
      if (slots.isEmpty) {
        slots = _fallbackSlotsFor(_selectedDate!);
        hint = slots.isEmpty
            ? 'Clinic is closed on Sundays. Try Mon–Sat, or pick a time.'
            : 'Showing standard clinic hours (API returned no slots).';
      }

      setState(() {
        _slots = slots;
        _loadingSlots = false;
        _slotsHint = hint;
        if (result.doctorId != null) _resolvedDoctorId = result.doctorId;
        if (_selectedSlot != null && !slots.contains(_selectedSlot)) {
          _selectedSlot = null;
          _selectedTime = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = _fallbackSlotsFor(_selectedDate!);
      setState(() {
        _slots = fallback;
        _loadingSlots = false;
        _slotsHint = fallback.isEmpty
            ? 'Could not load slots. Try another day or pick a time.'
            : 'Could not reach slot API — showing standard clinic hours.';
      });
    }
  }

  void _pickSlot(String slot) {
    final parts = slot.split(':');
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    setState(() {
      _selectedSlot = slot;
      _selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _selectDate() async {
    final initial = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime.now()) ? DateTime.now() : initial,
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
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null;
        _selectedTime = null;
        _slotsHint = null;
      });
      await _loadSlots();
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
      setState(() {
        _selectedTime = picked;
        _selectedSlot =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  String _bookingErrorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Server took too long. Check that the local API is running.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'Cannot reach the API. Is it running on localhost:5000?';
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }

  Future<void> _submitBooking() async {
    setState(() => _submitting = true);
    try {
      final repo = context.read<AppointmentsRepository>();
      final dateStr = _dateStr(_selectedDate!);
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00';

      final deps =
          _dependantsControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      final doctorId = _resolvedDoctorId ?? _selectedDoctor?.id;
      if (doctorId == null) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a doctor before booking.')),
        );
        return;
      }

      final reason = _reason.text.trim().isEmpty ? 'General consultation' : _reason.text.trim();
      final service = _selectedService.isEmpty ? 'general consultation' : _selectedService;

      final apt = await repo.bookAppointment(
        fullName: _fullName.text,
        phoneNumber: _phoneNumber.text,
        email: _email.text,
        preferredDate: dateStr,
        preferredTime: timeStr,
        reason: reason,
        doctorId: doctorId,
        service: service,
        isTelemedicine: _isTelemedicine,
        nationwideId: _nationwideId.text,
        whoIsComing: deps,
        department: _department.text,
        notes: _notes.text,
        dependentPatientId: widget.dependentPatientId,
      );

      if (_isTelemedicine) {
        final notificationService = NotificationService();
        await notificationService.scheduleAppointmentReminder(apt);
        await notificationService.scheduleMeetingStartNotification(apt);
      }

      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        _bookedId = apt.appointmentId.isNotEmpty ? apt.appointmentId : 'GP-${apt.id}-CONF';
        _bookingTimeStr =
            '${now.month}/${now.day}/${now.year} ${TimeOfDay.fromDateTime(now).format(context)}';
        _currentStep = 3;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: ${_bookingErrorMessage(e)}')),
      );
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_formKeyBasic.currentState!.validate()) {
        setState(() => _currentStep = 1);
        if (_slots.isEmpty && _selectedDoctor != null) {
          _loadSlots();
        }
      }
    } else if (_currentStep == 1) {
      if (_selectedDoctor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a doctor to see.')),
        );
        return;
      }
      if (_selectedDate == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a date and an available slot.')),
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
    final progress = (_currentStep / 3.0).clamp(0.0, 1.0);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentStep == 3 ? 'Appointment Booked!' : 'Book a doctor',
                    style: GoogleFonts.roboto(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
            if (_currentStep < 3)
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                color: const Color(0xFF00D2C4),
                minHeight: 3,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildStepContent(),
                ),
              ),
            ),
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
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Icon(_currentStep == 2 ? Icons.check : Icons.chevron_right),
                      label: Text(
                        _submitting
                            ? 'Booking...'
                            : (_currentStep == 2 ? 'Confirm booking' : 'Next'),
                      ),
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
      case 0:
        return _buildBasicInfoStep();
      case 1:
        return _buildDetailsStep();
      case 2:
        return _buildReviewStep();
      case 3:
      default:
        return _buildSuccessStep();
    }
  }

  Widget _buildBasicInfoStep() {
    return Form(
      key: _formKeyBasic,
      child: Column(
        key: const ValueKey('basic-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Patient details',
            style: GoogleFonts.roboto(
              color: const Color(0xFF00D2C4),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _fullName,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Patient Full Name', Icons.person_outline),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Please enter patient full name' : null,
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
            decoration: _fieldDeco('Patient ID / Membership (optional)', Icons.badge_outlined),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _department,
            style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
            decoration: _fieldDeco('Office/Department (Optional)', Icons.business_outlined),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dependants / Who is coming?',
                style: GoogleFonts.roboto(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _dependantsControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add, size: 14, color: Color(0xFF00D2C4)),
                label: Text(
                  'Add Dependant',
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF00D2C4),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (_dependantsControllers.isEmpty)
            Text(
              'No dependants added. Leave empty if coming alone.',
              style: GoogleFonts.roboto(
                color: Colors.white30,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            )
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

  Widget _buildSlotPicker() {
    if (_selectedDoctor == null) {
      return Text(
        'Choose a doctor to see open slots.',
        style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
      );
    }
    if (_selectedDate == null) {
      return Text(
        'Choose a date to load this doctor\'s open slots.',
        style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
      );
    }
    if (_loadingSlots) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF00D2C4), strokeWidth: 2),
        ),
      );
    }
    if (_slots.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _slotsHint ?? 'No open slots loaded for this date.',
            style: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final next = DateTime(
                    _selectedDate!.year,
                    _selectedDate!.month,
                    _selectedDate!.day,
                  ).add(const Duration(days: 1));
                  setState(() {
                    _selectedDate = next;
                    _selectedSlot = null;
                    _selectedTime = null;
                    _slotsHint = null;
                  });
                  await _loadSlots();
                },
                icon: const Icon(Icons.event_available, size: 16, color: Color(0xFF00D2C4)),
                label: Text(
                  'Try next day',
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF00D2C4),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _selectTime,
                icon: const Icon(Icons.access_time, size: 16, color: Color(0xFF00D2C4)),
                label: Text(
                  _selectedTime == null
                      ? 'Pick a time anyway'
                      : 'Time: ${_selectedTime!.format(context)}',
                  style: GoogleFonts.roboto(
                    color: const Color(0xFF00D2C4),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_slotsHint != null) ...[
          Text(
            _slotsHint!,
            style: GoogleFonts.roboto(color: const Color(0xFF00D2C4), fontSize: 11),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'Available slots',
          style: GoogleFonts.roboto(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _slots.map((slot) {
            final selected = _selectedSlot == slot;
            return ChoiceChip(
              label: Text(slot),
              selected: selected,
              onSelected: (_) => _pickSlot(slot),
              selectedColor: const Color(0xFF00D2C4),
              labelStyle: GoogleFonts.roboto(
                color: selected ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: const Color(0xFF1E293B),
              side: BorderSide(
                color: selected ? const Color(0xFF00D2C4) : Colors.white12,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _selectTime,
          child: Text(
            'Or pick a custom time',
            style: GoogleFonts.roboto(color: const Color(0xFF94A3B8), fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      key: const ValueKey('details-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Doctor, date & slot',
          style: GoogleFonts.roboto(
            color: const Color(0xFF00D2C4),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
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
                      : 'Selected Date: ${_dateStr(_selectedDate!)}',
                  style: GoogleFonts.roboto(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedService.isEmpty ? null : _selectedService,
          dropdownColor: const Color(0xFF0F172A),
          decoration: _fieldDeco('Consult type', Icons.healing_outlined),
          items: _services
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, style: GoogleFonts.roboto(color: Colors.white, fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedService = v);
          },
        ),
        const SizedBox(height: 12),
        _loadingDoctors
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(color: Color(0xFF00D2C4)),
                ),
              )
            : DropdownButtonFormField<int>(
                value: _selectedDoctor?.id,
                dropdownColor: const Color(0xFF0F172A),
                decoration: _fieldDeco('Doctor to see', Icons.badge_outlined),
                items: _doctors
                    .map(
                      (d) => DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          d.specialization == null || d.specialization!.isEmpty
                              ? d.name
                              : '${d.name} · ${d.specialization}',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.roboto(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  DoctorProfile? match;
                  for (final d in _doctors) {
                    if (d.id == id) {
                      match = d;
                      break;
                    }
                  }
                  setState(() {
                    _selectedDoctor = match;
                    _resolvedDoctorId = id;
                    _selectedSlot = null;
                    _selectedTime = null;
                  });
                  _loadSlots();
                },
              ),
        if (_doctors.isEmpty && !_loadingDoctors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No doctors in the directory. Ask admin to activate clinicians.',
              style: GoogleFonts.roboto(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 15),
        _buildSlotPicker(),
        const SizedBox(height: 15),
        SwitchListTile(
          title: Text(
            'Telemedicine (Video Call)',
            style: GoogleFonts.roboto(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            'Consult online instead of physical clinic visit',
            style: GoogleFonts.roboto(color: Colors.white30, fontSize: 11),
          ),
          value: _isTelemedicine,
          activeColor: const Color(0xFF00D2C4),
          contentPadding: EdgeInsets.zero,
          onChanged: (val) => setState(() => _isTelemedicine = val),
        ),
        const SizedBox(height: 12),
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
    final dateStr = _selectedDate != null ? _dateStr(_selectedDate!) : '';
    final timeStr = _selectedTime != null ? _selectedTime!.format(context) : '';
    final deps =
        _dependantsControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

    return Column(
      key: const ValueKey('review-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Confirm reservation',
          style: GoogleFonts.roboto(
            color: const Color(0xFF00D2C4),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(2),
            },
            children: [
              _buildTableRow('Full Name', _fullName.text),
              _buildTableRow('Phone No', _phoneNumber.text),
              _buildTableRow('Patient ID', _nationwideId.text.isEmpty ? '—' : _nationwideId.text),
              _buildTableRow('Who is coming', deps.isEmpty ? 'Self' : 'Self + ${deps.join(", ")}'),
              _buildTableRow('Preferred Date', dateStr),
              _buildTableRow('Preferred Time', timeStr),
              _buildTableRow(
                'Consult Type',
                _isTelemedicine ? 'Telehealth (Online Video)' : 'Physical Clinic Visit',
              ),
              _buildTableRow(
                'Service',
                _selectedService.isEmpty ? 'general consultation' : _selectedService,
              ),
              _buildTableRow('Doctor', _selectedDoctor?.name ?? '—'),
              _buildTableRow(
                'Complaint',
                _reason.text.trim().isEmpty ? 'General consultation' : _reason.text,
              ),
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
          child: Text(
            val,
            style: GoogleFonts.roboto(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
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
            .scale(duration: 400.ms),
        const SizedBox(height: 20),
        Text(
          'Booking confirmed',
          style: GoogleFonts.roboto(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your visit is pending doctor approval.',
          textAlign: TextAlign.center,
          style: GoogleFonts.roboto(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00D2C4).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                'Reference',
                style: GoogleFonts.roboto(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                _bookedId,
                style: GoogleFonts.roboto(
                  color: const Color(0xFF00D2C4),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _bookingTimeStr,
                style: GoogleFonts.roboto(color: Colors.white54, fontSize: 12),
              ),
              if (_selectedDoctor != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selectedDoctor!.name,
                  style: GoogleFonts.roboto(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D2C4),
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            'Done',
            style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.roboto(color: Colors.white38, fontSize: 12),
      prefixIcon: Icon(icon, color: const Color(0xFF8B5CF6), size: 18),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.02),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00D2C4)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
