enum AppRole {
  patient,
  doctor,
  admin,
  labTechnician;

  static AppRole fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'doctor':
        return AppRole.doctor;
      case 'admin':
        return AppRole.admin;
      case 'lab_technician':
      case 'labtechnician':
        return AppRole.labTechnician;
      case 'patient':
      default:
        return AppRole.patient;
    }
  }

  String get name {
    switch (this) {
      case AppRole.patient:
        return 'patient';
      case AppRole.doctor:
        return 'doctor';
      case AppRole.admin:
        return 'admin';
      case AppRole.labTechnician:
        return 'lab_technician';
    }
  }

  String get label {
    switch (this) {
      case AppRole.patient:
        return 'Patient';
      case AppRole.doctor:
        return 'Doctor';
      case AppRole.admin:
        return 'Administrator';
      case AppRole.labTechnician:
        return 'Lab Technician';
    }
  }
}
