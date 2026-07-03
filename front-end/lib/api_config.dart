import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// ══════════════════════════════════════════════════════════════
///  API Configuration & Helper Functions
/// ══════════════════════════════════════════════════════════════
class ApiConfig {
  // ── غيّري العنوان حسب بيئة التشغيل ───────────────────────────
  // Android Emulator  → http://10.0.2.2:7860
  // Physical device   → http://[YOUR_PC_IP]:7860
  // Hugging Face      → https://[space-name].hf.space
  // Windows/Desktop   → http://127.0.0.1:7860
  static const String baseUrl = 'http://127.0.0.1:7860';

  /// مهلة الاتصال والاستجابة
  static const Duration timeout = Duration(seconds: 60);
}

/// ══════════════════════════════════════════════════════════════
///  API Response Models
/// ══════════════════════════════════════════════════════════════

class SignPrediction {
  final String word;
  final String confidence;

  SignPrediction({required this.word, required this.confidence});

  factory SignPrediction.fromJson(Map<String, dynamic> json) {
    return SignPrediction(
      word: json['word'] ?? '',
      confidence: json['confidence'] ?? '0%',
    );
  }
}

class SignToTextResult {
  final bool success;
  final String predictedWord;
  final String confidence;
  final List<SignPrediction> top3;
  final int framesProcessed;
  final String? error;

  SignToTextResult({
    required this.success,
    this.predictedWord = '',
    this.confidence = '',
    this.top3 = const [],
    this.framesProcessed = 0,
    this.error,
  });
}

/// ══════════════════════════════════════════════════════════════
///  API Service (with debug logging)
/// ══════════════════════════════════════════════════════════════
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  /// ── POST /sign-to-text ───────────────────────────────────────
  Future<SignToTextResult> signToText(File videoFile) async {
    try {
      print('[API] signToText: Sending ${videoFile.path}');
      final uri = Uri.parse('${ApiConfig.baseUrl}/sign-to-text');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath('file', videoFile.path),
      );

      final streamedResponse = await request.send().timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamedResponse);

      print('[API] signToText: Status ${response.statusCode}');
      print('[API] signToText: Body ${response.body.substring(0, response.body.length.clamp(0, 300))}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          final top3List = (data['top3_predictions'] as List?)
                  ?.map((e) => SignPrediction.fromJson(e))
                  .toList() ??
              [];

          return SignToTextResult(
            success: true,
            predictedWord: data['predicted_word'] ?? '',
            confidence: data['confidence'] ?? '',
            top3: top3List,
            framesProcessed: data['frames_processed'] ?? 0,
          );
        } else {
          return SignToTextResult(
            success: false,
            error: data['message'] ?? 'Unknown error',
          );
        }
      } else {
        return SignToTextResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e, stack) {
      print('[API] signToText ERROR: $e');
      print('[API] signToText STACK: $stack');
      return SignToTextResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// ── POST /text-to-sign ───────────────────────────────────────
  Future<Uint8List?> textToSign(String word) async {
    try {
      final encoded = Uri.encodeComponent(word);
      final url = '${ApiConfig.baseUrl}/text-to-sign?word=$encoded';
      print('[API] textToSign: POST $url');

      final uri = Uri.parse(url);
      final response = await http.post(uri).timeout(ApiConfig.timeout);

      print('[API] textToSign: Status ${response.statusCode}');
      print('[API] textToSign: Content-Type ${response.headers['content-type']}');
      print('[API] textToSign: Body length ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('image/gif')) {
          return response.bodyBytes;
        } else {
          // الـ API رجّع JSON بدل GIF (يعني فيه خطأ)
          print('[API] textToSign: Expected GIF but got: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
          return null;
        }
      }
      print('[API] textToSign: Non-200 response: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
      return null;
    } catch (e, stack) {
      print('[API] textToSign ERROR: $e');
      print('[API] textToSign STACK: $stack');
      return null;
    }
  }

  /// ── POST /text-to-sign-points ────────────────────────────────
  /// يبعت كلمة ويرجع قائمة النقاط + زوايا العظام المحسوبة مسبقاً
  Future<Map<String, dynamic>?> textToSignPoints(String word) async {
    try {
      final encoded = Uri.encodeComponent(word);
      final url = '${ApiConfig.baseUrl}/text-to-sign-points?word=$encoded';
      print('[API] textToSignPoints: POST $url');

      final uri = Uri.parse(url);
      final response = await http.post(uri).timeout(ApiConfig.timeout);

      print('[API] textToSignPoints: Status ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
           // Parse rotations (pre-computed bone angles from backend)
           final List<dynamic>? rawRotations = data['rotations'];
           if (rawRotations != null && rawRotations.isNotEmpty) {
             return {
               'rotations': rawRotations,
             };
           }
           
           // Fallback to raw points if no rotations
           final List<dynamic> rawPoints = data['points'];
           List<List<double>> frames = [];
           for (var frame in rawPoints) {
             frames.add((frame as List).map((e) => (e as num).toDouble()).toList());
           }
           return {
             'points': frames,
           };
        }
      }
      return null;
    } catch (e, stack) {
      print('[API] textToSignPoints ERROR: $e');
      print('[API] textToSignPoints STACK: $stack');
      return null;
    }
  }

  /// ── GET /available-signs ─────────────────────────────────────
  Future<List<String>> getAvailableSigns() async {
    try {
      final url = '${ApiConfig.baseUrl}/available-signs';
      print('[API] getAvailableSigns: GET $url');

      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(ApiConfig.timeout);

      print('[API] getAvailableSigns: Status ${response.statusCode}');
      print('[API] getAvailableSigns: Body ${response.body.substring(0, response.body.length.clamp(0, 500))}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('[API] getAvailableSigns: Parsed JSON, status=${data['status']}, count=${data['count']}');

        if (data['status'] == 'success') {
          final signs = List<String>.from(data['signs'] ?? []);
          print('[API] getAvailableSigns: Loaded ${signs.length} signs');
          return signs;
        } else {
          print('[API] getAvailableSigns: API returned non-success status');
        }
      }
      return [];
    } catch (e, stack) {
      print('[API] getAvailableSigns ERROR: $e');
      print('[API] getAvailableSigns STACK: $stack');
      return [];
    }
  }

  /// ── GET / (Health Check) ─────────────────────────────────────
  Future<bool> isServerOnline() async {
    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final response =
          await http.get(uri).timeout(const Duration(seconds: 5));
      print('[API] healthCheck: Status ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('[API] healthCheck ERROR: $e');
      return false;
    }
  }
}
