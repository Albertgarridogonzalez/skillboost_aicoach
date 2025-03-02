// chatgpt_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatGPTService {
  final String apiKey;
  ChatGPTService(this.apiKey);

  Future<String> getCorrections(String poseAnalysisJson) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    final body = jsonEncode({
      "model": "gpt-3.5-turbo",
      "messages": [
        {
          "role": "system",
          "content": "Eres un experto en biomecánica de deportes..."
        },
        {
          "role": "user",
          "content": "Analiza la siguiente data de poses y ángulos: $poseAnalysisJson"
        }
      ],
      "max_tokens": 200,
      "temperature": 0.8
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['choices'][0]['message']['content'];
      return text;
    } else {
      return "Error: ${response.body}";
    }
  }
}
