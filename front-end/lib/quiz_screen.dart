import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:confetti/confetti.dart';
import 'package:http/http.dart' as http;
import 'theme.dart';
import 'bubble_screen.dart';
import 'api_config.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  final _api = ApiService();
  final _webviewController = WebviewController();
  bool _isWebviewInitialized = false;

  int _currentQuestionIndex = 0;
  int _score = 0;
  static const int _totalQuestions = 10;
  
  // Question state
  String? _correctWord;
  List<String> _choices = [];
  Map<String, dynamic>? _currentQuestionData;
  bool _isLoadingQuestion = true;
  String? _error;
  bool _isPlayingAnimation = false;

  // Timer state
  int _timeLeft = 15;
  Timer? _timer;

  // Selection state
  String? _selectedChoice;
  bool? _isCorrectAnswer;

  // Animations & FX
  late ConfettiController _confettiCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 2));
    
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    _initWebview().then((_) {
      _fetchNextQuestion();
    });
  }

  Future<void> _initWebview() async {
    try {
      await _webviewController.initialize();

      _webviewController.webMessage.listen((msg) {
        final msgStr = msg.toString();
        if (msgStr == 'ANIMATION_DONE' && mounted) {
          setState(() => _isPlayingAnimation = false);
        }
      });

      _webviewController.loadingState.listen((state) async {
        if (state == LoadingState.navigationCompleted) {
          await _webviewController.executeScript('''
            (function() {
              var origLog = console.log;
              console.log = function(message) {
                if(typeof message === 'string' && (message.startsWith('WORD_START:') || message.startsWith('WORD_END:') || message === 'ANIMATION_DONE')) {
                  window.chrome.webview.postMessage(message);
                }
                origLog.apply(console, arguments);
              };
            })();
          ''');
        }
      });

      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = '${ApiConfig.baseUrl}/static/index.html?v=$ts';
      await _webviewController.loadUrl(url);

      if (mounted) {
        setState(() => _isWebviewInitialized = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل تحميل الأفاتار: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timeLeft = 15);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    _timer?.cancel();
    if (_selectedChoice == null) {
      _handleAnswerSelection("TIMEOUT_WRONG_ANSWER");
    }
  }

  Future<void> _fetchNextQuestion() async {
    setState(() {
      _isLoadingQuestion = true;
      _error = null;
      _selectedChoice = null;
      _isCorrectAnswer = null;
    });

    try {
      // Direct call to new quiz endpoint via standard http using ApiConfig.baseUrl
      // Since we don't have it in ApiService yet, we'll do a quick http call here.
      // But it's better to add it to api_config.dart. Let's do it directly for simplicity.
      final url = Uri.parse('${ApiConfig.baseUrl}/api/quiz/question');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'success') {
          if (!mounted) return;
          setState(() {
            _currentQuestionData = data;
            _correctWord = data['correct_word'];
            _choices = List<String>.from(data['choices']);
            _isLoadingQuestion = false;
          });
          _playSign();
          _startTimer();
        } else {
          throw Exception(data['message']);
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingQuestion = false;
        _error = 'حدث خطأ في جلب السؤال: $e';
      });
    }
  }

  Future<void> _playSign() async {
    if (_currentQuestionData == null || !_isWebviewInitialized) return;
    
    final rotations = _currentQuestionData!['rotations'] as List<dynamic>?;
    if (rotations != null && rotations.isNotEmpty) {
      setState(() => _isPlayingAnimation = true);
      final allFramesJson = json.encode(rotations);
      final escaped = allFramesJson.replaceAll("'", "\\'");
      try {
        await _webviewController.executeScript("playAnimation('$escaped');");
      } catch (e) {
        print('[QuizAnimation] Error: $e');
      }
    }
  }

  void _handleAnswerSelection(String choice) async {
    if (_selectedChoice != null) return; // Already answered
    _timer?.cancel();

    setState(() {
      _selectedChoice = choice;
      _isCorrectAnswer = (choice == _correctWord);
    });

    if (_isCorrectAnswer!) {
      _score += 100 + (_timeLeft * 10); // Bonus for time
      _confettiCtrl.play();
    } else {
      _shakeCtrl.forward(from: 0);
    }

    // Wait a bit to show feedback, then next question or finish
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;

    if (_currentQuestionIndex + 1 < _totalQuestions) {
      setState(() => _currentQuestionIndex++);
      _fetchNextQuestion();
    } else {
      _showSuccessOverlay();
    }
  }

  void _showSuccessOverlay() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.background.withOpacity(0.95),
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) {
        final pct = _score / (100 * _totalQuestions + 150 * _totalQuestions) * 100;
        final grade = _score >= 2000 ? "A+" : _score >= 1500 ? "A" : _score >= 1000 ? "B" : "C";
        final gradeColor = _score >= 1500 ? AppColors.emerald : AppColors.primary;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConfettiWidget(
                  confettiController: _confettiCtrl,
                  blastDirectionality: BlastDirectionality.explosive,
                  colors: const [AppColors.neonCyan, AppColors.emerald, AppColors.primary],
                ),
                Text(
                  "انتهى الاختبار!",
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 30),
                // Custom Ring Chart simulation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: CircularProgressIndicator(
                        value: _score / 2500, // Roughly max possible score
                        strokeWidth: 12,
                        color: gradeColor,
                        backgroundColor: gradeColor.withOpacity(0.2),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grade,
                          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: gradeColor),
                        ),
                        Text(
                          "$_score نقطة",
                          textDirection: TextDirection.rtl,
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                        Navigator.pop(context); // Close Quiz screen
                      },
                      icon: const Icon(Icons.exit_to_app, color: Colors.white),
                      label: const Text("خروج", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _currentQuestionIndex = 0;
                          _score = 0;
                        });
                        _fetchNextQuestion();
                      },
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      label: const Text("حاول مجدداً", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
    _confettiCtrl.play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confettiCtrl.dispose();
    _shakeCtrl.dispose();
    _webviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoadingQuestion
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _error != null
                          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                          : Column(
                              children: [
                                _buildAvatarArea(),
                                const Spacer(),
                                _buildChoicesArea(),
                                const SizedBox(height: 20),
                              ],
                            ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiCtrl,
                blastDirectionality: BlastDirectionality.explosive,
                colors: const [AppColors.neonCyan, AppColors.emerald, AppColors.primary],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Score Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text("$_score", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              
              // Title
              Text(
                "السؤال ${_currentQuestionIndex + 1} من $_totalQuestions",
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              
              // Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress Bar & Timer
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (_currentQuestionIndex) / _totalQuestions,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    color: const Color(0xFFA855F7), // Vibrant Purple
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _timeLeft <= 5 ? Colors.red.withOpacity(0.2) : AppColors.neonCyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _timeLeft <= 5 ? Colors.red : AppColors.neonCyan.withOpacity(0.3)),
                ),
                child: Text(
                  "00:${_timeLeft.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    color: _timeLeft <= 5 ? Colors.red : AppColors.neonCyan,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace'
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarArea() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 350,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: 5,
          )
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _isWebviewInitialized
                ? Webview(_webviewController)
                : const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ),
          // Replay Button
          Positioned(
            bottom: 16,
            right: 16,
            child: SparkleButton(
              onTap: _isPlayingAnimation ? null : _playSign,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isPlayingAnimation ? Icons.hourglass_bottom_rounded : Icons.replay_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text("أعد الإشارة", textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChoicesArea() {
    final prefixes = ['أ', 'ب', 'ج', 'د'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildChoiceBtn(_choices[0], prefixes[0])),
              const SizedBox(width: 16),
              Expanded(child: _buildChoiceBtn(_choices[1], prefixes[1])),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildChoiceBtn(_choices[2], prefixes[2])),
              const SizedBox(width: 16),
              Expanded(child: _buildChoiceBtn(_choices[3], prefixes[3])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceBtn(String choice, String prefix) {
    bool isSelected = _selectedChoice == choice;
    bool isCorrect = choice == _correctWord;
    
    Color bgColor = Colors.white.withOpacity(0.05);
    Color borderColor = Colors.white.withOpacity(0.1);
    
    if (_selectedChoice != null) {
      if (isCorrect) {
        bgColor = AppColors.emerald.withOpacity(0.2);
        borderColor = AppColors.emerald;
      } else if (isSelected) {
        bgColor = Colors.red.withOpacity(0.2);
        borderColor = Colors.red;
      } else {
        bgColor = Colors.white.withOpacity(0.02);
      }
    }

    Widget button = GestureDetector(
      onTap: () => _handleAnswerSelection(choice),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: isSelected || isCorrect ? 2 : 1),
          boxShadow: [
            if (isSelected || (isCorrect && _selectedChoice != null))
              BoxShadow(
                color: borderColor.withOpacity(0.4),
                blurRadius: 20,
              )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                choice,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  prefix,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Apply shake animation if this was the selected wrong answer
    if (_selectedChoice != null && isSelected && !isCorrect) {
      return AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          final sineValue = (12 * _shakeAnim.value * (1 - _shakeCtrl.value) * (1 - _shakeCtrl.value) * 1.5).roundToDouble();
          return Transform.translate(
            offset: Offset(sineValue % 2 == 0 ? 5 : -5, 0),
            child: child,
          );
        },
        child: button,
      );
    }
    
    // Apply scale pop if this is the correct answer
    if (_selectedChoice != null && isCorrect) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.05),
        duration: const Duration(milliseconds: 300),
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: button,
      );
    }

    return button;
  }
}
