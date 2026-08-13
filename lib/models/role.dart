enum AppRole {
  patient,
  doctor,
  admin,
  labTechnician,
  nurse,
  medicalOps,
  pharmacy,
  imaging,
  corporate,
  insurance,
  finance;

  static AppRole fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'doctor':
        return AppRole.doctor;
      case 'admin':
        return AppRole.admin;
      case 'lab_technician':
      case 'labtechnician':
        return AppRole.labTechnician;
      case 'nurse':
        return AppRole.nurse;
      case 'medical_ops':
      case 'medicalops':
        return AppRole.medicalOps;
      case 'pharmacy':
        return AppRole.pharmacy;
      case 'imaging':
        return AppRole.imaging;
      case 'corporate':
        return AppRole.corporate;
      case 'insurance':
        return AppRole.insurance;
      case 'finance':
        return AppRole.finance;
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
      case AppRole.nurse:
        return 'nurse';
      case AppRole.medicalOps:
        return 'medical_ops';
      case AppRole.pharmacy:
        return 'pharmacy';
      case AppRole.imaging:
        return 'imaging';
      case AppRole.corporate:
        return 'corporate';
      case AppRole.insurance:
        return 'insurance';
      case AppRole.finance:
        return 'finance';
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
      case AppRole.nurse:
        return 'Nurse / Triage';
      case AppRole.medicalOps:
        return 'Medical Operations';
      case AppRole.pharmacy:
        return 'Pharmacy';
      case AppRole.imaging:
        return 'Imaging Centre';
      case AppRole.corporate:
        return 'Corporate';
      case AppRole.insurance:
        return 'Insurance';
      case AppRole.finance:
        return 'Finance';
    }
  }
}
