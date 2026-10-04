class PatientProfile {
  const PatientProfile({
    required this.id,
    this.patientCode,
    required this.fullName,
    this.email,
    required this.phoneNumber,
    this.dateOfBirth,
    this.sex,
    this.region,
    this.town,
    this.address,
    this.occupation,
    this.emergencyName,
    this.emergencyPhone,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.bloodGroup,
    this.genotype,
    this.allergies,
    this.chronicConditions,
    this.currentMedications,
    this.previousDiagnoses,
    this.surgeries,
    this.familyHistory,
    this.socialHistory,
    this.preferredLocation,
    this.nationwideId,
    this.profileComplete = false,
  });

  final int id;
  final String? patientCode;
  final String fullName;
  final String? email;
  final String phoneNumber;
  final String? dateOfBirth;
  final String? sex;
  final String? region;
  final String? town;
  final String? address;
  final String? occupation;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? bloodGroup;
  final String? genotype;
  final String? allergies;
  final String? chronicConditions;
  final String? currentMedications;
  final String? previousDiagnoses;
  final String? surgeries;
  final String? familyHistory;
  final String? socialHistory;
  final String? preferredLocation;
  final String? nationwideId;
  final bool profileComplete;

  factory PatientProfile.fromJson(Map<String, dynamic> json) {
    return PatientProfile(
      id: json['id'] as int? ?? 0,
      patientCode: json['patient_code']?.toString(),
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString(),
      phoneNumber: json['phone_number']?.toString() ?? '',
      dateOfBirth: json['date_of_birth']?.toString(),
      sex: json['sex']?.toString(),
      region: json['region']?.toString(),
      town: json['town']?.toString(),
      address: json['address']?.toString(),
      occupation: json['occupation']?.toString(),
      emergencyName: json['emergency_name']?.toString(),
      emergencyPhone: json['emergency_phone']?.toString(),
      nextOfKinName: json['next_of_kin_name']?.toString(),
      nextOfKinPhone: json['next_of_kin_phone']?.toString(),
      bloodGroup: json['blood_group']?.toString(),
      genotype: json['genotype']?.toString(),
      allergies: json['allergies']?.toString(),
      chronicConditions: json['chronic_conditions']?.toString(),
      currentMedications: json['current_medications']?.toString(),
      previousDiagnoses: json['previous_diagnoses']?.toString(),
      surgeries: json['surgeries']?.toString(),
      familyHistory: json['family_history']?.toString(),
      socialHistory: json['social_history']?.toString(),
      preferredLocation: json['preferred_location']?.toString(),
      nationwideId: json['nationwide_id']?.toString(),
      profileComplete: json['profile_complete'] == true,
    );
  }

  Map<String, dynamic> toPayload() => {
        'full_name': fullName,
        'email': email,
        'phone_number': phoneNumber,
        'date_of_birth': dateOfBirth?.split('T').first,
        'sex': sex,
        'region': region,
        'town': town,
        'address': address,
        'occupation': occupation,
        'emergency_name': emergencyName,
        'emergency_phone': emergencyPhone,
        'next_of_kin_name': nextOfKinName,
        'next_of_kin_phone': nextOfKinPhone,
        'blood_group': bloodGroup,
        'genotype': genotype,
        'allergies': allergies,
        'chronic_conditions': chronicConditions,
        'current_medications': currentMedications,
        'previous_diagnoses': previousDiagnoses,
        'surgeries': surgeries,
        'family_history': familyHistory,
        'social_history': socialHistory,
        'preferred_location': preferredLocation,
        'nationwide_id': nationwideId,
      };
}
