// Chat model for the Ada (M.AI) section.
enum AiRole { user, assistant }

class AiMessage {
  final AiRole role;
  final String text;
  final bool streaming;

  const AiMessage(this.role, this.text, {this.streaming = false});

  AiMessage copyWith({String? text, bool? streaming}) => AiMessage(
    role,
    text ?? this.text,
    streaming: streaming ?? this.streaming,
  );
}
