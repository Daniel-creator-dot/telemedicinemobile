import '../../core/api_client.dart';
import '../../models/appointment.dart';
import '../../models/prescription.dart';
import '../../models/consultation.dart';
import '../../models/auth_user.dart';

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
      },
    );
    if (res.data == null) throw Exception('Booking failed: Empty response');
    return Appointment.fromJson(res.data!);
  }

  Future<void> payForAppointment(int id) async {
    await _api.dio.post<Map<String, dynamic>>('/api/appointments/$id/pay');
  }

  Future<Map<String, dynamic>> initializePaystackPayment(int id) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/appointments/$id/pay/initialize');
    if (res.data == null) throw Exception('Payment initialization failed');
    return res.data!;
  }

  Future<Map<String, dynamic>> verifyPaystackPayment(int id, String reference) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/appointments/$id/pay/verify',
      data: {'reference': reference},
    );
    if (res.data == null) throw Exception('Payment verification failed');
    return res.data!;
  }

  Future<List<AuthUser>> getAvailableDoctors() async {
    final res = await _api.dio.get<List<dynamic>>('/api/users');
    if (res.data == null) return [];
    final allUsers = res.data!.map((json) => AuthUser.fromJson(json as Map<String, dynamic>)).toList();
    // Filter to only return doctors
    return allUsers.where((u) => u.role.name == 'doctor').toList();
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
}
