class Consultation {
  const Consultation({
    required this.id,
    required this.appointmentId,
    required this.patientId,
    required this.doctorId,
    this.chiefComplaint,
    this.symptoms,
    this.diagnosis,
    this.clinicalNotes,
    this.vitalsBp,
    this.vitalsTemp,
    this.vitalsPulse,
    this.vitalsWeight,
    this.vitalsHeight,
    this.vitalsSpo2,
    this.followUpDate,
    required this.status,
    this.createdAt,
    this.doctorName,
    this.preferredDate,
    this.service,
    this.appointmentNotes,
  });

  final int id;
  final int appointmentId;
  final int patientId;
  final int doctorId;
  final String? chiefComplaint;
  final String? symptoms;
  final String? diagnosis;
  final String? clinicalNotes;
  final String? vitalsBp;
  final String? vitalsTemp;
  final String? vitalsPulse;
  final String? vitalsWeight;
  final String? vitalsHeight;
  final String? vitalsSpo2;
  final String? followUpDate;
  final String status;
  final String? createdAt;
  final String? doctorName;
  final String? preferredDate;
  final String? service;
  final String? appointmentNotes;

  factory Consultation.fromJson(Map<String, dynamic> json) {
    return Consultation(
      id: json['id'] as int? ?? 0,
      appointmentId: json['appointment_id'] as int? ?? 0,
      patientId: json['patient_id'] as int? ?? 0,
      doctorId: json['doctor_id'] as int? ?? 0,
      chiefComplaint: json['chief_complaint']?.toString(),
      symptoms: json['symptoms']?.toString(),
      diagnosis: json['diagnosis']?.toString(),
      clinicalNotes: json['clinical_notes']?.toString(),
      vitalsBp: json['vitals_bp']?.toString(),
      vitalsTemp: json['vitals_temp']?.toString(),
      vitalsPulse: json['vitals_pulse']?.toString(),
      vitalsWeight: json['vitals_weight']?.toString(),
      vitalsHeight: json['vitals_height']?.toString(),
      vitalsSpo2: json['vitals_spo2']?.toString(),
      followUpDate: json['follow_up_date']?.toString(),
      status: json['status']?.toString() ?? 'in_progress',
      createdAt: json['created_at']?.toString(),
      doctorName: json['doctor_name']?.toString(),
      preferredDate: json['preferred_date']?.toString(),
      service: json['service']?.toString(),
      appointmentNotes: json['appointment_notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'appointment_id': appointmentId,
        'patient_id': patientId,
        'doctor_id': doctorId,
        if (chiefComplaint != null) 'chief_complaint': chiefComplaint,
        if (symptoms != null) 'symptoms': symptoms,
        if (diagnosis != null) 'diagnosis': diagnosis,
        if (clinicalNotes != null) 'clinical_notes': clinicalNotes,
        if (vitalsBp != null) 'vitals_bp': vitalsBp,
        if (vitalsTemp != null) 'vitals_temp': vitalsTemp,
        if (vitalsPulse != null) 'vitals_pulse': vitalsPulse,
        if (vitalsWeight != null) 'vitals_weight': vitalsWeight,
        if (vitalsHeight != null) 'vitals_height': vitalsHeight,
        if (vitalsSpo2 != null) 'vitals_spo2': vitalsSpo2,
        if (followUpDate != null) 'follow_up_date': followUpDate,
        'status': status,
        if (createdAt != null) 'created_at': createdAt,
        if (doctorName != null) 'doctor_name': doctorName,
        if (preferredDate != null) 'preferred_date': preferredDate,
        if (service != null) 'service': service,
        if (appointmentNotes != null) 'appointment_notes': appointmentNotes,
      };
}
