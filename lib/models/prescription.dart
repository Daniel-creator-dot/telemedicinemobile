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
    this.prescriptionRef,
    this.strength,
    this.route,
    this.quantity,
    this.pharmacyName,
    this.dispenseStatus,
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
  final String? prescriptionRef;
  final String? strength;
  final String? route;
  final String? quantity;
  final String? pharmacyName;
  final String? dispenseStatus;

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
      prescriptionRef: json['prescription_ref']?.toString(),
      strength: json['strength']?.toString(),
      route: json['route']?.toString(),
      quantity: json['quantity']?.toString(),
      pharmacyName: json['pharmacy_name']?.toString(),
      dispenseStatus: json['dispense_status']?.toString(),
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
