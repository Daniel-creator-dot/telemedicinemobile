import '../../core/api_client.dart';
import '../../models/chat_thread.dart';

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<List<ChatThread>> getThreads() async {
    final res = await _api.dio.get<List<dynamic>>('/api/chat/threads');
    if (res.data == null) return [];
    return res.data!
        .map((json) => ChatThread.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ChatThread> openThread({required int doctorUserId}) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/chat/threads',
      data: {'doctorUserId': doctorUserId},
    );
    if (res.data == null) throw Exception('Could not open chat thread');
    return ChatThread.fromJson(res.data!);
  }

  Future<List<ChatMessage>> getMessages(int threadId, int currentUserId) async {
    final res = await _api.dio.get<List<dynamic>>('/api/chat/threads/$threadId/messages');
    if (res.data == null) return [];
    return res.data!
        .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>, currentUserId))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required int threadId,
    required String body,
    required int currentUserId,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/chat/threads/$threadId/messages',
      data: {'body': body.trim()},
    );
    if (res.data == null) throw Exception('Message not sent');
    return ChatMessage.fromJson(res.data!, currentUserId);
  }
}
