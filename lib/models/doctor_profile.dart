class DoctorProfile {
  const DoctorProfile({
    required this.id,
    required this.name,
    this.specialization,
    this.title,
    this.qualifications,
    this.registrationNumber,
    this.yearsExperience,
    this.languages,
    this.biography,
    this.consultationFee,
    this.facility,
    this.isOnline = false,
    this.slotDuration = 15,
    this.userId,
  });

  final int id;
  final String name;
  final String? specialization;
  final String? title;
  final String? qualifications;
  final String? registrationNumber;
  final int? yearsExperience;
  final String? languages;
  final String? biography;
  final double? consultationFee;
  final String? facility;
  final bool isOnline;
  final int slotDuration;
  final int? userId;

  factory DoctorProfile.fromJson(Map<String, dynamic> json) {
    return DoctorProfile(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? json['user_name']?.toString() ?? 'Doctor',
      specialization: json['specialization']?.toString(),
      title: json['title']?.toString(),
      qualifications: json['qualifications']?.toString(),
      registrationNumber: json['registration_number']?.toString(),
      yearsExperience: json['years_experience'] is int
          ? json['years_experience'] as int
          : int.tryParse(json['years_experience']?.toString() ?? ''),
      languages: json['languages']?.toString(),
      biography: json['biography']?.toString(),
      consultationFee: json['consultation_fee'] == null
          ? null
          : double.tryParse(json['consultation_fee'].toString()),
      facility: json['facility']?.toString(),
      isOnline: json['is_online'] == true,
      slotDuration: json['slot_duration'] as int? ?? 15,
      userId: json['user_id'] as int?,
    );
  }
}
