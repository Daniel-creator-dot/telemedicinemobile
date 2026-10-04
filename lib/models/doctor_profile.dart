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
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
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
      isOnline: json['is_online'] == true ||
          json['is_online'] == 1 ||
          json['is_online']?.toString().toLowerCase() == 'true' ||
          json['is_online']?.toString() == 't' ||
          json['is_online']?.toString() == '1',
      slotDuration: json['slot_duration'] is int
          ? json['slot_duration'] as int
          : int.tryParse(json['slot_duration']?.toString() ?? '') ?? 30,
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse(json['user_id']?.toString() ?? ''),
    );
  }

  DoctorProfile copyWith({bool? isOnline}) {
    return DoctorProfile(
      id: id,
      name: name,
      specialization: specialization,
      title: title,
      qualifications: qualifications,
      registrationNumber: registrationNumber,
      yearsExperience: yearsExperience,
      languages: languages,
      biography: biography,
      consultationFee: consultationFee,
      facility: facility,
      isOnline: isOnline ?? this.isOnline,
      slotDuration: slotDuration,
      userId: userId,
    );
  }
}
