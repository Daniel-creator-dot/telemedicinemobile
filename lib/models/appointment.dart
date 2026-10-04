class Appointment {
  const Appointment({
    required this.id,
    required this.appointmentId,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    required this.preferredDate,
    required this.preferredTime,
    required this.status,
    required this.isTelemedicine,
    required this.paymentStatus,
    this.meetingLink,
    this.doctorName,
    this.doctorId,
    this.service,
    this.priority,
    this.notes,
    this.staffId,
    this.nationwideId,
    this.whoIsComing,
    this.patientId,
    this.bookingType,
    this.consultType,
    this.queueNumber,
    this.etaMinutes,
    this.complaint,
  });

  final int id;
  final String appointmentId;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String preferredDate;
  final String preferredTime;
  final String status;
  final bool isTelemedicine;
  final String paymentStatus;
  final String? meetingLink;
  final String? doctorName;
  final int? doctorId;
  final String? service;
  final String? priority;
  final String? notes;
  final String? staffId;
  final String? nationwideId;
  final List<String>? whoIsComing;
  final int? patientId;
  final String? bookingType;
  final String? consultType;
  final int? queueNumber;
  final int? etaMinutes;
  final String? complaint;

  factory Appointment.fromJson(Map<String, dynamic> json) {
    // Parse who_is_coming which can be a list or a string
    List<String>? whoIsComing;
    final raw = json['who_is_coming'];
    if (raw is List) {
      whoIsComing = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      whoIsComing = [raw];
    }

    return Appointment(
      id: _readInt(json['id']) ?? 0,
      appointmentId: json['appointment_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      email: json['email']?.toString(),
      preferredDate: _dateOnly(json['preferred_date']),
      preferredTime: _timeOnly(json['preferred_time']),
      status: json['status']?.toString() ?? 'pending',
      isTelemedicine: _readBool(json['is_telemedicine']) ||
          json['booking_type']?.toString() == 'consult_now',
      paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
      meetingLink: _readLink(json['meeting_link']),
      doctorName: json['doctor_name']?.toString(),
      doctorId: _readInt(json['doctor_id']),
      service: json['service']?.toString(),
      priority: json['priority']?.toString(),
      notes: json['notes']?.toString(),
      staffId: json['staff_id']?.toString(),
      nationwideId: json['nationwide_id']?.toString(),
      whoIsComing: whoIsComing,
      patientId: _readInt(json['patient_id']),
      bookingType: json['booking_type']?.toString(),
      consultType: json['consult_type']?.toString(),
      queueNumber: _readInt(json['queue_number']),
      etaMinutes: _readInt(json['eta_minutes']),
      complaint: json['complaint']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointment_id': appointmentId,
        'full_name': fullName,
        'phone_number': phoneNumber,
        if (email != null) 'email': email,
        'preferred_date': preferredDate,
        'preferred_time': preferredTime,
        'status': status,
        'is_telemedicine': isTelemedicine,
        'payment_status': paymentStatus,
        if (meetingLink != null) 'meeting_link': meetingLink,
        if (doctorName != null) 'doctor_name': doctorName,
        if (doctorId != null) 'doctor_id': doctorId,
        if (service != null) 'service': service,
        if (priority != null) 'priority': priority,
        if (notes != null) 'notes': notes,
        if (staffId != null) 'staff_id': staffId,
        if (nationwideId != null) 'nationwide_id': nationwideId,
        if (whoIsComing != null) 'who_is_coming': whoIsComing,
        if (patientId != null) 'patient_id': patientId,
        if (bookingType != null) 'booking_type': bookingType,
        if (consultType != null) 'consult_type': consultType,
        if (queueNumber != null) 'queue_number': queueNumber,
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
        if (complaint != null) 'complaint': complaint,
      };

  bool get isConsultNow => bookingType == 'consult_now';

  bool get hasMeetingLink => meetingLink != null && meetingLink!.trim().isNotEmpty;

  bool get isVideoConsult => isTelemedicine || isConsultNow || hasMeetingLink;

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String _dateOnly(dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return '';
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(s);
    return m?.group(1) ?? s;
  }

  static String _timeOnly(dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return '';
    // Accept "HH:MM:SS", "HH:MM", or DateTime-ish strings.
    final m = RegExp(r'(\d{1,2}:\d{2}(?::\d{2})?)').firstMatch(s);
    return m?.group(1) ?? s;
  }

  static bool _readBool(dynamic value) {
    if (value == true || value == 1) return true;
    final s = value?.toString().toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
  }

  static String? _readLink(dynamic value) {
    final s = value?.toString().trim();
    if (s == null || s.isEmpty || s == 'null') return null;
    return s;
  }

  bool get isLiveConsult {
    final s = status.toLowerCase();
    return s == 'approved' || s == 'arrived' || s == 'consulting';
  }

  bool get isWaitingInQueue {
    final s = status.toLowerCase();
    return s == 'queued' || s == 'pending' || s == 'triage';
  }

  Appointment copyWith({
    String? status,
    String? paymentStatus,
    String? meetingLink,
    String? doctorName,
    int? doctorId,
    int? queueNumber,
    int? etaMinutes,
  }) {
    return Appointment(
      id: id,
      appointmentId: appointmentId,
      fullName: fullName,
      phoneNumber: phoneNumber,
      email: email,
      preferredDate: preferredDate,
      preferredTime: preferredTime,
      status: status ?? this.status,
      isTelemedicine: isTelemedicine,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      meetingLink: meetingLink ?? this.meetingLink,
      doctorName: doctorName ?? this.doctorName,
      doctorId: doctorId ?? this.doctorId,
      service: service,
      priority: priority,
      notes: notes,
      staffId: staffId,
      nationwideId: nationwideId,
      whoIsComing: whoIsComing,
      patientId: patientId,
      bookingType: bookingType,
      consultType: consultType,
      queueNumber: queueNumber ?? this.queueNumber,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      complaint: complaint,
    );
  }
}
