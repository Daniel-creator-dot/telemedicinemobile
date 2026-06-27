class Prescription {
  const Prescription({
    required this.id,
    required this.appointmentId,
    required this.patientId,
    required this.medicationName,
    this.dosage,
    this.frequency,
    this.duration,
    this.instructions,
    this.createdAt,
    this.patientName,
    this.aptCode,
  });

  final int id;
  final int appointmentId;
  final int patientId;
  final String medicationName;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? instructions;
  final String? createdAt;
  final String? patientName;
  final String? aptCode;

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: json['id'] as int? ?? 0,
      appointmentId: json['appointment_id'] as int? ?? 0,
      patientId: json['patient_id'] as int? ?? 0,
      medicationName: json['medication_name']?.toString() ?? '',
      dosage: json['dosage']?.toString(),
      frequency: json['frequency']?.toString(),
      duration: json['duration']?.toString(),
      instructions: json['instructions']?.toString(),
      createdAt: json['created_at']?.toString(),
      patientName: json['patient_name']?.toString(),
      aptCode: json['apt_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointment_id': appointmentId,
        'patient_id': patientId,
        'medication_name': medicationName,
        if (dosage != null) 'dosage': dosage,
        if (frequency != null) 'frequency': frequency,
        if (duration != null) 'duration': duration,
        if (instructions != null) 'instructions': instructions,
        if (createdAt != null) 'created_at': createdAt,
        if (patientName != null) 'patient_name': patientName,
        if (aptCode != null) 'apt_code': aptCode,
      };
}
