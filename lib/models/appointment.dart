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
      id: json['id'] as int? ?? 0,
      appointmentId: json['appointment_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      email: json['email']?.toString(),
      preferredDate: json['preferred_date']?.toString() ?? '',
      preferredTime: json['preferred_time']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      isTelemedicine: json['is_telemedicine'] == true || json['is_telemedicine'] == 1,
      paymentStatus: json['payment_status']?.toString() ?? 'unpaid',
      meetingLink: json['meeting_link']?.toString(),
      doctorName: json['doctor_name']?.toString(),
      doctorId: json['doctor_id'] as int?,
      service: json['service']?.toString(),
      priority: json['priority']?.toString(),
      notes: json['notes']?.toString(),
      staffId: json['staff_id']?.toString(),
      nationwideId: json['nationwide_id']?.toString(),
      whoIsComing: whoIsComing,
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
      };
}
