import 'package:flutter_test/flutter_test.dart';
import 'package:studentos/services/hugging_face_config.dart';

void main() {
  test('uses Hugging Face router chat completions endpoint', () {
    expect(
      HuggingFaceConfig.chatCompletionsUri.toString(),
      'https://router.huggingface.co/v1/chat/completions',
    );
  });

  test('keeps model id', () {
    expect(
      HuggingFaceConfig.modelId('Qwen/Qwen2.5-3B-Instruct'),
      'Qwen/Qwen2.5-3B-Instruct',
    );
  });

  test('normalizes Hugging Face model page URL', () {
    expect(
      HuggingFaceConfig.modelId(
        'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct',
      ),
      'Qwen/Qwen2.5-3B-Instruct',
    );
  });

  test('extracts model id from old api inference URL', () {
    expect(
      HuggingFaceConfig.modelId(
        'https://api-inference.huggingface.co/Qwen/Qwen2.5-3B-Instruct',
      ),
      'Qwen/Qwen2.5-3B-Instruct',
    );
  });
}
