class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final String? localImagePath;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.localImagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'localImagePath': localImagePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      text: map['text'] as String,
      localImagePath: map['localImagePath'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}