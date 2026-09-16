import '../../core/api_client.dart';
import '../../models/appointment.dart';
import '../../models/prescription.dart';
import '../../models/consultation.dart';
import '../../models/auth_user.dart';
import '../../models/role.dart';

class AppointmentsRepository {
  AppointmentsRepository(this._api);

  final ApiClient _api;

  Future<List<Appointment>> getMyAppointments() async {
    final res = await _api.dio.get<List<dynamic>>('/api/appointments/my');
    if (res.data == null) return [];
    return res.data!.map((json) => Appointment.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<Appointment>> getAllAppointments() async {
    final res = await _api.dio.get<List<dynamic>>('/api/appointments');
    if (res.data == null) return [];
    return res.data!.map((json) => Appointment.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<Appointment> bookAppointment({
    required String fullName,
    required String phoneNumber,
    String? email,
    required String preferredDate,
    required String preferredTime,
    required String reason,
    int? doctorId,
    String? service,
    bool isTelemedicine = false,
    String? nationwideId,
    List<String>? whoIsComing,
    String? department,
    String? notes,
    int? dependentPatientId,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/appointments',
      data: {
        'fullName': fullName.trim(),
        'phoneNumber': phoneNumber.trim(),
        if (email != null && email.isNotEmpty) 'email': email.trim(),
        'preferredDate': preferredDate,
        'preferredTime': preferredTime,
        'reason': reason.trim(),
        if (doctorId != null) 'doctor_id': doctorId,
        if (service != null && service.isNotEmpty) 'service': service,
        'isTelemedicine': isTelemedicine,
        if (nationwideId != null && nationwideId.isNotEmpty) 'nationwideId': nationwideId.trim(),
        if (whoIsComing != null && whoIsComing.isNotEmpty) 'whoIsComing': whoIsComing,
        if (department != null && department.isNotEmpty) 'department': department.trim(),
        if (notes != null && notes.isNotEmpty) 'notes': notes.trim(),
        if (service != null && service.isNotEmpty) 'consult_type': service,
        'booking_type': 'scheduled',
        if (dependentPatientId != null) 'dependent_patient_id': dependentPatientId,
      },
    );
    if (res.data == null) throw Exception('Booking failed: Empty response');
    return Appointment.fromJson(res.data!);
  }

  Future<Map<String, dynamic>> initializePay(int id) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/appointments/$id/pay/initialize');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> verifyPay(int id, String reference) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/appointments/$id/pay',
      data: {'reference': reference},
    );
    return res.data ?? {};
  }

  Future<List<AuthUser>> getAvailableDoctors() async {
    final res = await _api.dio.get<List<dynamic>>('/api/doctors/directory');
    if (res.data == null) return [];
    // Directory returns doctors.id — never fall back to /api/users (users.id mismatch).
    return res.data!.map((json) {
      final map = json as Map<String, dynamic>;
      return AuthUser(
        id: map['id'].toString(),
        username: map['name']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Doctor',
        role: AppRole.doctor,
      );
    }).toList();
  }

  Future<List<Prescription>> getMyPrescriptions() async {
    final res = await _api.dio.get<List<dynamic>>('/api/prescriptions/my');
    if (res.data == null) return [];
    return res.data!.map((json) => Prescription.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<List<Consultation>> getMyConsultations() async {
    final res = await _api.dio.get<List<dynamic>>('/api/consultations/my');
    if (res.data == null) return [];
    return res.data!.map((json) => Consultation.fromJson(json as Map<String, dynamic>)).toList();
  }

  Future<void> updateAppointmentStatus(int id, String status) async {
    await _api.dio.patch<Map<String, dynamic>>(
      '/api/appointments/$id/status',
      data: {'status': status},
    );
  }

  Future<Appointment?> getAppointmentById(int id) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/api/appointments/$id');
      if (res.data != null) return Appointment.fromJson(res.data!);
    } catch (_) {}
    try {
      final mine = await getMyAppointments();
      for (final apt in mine) {
        if (apt.id == id) return apt;
      }
    } catch (_) {}
    try {
      final all = await getAllAppointments();
      for (final apt in all) {
        if (apt.id == id) return apt;
      }
    } catch (_) {}
    return null;
  }

  Future<Appointment> generateMeetingLink(int id) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/appointments/$id/generate-link');
    if (res.data == null) throw Exception('Could not create meeting link');
    return Appointment.fromJson(res.data!);
  }
}
