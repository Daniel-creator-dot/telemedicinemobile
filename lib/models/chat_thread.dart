class ChatThread {
  const ChatThread({
    required this.id,
    required this.patientUserId,
    required this.doctorUserId,
    required this.otherName,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final int id;
  final int patientUserId;
  final int doctorUserId;
  final String otherName;
  final String? lastMessage;
  final String? lastMessageAt;
  final int unreadCount;

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      id: json['id'] as int? ?? 0,
      patientUserId: json['patient_user_id'] as int? ?? 0,
      doctorUserId: json['doctor_user_id'] as int? ?? 0,
      otherName: json['other_name']?.toString() ?? 'Care team',
      lastMessage: json['last_message']?.toString(),
      lastMessageAt: json['last_message_at']?.toString(),
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.body,
    required this.isMine,
    this.createdAt,
  });

  final int id;
  final int threadId;
  final int senderUserId;
  final String body;
  final bool isMine;
  final String? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId) {
    final senderId = json['sender_user_id'] as int? ?? 0;
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      threadId: json['thread_id'] as int? ?? 0,
      senderUserId: senderId,
      body: json['body']?.toString() ?? '',
      isMine: senderId == currentUserId,
      createdAt: json['created_at']?.toString(),
    );
  }
}
