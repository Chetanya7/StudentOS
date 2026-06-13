enum ChatMessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  final ChatMessageRole role;
  final String text;
}
