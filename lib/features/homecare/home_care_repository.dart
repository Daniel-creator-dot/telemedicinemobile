import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import 'home_care_logic.dart';

class HomeCareFailure implements Exception {
  HomeCareFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class HomeCarePatientChoice {
  const HomeCarePatientChoice({
    required this.id,
    required this.name,
    this.phone,
  });

  final int id;
  final String name;
  final String? phone;

  factory HomeCarePatientChoice.fromJson(Map<String, dynamic> json) {
    return HomeCarePatientChoice(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      name: json['full_name']?.toString().trim().isNotEmpty == true
          ? json['full_name'].toString().trim()
          : 'Patient',
      phone: _text(json['phone_number']),
    );
  }
}

class HomeCareRequest {
  const HomeCareRequest({
    required this.id,
    required this.title,
    required this.status,
    required this.mine,
    required this.taken,
    this.location,
    this.contactPhone,
    this.note,
    this.claimedByLabel,
    this.claimedByName,
    this.claimedByAgency,
    this.createdAt,
    this.claimedAt,
    this.nearYou = false,
    this.patientId,
    this.patientName,
    this.referrerUserId,
    this.referrerName,
    this.referredByMe = false,
    this.postedByMe = false,
  });

  final int id;
  final String title;
  final String status;
  final bool mine;
  final bool taken;
  final String? location;
  final String? contactPhone;
  final String? note;
  final String? claimedByLabel;
  final String? claimedByName;
  final String? claimedByAgency;
  final String? createdAt;
  final String? claimedAt;
  final bool nearYou;
  final int? patientId;
  final String? patientName;
  final int? referrerUserId;
  final String? referrerName;
  final bool referredByMe;

  /// True when this viewer created the request. Status in the API stays `open`.
  final bool postedByMe;

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get canTake => isOpen && !mine && !taken;

  /// Agency name when the taker runs an agency, otherwise the person's name.
  String get claimerName {
    final agency = claimedByAgency?.trim() ?? '';
    if (agency.isNotEmpty) return agency;
    final label = claimedByLabel?.trim() ?? '';
    if (label.isNotEmpty) return label;
    return claimedByName?.trim() ?? '';
  }

  /// Copy used right after a successful post so the card can say Sent immediately.
  HomeCareRequest markedSent({bool referred = false}) {
    return HomeCareRequest(
      id: id,
      title: title,
      status: status,
      mine: mine,
      taken: taken,
      location: location,
      contactPhone: contactPhone,
      note: note,
      claimedByLabel: claimedByLabel,
      claimedByName: claimedByName,
      claimedByAgency: claimedByAgency,
      createdAt: createdAt,
      claimedAt: claimedAt,
      nearYou: nearYou,
      patientId: patientId,
      patientName: patientName,
      referrerUserId: referrerUserId,
      referrerName: referrerName,
      referredByMe: referred || referredByMe,
      postedByMe: true,
    );
  }

  /// Pill shown on the card.
  /// The creator sees Sent while the job is still open. Nurses keep Open so Take stays.
  /// Other caregivers see Taken with the taker's name once it is claimed.
  String pillLabel({required bool admin}) {
    if (isClosed) return 'Closed';
    if (isOpen) {
      final creator = admin ? postedByMe : referredByMe;
      return creator ? 'Sent' : 'Open';
    }
    if (mine && !admin) return 'You took this';
    if (!admin) {
      final name = claimerName;
      return name.isEmpty ? 'Taken' : 'Taken · $name';
    }
    return 'Taken';
  }

  /// Extra line so the taker's name, and for admin the time, stay with the pill.
  String? takenDetail({required bool admin}) {
    if (isOpen) return null;
    final name = claimerName;
    final when = formatHomeCareWhen(claimedAt);
    if (mine && !admin) return name.isEmpty ? null : name;
    if (admin) {
      if (name.isEmpty && when == null) return null;
      if (name.isEmpty) return 'Taken · $when';
      if (when == null) return 'Taken by $name';
      return 'Taken by $name · $when';
    }
    if (isClosed && name.isNotEmpty) return 'Taken · $name';
    return null;
  }

  String get statusLabel => pillLabel(admin: false);

  String get claimerLine {
    if (mine) {
      final name = claimerName;
      return name.isEmpty ? 'You took this' : 'You took this · $name';
    }
    final name = claimerName;
    if (name.isEmpty) return 'Taken';
    return 'Taken · $name';
  }

  factory HomeCareRequest.fromJson(Map<String, dynamic> json) {
    return HomeCareRequest(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      title: json['title']?.toString() ?? 'Home care',
      status: json['status']?.toString() ?? 'open',
      mine: json['mine'] == true,
      taken: json['taken'] == true || json['status']?.toString() == 'claimed',
      location: _text(json['location']),
      contactPhone: _text(json['contact_phone']),
      note: _text(json['note']),
      claimedByLabel: _text(json['claimed_by_label']),
      claimedByName: _text(json['claimed_by_name']),
      claimedByAgency: _text(json['claimed_by_agency']),
      createdAt: _text(json['created_at']),
      claimedAt: _text(json['claimed_at']),
      nearYou: json['near_you'] == true,
      patientId: _readId(json['patient_id']),
      patientName: _text(json['patient_name']),
      referrerUserId: _readId(json['referrer_user_id']),
      referrerName: _text(json['referrer_name']),
      referredByMe: json['referred_by_me'] == true,
      postedByMe: json['posted_by_me'] == true,
    );
  }
}

int? _readId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

/// Open requests first, then taken, then closed. Nearby open jobs lead their group.
List<HomeCareRequest> sortHomeCareRequests(List<HomeCareRequest> items) {
  final copy = [...items];
  copy.sort((a, b) {
    final byStatus = homeCareStatusRank(
      a.status,
    ).compareTo(homeCareStatusRank(b.status));
    if (byStatus != 0) return byStatus;
    if (a.nearYou != b.nearYou) return a.nearYou ? -1 : 1;
    final byTime = (b.createdAt ?? '').compareTo(a.createdAt ?? '');
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
  });
  return copy;
}

/// Puts a request that was just posted at the top of the open group.
List<HomeCareRequest> placeNewestHomeCareRequest(
  List<HomeCareRequest> items,
  HomeCareRequest created,
) {
  final open = <HomeCareRequest>[created];
  final later = <HomeCareRequest>[];
  for (final row in items) {
    if (row.id == created.id) continue;
    if (row.isOpen) {
      open.add(row);
    } else {
      later.add(row);
    }
  }
  return [...open, ...later];
}

/// Keeps a request the viewer just posted at the top, labeled Sent, while it is open.
List<HomeCareRequest> pinJustPostedHomeCareRequest(
  List<HomeCareRequest> items,
  HomeCareRequest? justPosted, {
  bool referred = false,
  int? onlyPatientId,
}) {
  if (justPosted == null) return items;
  if (onlyPatientId != null && justPosted.patientId != onlyPatientId) {
    return items;
  }
  HomeCareRequest? found;
  for (final row in items) {
    if (row.id == justPosted.id) {
      found = row;
      break;
    }
  }
  if (found != null && !found.isOpen) return items;
  final source = found ?? justPosted;
  return placeNewestHomeCareRequest(
    items,
    source.markedSent(
      referred: referred || source.referredByMe || justPosted.referredByMe,
    ),
  );
}

class HomeCareMessage {
  const HomeCareMessage({
    required this.id,
    required this.senderName,
    required this.senderRole,
    required this.body,
    this.senderId,
    this.createdAt,
  });

  final int id;
  final int? senderId;
  final String senderName;
  final String senderRole;
  final String body;
  final String? createdAt;

  factory HomeCareMessage.fromJson(Map<String, dynamic> json) {
    final rawId = json['sender_id'];
    return HomeCareMessage(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      senderId: rawId is int ? rawId : int.tryParse('${rawId ?? ''}'),
      senderName: _text(json['sender_name']) ?? 'Healynks',
      senderRole: _text(json['sender_role']) ?? 'nurse',
      body: json['body']?.toString() ?? '',
      createdAt: _text(json['created_at']),
    );
  }
}

String? _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'null') return null;
  return text;
}

class HomeCareRepository {
  HomeCareRepository(this._api);

  final ApiClient _api;

  Future<List<HomeCareRequest>> list({int? patientId}) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/homecare/requests',
        queryParameters: patientId == null || patientId <= 0
            ? null
            : {'patient_id': patientId},
      );
      final raw = res.data?['requests'];
      if (raw is! List) return const [];
      return sortHomeCareRequests(
        raw
            .whereType<Map>()
            .map(
              (row) => HomeCareRequest.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(),
      );
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not load home care requests.'),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<List<HomeCarePatientChoice>> searchPatients(String query) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/homecare/patients',
        queryParameters: {'q': query.trim()},
      );
      final raw = res.data?['patients'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) => HomeCarePatientChoice.fromJson(Map<String, dynamic>.from(row)))
          .where((patient) => patient.id > 0)
          .toList();
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not search patients.'),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<HomeCareRequest> create({
    required String title,
    required String location,
    required String contactPhone,
    String? note,
    int? patientId,
  }) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/homecare/requests',
        data: {
          'title': title.trim(),
          'location': location.trim(),
          'contact_phone': contactPhone.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (patientId != null && patientId > 0) 'patient_id': patientId,
        },
      );
      final data = res.data;
      if (data == null) {
        throw HomeCareFailure('Could not post this home care request.');
      }
      return HomeCareRequest.fromJson(data);
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not post this home care request.'),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<HomeCareRequest> claim(int id) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/homecare/requests/$id/claim',
      );
      final data = res.data;
      if (data == null) throw HomeCareFailure('Could not take this request.');
      return HomeCareRequest.fromJson(data);
    } on DioException catch (err) {
      final status = err.response?.statusCode;
      if (status == 409) {
        final server = ApiClient.messageFromDio(
          err,
          'This job has been taken.',
        );
        final closed = server.toLowerCase().contains('closed');
        throw HomeCareFailure(
          closed ? server : 'This job has been taken.',
          statusCode: 409,
        );
      }
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not take this request.'),
        statusCode: status,
      );
    }
  }

  Future<List<HomeCareMessage>> messages(int requestId) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/homecare/requests/$requestId/messages',
      );
      final raw = res.data?['messages'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (row) => HomeCareMessage.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not load messages. Try again.'),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<HomeCareMessage> sendMessage(int requestId, String body) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/homecare/requests/$requestId/messages',
        data: {'body': body.trim()},
      );
      final data = res.data;
      if (data == null)
        throw HomeCareFailure('Could not send that message. Try again.');
      return HomeCareMessage.fromJson(data);
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(
          err,
          'Could not send that message. Try again.',
        ),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<HomeCareRequest> addNote(int id, String note) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/homecare/requests/$id/note',
        data: {'note': note.trim()},
      );
      final data = res.data;
      if (data == null) throw HomeCareFailure('Could not add that note.');
      return HomeCareRequest.fromJson(data);
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not add that note.'),
        statusCode: err.response?.statusCode,
      );
    }
  }

  Future<HomeCareRequest> close(int id) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/homecare/requests/$id/close',
      );
      final data = res.data;
      if (data == null) throw HomeCareFailure('Could not update this request.');
      return HomeCareRequest.fromJson(data);
    } on DioException catch (err) {
      throw HomeCareFailure(
        ApiClient.messageFromDio(err, 'Could not update this request.'),
        statusCode: err.response?.statusCode,
      );
    }
  }
}
