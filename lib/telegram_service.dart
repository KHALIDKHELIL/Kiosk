import 'package:http/http.dart' as http;
import 'secrets.dart'; 

class TelegramNotifier {
  static Future<void> sendNotification(String message) async {
    if (Secrets.telegramBotToken.isEmpty || Secrets.telegramChatId.isEmpty) return;
    
    final url = Uri.parse('https://api.telegram.org/bot${Secrets.telegramBotToken}/sendMessage');
    
    try {
      await http.post(
        url,
        body: {
          'chat_id': Secrets.telegramChatId,
          'text': message,
          'parse_mode': 'Markdown',
        },
      );
    } catch (e) {
      // Fails silently so the worker isn't interrupted if the internet drops briefly
      print('Telegram Notification Failed: $e');
    }
  }
}