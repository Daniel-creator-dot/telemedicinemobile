class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.appointmentId,
    required this.senderId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int appointmentId;
  final int senderId;
  final String senderRole;
  final String senderName;
  final String body;
  final String createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      appointmentId: json['appointment_id'] as int? ?? 0,
      senderId: json['sender_id'] as int? ?? 0,
      senderRole: json['sender_role']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'User',
      body: json['body']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}
