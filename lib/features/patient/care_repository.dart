import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/appointment.dart';
import '../../models/chat_message.dart';
import '../../models/doctor_profile.dart';
import '../../models/patient_profile.dart';

class DoctorSlotsResult {
  const DoctorSlotsResult({
    required this.date,
    required this.slots,
    this.nextAvailableDate,
    this.doctorId,
  });

  final String date;
  final List<String> slots;
  final String? nextAvailableDate;
  final int? doctorId;
}

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

  Future<List<DoctorProfile>> getDirectory({String? specialty, String? q, String? language, String? region}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/doctors/directory',
      queryParameters: {
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (q != null && q.isNotEmpty) 'q': q,
        if (language != null && language.isNotEmpty) 'language': language,
        if (region != null && region.isNotEmpty) 'region': region,
      },
    );
    return (res.data ?? [])
        .map((e) => DoctorProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DoctorSlotsResult> getSlots(int doctorId, String date) async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/doctors/$doctorId/slots', queryParameters: {'date': date});
    final data = res.data ?? {};
    final slots = data['slots'];
    return DoctorSlotsResult(
      date: data['date']?.toString() ?? date,
      slots: slots is List ? slots.map((e) => e.toString()).toList() : const [],
      nextAvailableDate: data['next_available_date']?.toString(),
      doctorId: data['doctor_id'] is int
          ? data['doctor_id'] as int
          : int.tryParse(data['doctor_id']?.toString() ?? ''),
    );
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

  Future<List<Map<String, dynamic>>> getChatThreads() async {
    final res = await _api.dio.get<List<dynamic>>('/api/chat/me/threads');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<int> unreadChatCount() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/chat/me/unread-count');
    final count = res.data?['count'];
    if (count is int) return count;
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  Future<void> markChatRead(int appointmentId) async {
    await _api.dio.patch('/api/chat/$appointmentId/read');
  }

  Future<List<Map<String, dynamic>>> myNotifications() async {
    final res = await _api.dio.get<List<dynamic>>('/api/notifications/me');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<int> unreadNotificationCount() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/notifications/me/unread-count');
    final count = res.data?['count'];
    if (count is int) return count;
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> opsDashboard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/ops/dashboard');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> opsBoard() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/ops/board');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> opsAssignPartner({
    required String kind,
    required int id,
    required int partnerId,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/ops/partner-assign',
      data: {'kind': kind, 'id': id, 'partner_id': partnerId},
    );
    return res.data ?? {};
  }

  Future<DoctorProfile> getMyDoctorProfile() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/doctors/me');
    return DoctorProfile.fromJson(res.data ?? {});
  }

  Future<void> setDoctorOnline(bool online) async {
    await _api.dio.patch('/api/doctors/me/availability', data: {'is_online': online});
  }

  Future<void> doctorHeartbeat() async {
    await _api.dio.post('/api/doctors/me/heartbeat');
  }

  /// Cheap poll for live online/offline badges.
  Future<Map<int, bool>> getDoctorPresence() async {
    final res = await _api.dio.get<List<dynamic>>('/api/doctors/presence');
    final map = <int, bool>{};
    for (final row in res.data ?? const []) {
      if (row is! Map) continue;
      final id = row['id'] is int ? row['id'] as int : int.tryParse(row['id']?.toString() ?? '');
      if (id == null) continue;
      final online = row['is_online'] == true ||
          row['is_online'] == 1 ||
          row['is_online']?.toString().toLowerCase() == 'true' ||
          row['is_online']?.toString() == 't';
      map[id] = online;
    }
    return map;
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

  Future<List<Map<String, dynamic>>> pharmacyQueue({String scope = 'active'}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/pharmacy/queue',
      queryParameters: {'scope': scope},
    );
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

  Future<Map<String, dynamic>> billingPayers() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/billing/payers');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> checkEligibility({
    required String source,
    required String memberKey,
    int? payerId,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/billing/eligibility/check',
      data: {
        'source': source,
        'member_key': memberKey,
        if (payerId != null) 'payer_id': payerId,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> attachCoverage({
    required String source,
    required String memberKey,
    int? payerId,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/billing/coverage/attach',
      data: {
        'source': source,
        'member_key': memberKey,
        if (payerId != null) 'payer_id': payerId,
      },
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

  Future<Map<String, dynamic>> updateFinancePayment(int id, String action, {String? notes}) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/finance/payments/$id',
      data: {
        'action': action,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return res.data ?? {};
  }

  Future<void> markNotificationsRead() async {
    await _api.dio.patch('/api/notifications/me/read');
  }

  Future<Map<String, dynamic>> phasesMe() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/phases/me');
    return res.data ?? {};
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

  Future<Map<String, dynamic>> chronicRoster({
    String? programKey,
    String? status,
    String? q,
  }) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/api/chronic/roster',
      queryParameters: {
        if (programKey != null && programKey.isNotEmpty) 'program_key': programKey,
        if (status != null && status.isNotEmpty) 'status': status,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateChronicProgram(int id, Map<String, dynamic> payload) async {
    final res = await _api.dio.patch<Map<String, dynamic>>('/api/chronic/$id', data: payload);
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

  Future<List<int>> vaultFileBytes(int id) async {
    final res = await _api.dio.get<List<int>>(
      '/api/vault/documents/$id/file',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? <int>[];
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

  Future<Map<String, dynamic>> adminNationalAnalytics() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/admin/analytics');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> networkCoverage() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/network/coverage');
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> nationalNearby({String? type, double? lat, double? lng}) async {
    final res = await _api.dio.get('/api/network/nearby', queryParameters: {
      if (type != null) 'type': type,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    final data = res.data;
    if (data is Map && data['results'] is List) {
      return (data['results'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> nationalOps() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/network/national');
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> auditLog() async {
    final res = await _api.dio.get<List<dynamic>>('/api/audit');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> riskAlerts({int? patientId}) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/api/risk-alerts',
      queryParameters: {if (patientId != null) 'patient_id': patientId},
    );
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> scanRiskAlerts({int? patientId}) async {
    await _api.dio.post('/api/risk-alerts/scan', data: {if (patientId != null) 'patient_id': patientId});
  }

  Future<Map<String, dynamic>> familyChart(int patientId) async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/family/$patientId/chart');
    return res.data ?? {};
  }

  Future<void> saveConsent(String type, {bool accepted = true}) async {
    await _api.dio.post('/api/consents/me', data: {'consent_type': type, 'accepted': accepted});
  }

  Future<List<Map<String, dynamic>>> myConsents() async {
    final res = await _api.dio.get<List<dynamic>>('/api/consents/me');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> myBilling() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/billing/me');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> membershipMe() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/membership/me');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> initializeMembership({
    required String tier,
    required String period,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/membership/initialize',
      data: {'tier': tier, 'period': period},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> activateMembership({
    required String tier,
    required String period,
    required String reference,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/membership/activate',
      data: {'tier': tier, 'period': period, 'reference': reference},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> myFollowups() async {
    final res = await _api.dio.get<List<dynamic>>('/api/followups/me');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> supportTickets() async {
    final res = await _api.dio.get<List<dynamic>>('/api/support/tickets');
    return (res.data ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> openSupportTicket(Map<String, dynamic> payload) async {
    final res = await _api.dio.post<Map<String, dynamic>>('/api/support/tickets', data: payload);
    return res.data ?? {};
  }

  Future<void> updateSupportTicket(int id, Map<String, dynamic> payload) async {
    await _api.dio.patch('/api/support/tickets/$id', data: payload);
  }

  Future<Map<String, dynamic>> hospitalDesk() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/hospital/desk');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateHospitalCapacity(Map<String, dynamic> payload) async {
    final res = await _api.dio.patch<Map<String, dynamic>>('/api/hospital/capacity', data: payload);
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> createHospitalOutbound(Map<String, dynamic> payload) async {
    final res =
        await _api.dio.post<Map<String, dynamic>>('/api/hospital/referrals/outbound', data: payload);
    return res.data ?? {};
  }
}
