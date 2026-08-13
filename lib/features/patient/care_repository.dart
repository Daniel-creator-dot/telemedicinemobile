import '../../core/api_client.dart';
import '../../models/appointment.dart';
import '../../models/chat_message.dart';
import '../../models/doctor_profile.dart';
import '../../models/patient_profile.dart';

class CareRepository {
  CareRepository(this._api);
  final ApiClient _api;

  Future<PatientProfile> getMyProfile() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/patients/me');
    return PatientProfile.fromJson(res.data ?? {});
  }

  Future<PatientProfile> saveMyProfile(Map<String, dynamic> payload) async {
    final res = await _api.dio.put<Map<String, dynamic>>('/api/patients/me', data: payload);
    return PatientProfile.fromJson(res.data ?? {});
  }

  Future<List<DoctorProfile>> getDirectory({String? specialty, String? q}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/doctors/directory',
      queryParameters: {
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    return (res.data ?? [])
        .map((e) => DoctorProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> getSlots(int doctorId, String date) async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/doctors/$doctorId/slots', queryParameters: {'date': date});
    final slots = res.data?['slots'];
    if (slots is List) return slots.map((e) => e.toString()).toList();
    return [];
  }

  Future<List<String>> getConsultTypes() async {
    final res = await _api.dio.get<List<dynamic>>('/api/meta/consult-types');
    return (res.data ?? []).map((e) => e.toString()).toList();
  }

  Future<Appointment> consultNow(Map<String, dynamic> triage) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/queue/consult-now', data: triage);
    final apt = res.data?['appointment'] ?? res.data;
    return Appointment.fromJson(Map<String, dynamic>.from(apt as Map));
  }

  Future<List<Appointment>> getQueue() async {
    final res = await _api.dio.get<List<dynamic>>('/api/queue');
    return (res.data ?? []).map((e) => Appointment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getTriage() async {
    final res = await _api.dio.get<List<dynamic>>('/api/triage');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> updateTriage(int id, Map<String, dynamic> data) async {
    await _api.dio.put('/api/triage/$id', data: data);
  }

  Future<void> assignQueue(int appointmentId, Map<String, dynamic> data) async {
    await _api.dio.patch('/api/queue/$appointmentId/assign', data: data);
  }

  Future<List<ChatMessage>> getChat(int appointmentId) async {
    final res = await _api.dio.get<List<dynamic>>('/api/chat/$appointmentId');
    return (res.data ?? []).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChatMessage> sendChat(int appointmentId, String body) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/chat/$appointmentId', data: {'body': body});
    return ChatMessage.fromJson(res.data ?? {});
  }

  Future<List<Map<String, dynamic>>> myNotifications() async {
    final res = await _api.dio.get<List<dynamic>>('/api/notifications/me');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> opsDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/ops/dashboard');
    return res.data ?? {};
  }

  Future<void> setDoctorOnline(bool online) async {
    await _api.dio.patch('/api/doctors/me/availability', data: {'is_online': online});
  }

  Future<List<Map<String, dynamic>>> getPartners({String? type, String? region}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/partners',
      queryParameters: {
        if (type != null) 'type': type,
        if (region != null) 'region': region,
      },
    );
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> nearbyPartners({required String type, int? patientId}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/partners/nearby',
      queryParameters: {
        'type': type,
        if (patientId != null) 'patient_id': patientId,
      },
    );
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> myPartnerOrg() async {
    final res = await _api.dio.get('/api/partners/me');
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Map<String, dynamic>> sendPrescriptionToPharmacy(int id, {int? pharmacyId}) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/prescriptions/$id/send',
      data: {if (pharmacyId != null) 'pharmacy_id': pharmacyId},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> pharmacyQueue() async {
    final res = await _api.dio.get<List<dynamic>>('/api/pharmacy/queue');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> updatePharmacyStatus(int id, String status, {String? notes}) async {
    await _api.dio.patch('/api/pharmacy/prescriptions/$id', data: {'status': status, if (notes != null) 'notes': notes});
  }

  Future<List<Map<String, dynamic>>> getReferrals() async {
    final res = await _api.dio.get<List<dynamic>>('/api/referrals');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createReferral(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/referrals', data: payload);
    return res.data ?? {};
  }

  Future<void> updateReferral(int id, Map<String, dynamic> payload) async {
    await _api.dio.patch('/api/referrals/$id', data: payload);
  }

  Future<Map<String, dynamic>> myNetwork() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/network/mine');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> eligibility({int? patientId}) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/api/billing/eligibility',
      queryParameters: {if (patientId != null) 'patient_id': patientId},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> corporateDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/corporate/dashboard');
    return res.data ?? {};
  }

  Future<void> addCorporateMember({required String patientCode, String? staffId, String? department}) async {
    await _api.dio.post('/api/corporate/members', data: {
      'patient_code': patientCode,
      if (staffId != null) 'staff_id': staffId,
      if (department != null) 'department': department,
    });
  }

  Future<void> updateCorporateMember(int id, String status) async {
    await _api.dio.patch('/api/corporate/members/$id', data: {'status': status});
  }

  Future<Map<String, dynamic>> insuranceWorkbench() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/insurance/workbench');
    return res.data ?? {};
  }

  Future<void> updatePreauth(int id, Map<String, dynamic> payload) async {
    await _api.dio.patch('/api/insurance/preauths/$id', data: payload);
  }

  Future<void> updateClaim(int id, Map<String, dynamic> payload) async {
    await _api.dio.patch('/api/insurance/claims/$id', data: payload);
  }

  Future<Map<String, dynamic>> financeDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/finance/dashboard');
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> runSettlements() async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/finance/settlements/run');
    final created = res.data?['created'];
    if (created is List) return created.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Future<void> updateSettlement(int id, String status) async {
    await _api.dio.patch('/api/finance/settlements/$id', data: {'status': status});
  }

  Future<void> markNotificationsRead() async {
    await _api.dio.patch('/api/notifications/me/read');
  }

  Future<Map<String, dynamic>> healthJourney() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/journey/me');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> documentVault() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/vault/me');
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> getTracker({int? patientId}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/tracker',
      queryParameters: {if (patientId != null) 'patient_id': patientId},
    );
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> addTracker(Map<String, dynamic> payload) async {
    await _api.dio.post('/api/tracker', data: payload);
  }

  Future<List<Map<String, dynamic>>> chronicPrograms({int? patientId}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/chronic/me',
      queryParameters: {if (patientId != null) 'patient_id': patientId},
    );
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> chronicCatalog() async {
    final res = await _api.dio.get<List<dynamic>>('/api/chronic/catalog');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> enrollChronic(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/chronic', data: payload);
    return res.data ?? {};
  }

  Future<void> updateChronicTask(int programId, int taskId, Map<String, dynamic> payload) async {
    await _api.dio.patch('/api/chronic/$programId/tasks/$taskId', data: payload);
  }

  Future<List<Map<String, dynamic>>> getFamily() async {
    final res = await _api.dio.get<List<dynamic>>('/api/family');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> addDependent(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/family', data: payload);
    return res.data ?? {};
  }

  Future<void> removeDependent(int id) async {
    await _api.dio.delete('/api/family/$id');
  }

  Future<Map<String, dynamic>> addVaultDocument(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/vault/documents', data: payload);
    return res.data ?? {};
  }

  Future<void> deleteVaultDocument(int id) async {
    await _api.dio.delete('/api/vault/documents/$id');
  }

  Future<Map<String, dynamic>> aiAssist(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/ai/assist', data: payload);
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> adminOpsSummary() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/admin/ops-summary');
    return res.data ?? {};
  }
}
