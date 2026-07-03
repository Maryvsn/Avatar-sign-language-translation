import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'api_config.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isFront = false;
  bool _isRecording = false;
  bool _isSending = false;
  String? _errorMsg;

  // Prediction
  String _prediction = "";
  String _confidence = "";
  double _confidenceValue = 0.0;
  List<SignPrediction> _top3 = [];
  int _framesProcessed = 0;
  bool _hasResult = false;

  // Sentence accumulation
  List<String> _generatedSentence = [];
  final ScrollController _sentenceScrollCtrl = ScrollController();

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // File import
  File? _importedFile;
  bool _isProcessingFile = false;

  final _api = ApiService();

  // Animation controllers
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  late AnimationController _ttsWaveCtrl;
  late AnimationController _confidenceAnimCtrl;
  late Animation<double> _confidenceAnim;
  double _prevConfidence = 0.0;

  // Glassmorphism constants
  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFFA855F7);
  static const _neonCyan = Color(0xFF06B6D4);
  static const _emerald = Color(0xFF10B981);
  static const _bg = Color(0xFF0B0F19);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _initTts();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _ttsWaveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    _confidenceAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _confidenceAnim = Tween<double>(begin: 0, end: 0).animate(
        CurvedAnimation(parent: _confidenceAnimCtrl, curve: Curves.easeOutCubic));
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("ar-SA");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    _ttsWaveCtrl.dispose();
    _confidenceAnimCtrl.dispose();
    _sentenceScrollCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _isInitialized = false;
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(useFront: _isFront);
    }
  }

  Future<void> _initCamera({bool useFront = false}) async {
    setState(() {
      _isInitialized = false;
      _errorMsg = null;
    });

    try {
      print('[Camera] Fetching available cameras...');
      _cameras = await availableCameras();
      print('[Camera] Found ${_cameras.length} cameras:');
      for (int i = 0; i < _cameras.length; i++) {
        print('[Camera]   [$i] ${_cameras[i].name} - ${_cameras[i].lensDirection}');
      }

      if (_cameras.isEmpty) {
        print('[Camera] ERROR: No cameras found!');
        setState(() => _errorMsg = "No cameras found on this device.\n\nOn Windows, make sure your webcam is connected and not in use by another app.");
        return;
      }

      CameraDescription selected;
      if (useFront && _cameras.length > 1) {
        selected = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        selected = _cameras.first;
      }

      print('[Camera] Selected: ${selected.name} (${selected.lensDirection})');

      await _controller?.dispose();

      _controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );

      print('[Camera] Initializing controller...');
      await _controller!.initialize();
      print('[Camera] ✅ Camera initialized successfully!');
      print('[Camera] Preview size: ${_controller!.value.previewSize}');

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _isFront = useFront;
      });
    } on CameraException catch (e) {
      print('[Camera] CameraException: ${e.code} - ${e.description}');
      if (!mounted) return;
      setState(() => _errorMsg = "Camera Error [${e.code}]:\n${e.description}");
    } catch (e, stack) {
      print('[Camera] ERROR: $e');
      print('[Camera] STACK: $stack');
      if (!mounted) return;
      setState(() => _errorMsg = "Camera error: $e");
    }
  }

  void _toggleCamera() => _initCamera(useFront: !_isFront);

  // ── Recording ──────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('[Camera] Cannot start recording: controller not ready');
      return;
    }
    if (_isRecording) return;

    try {
      print('[Camera] Starting video recording...');
      await _controller!.startVideoRecording();
      print('[Camera] ✅ Recording started!');
      setState(() {
        _isRecording = true;
        _hasResult = false;
        _prediction = "";
        _confidence = "";
        _confidenceValue = 0.0;
        _top3 = [];
        _errorMsg = null;
      });
      _pulseCtrl.repeat(reverse: true);
    } on CameraException catch (e) {
      print('[Camera] CameraException during recording: ${e.code} - ${e.description}');
      setState(() => _errorMsg = "Recording error [${e.code}]: ${e.description}");
    } catch (e, stack) {
      print('[Camera] Recording error: $e');
      print('[Camera] Stack: $stack');
      setState(() => _errorMsg = "Recording error: $e");
    }
  }

  Future<void> _stopAndSend() async {
    if (_controller == null || !_isRecording) return;

    try {
      print('[Camera] Stopping recording...');
      final XFile videoFile = await _controller!.stopVideoRecording();
      print('[Camera] ✅ Recording stopped. File: ${videoFile.path}');
      _pulseCtrl.stop();
      _pulseCtrl.reset();

      final file = File(videoFile.path);
      final fileSize = await file.length();
      print('[Camera] Video file size: ${(fileSize / 1024).toStringAsFixed(1)} KB');

      setState(() {
        _isRecording = false;
        _isSending = true;
        _prediction = "";
        _confidence = "";
      });

      print('[Camera] Sending video to API...');
      final result = await _api.signToText(file);
      print('[Camera] API response: success=${result.success}, word=${result.predictedWord}');

      try { await file.delete(); } catch (_) {}

      if (!mounted) return;

      setState(() {
        _isSending = false;
        _hasResult = true;
        if (result.success) {
          _prediction = result.predictedWord;
          _confidence = result.confidence;
          _top3 = result.top3;
          _framesProcessed = result.framesProcessed;

          // Parse confidence value for the circular indicator
          final confStr = result.confidence.replaceAll('%', '').trim();
          final confVal = double.tryParse(confStr) ?? 0;
          _prevConfidence = _confidenceAnim.value;
          _confidenceValue = confVal / 100.0;
          _confidenceAnim = Tween<double>(
            begin: _prevConfidence,
            end: _confidenceValue,
          ).animate(CurvedAnimation(
              parent: _confidenceAnimCtrl, curve: Curves.easeOutCubic));
          _confidenceAnimCtrl.forward(from: 0);

          // Accumulate the word into the sentence
          if (result.predictedWord.isNotEmpty && confVal > 50) {
            _generatedSentence.add(result.predictedWord);
            // Scroll to the end after build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_sentenceScrollCtrl.hasClients) {
                _sentenceScrollCtrl.animateTo(
                  _sentenceScrollCtrl.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        } else {
          _prediction = "Error";
          _confidence = "";
          _errorMsg = result.error;
        }
      });
    } on CameraException catch (e) {
      print('[Camera] CameraException during stop: ${e.code} - ${e.description}');
      setState(() {
        _isRecording = false;
        _isSending = false;
        _errorMsg = "Camera Error [${e.code}]: ${e.description}";
      });
    } catch (e, stack) {
      print('[Camera] Stop/Send error: $e');
      print('[Camera] Stack: $stack');
      setState(() {
        _isRecording = false;
        _isSending = false;
        _errorMsg = "Error: $e";
      });
    }
  }

  void _clearAll() {
    setState(() {
      _generatedSentence.clear();
      _prediction = "";
      _confidence = "";
      _confidenceValue = 0.0;
      _hasResult = false;
      _top3 = [];
      _errorMsg = null;
    });
  }

  void _deleteLastWord() {
    if (_generatedSentence.isEmpty) return;
    setState(() {
      _generatedSentence.removeLast();
    });
  }

  Future<void> _speakSentence() async {
    if (_generatedSentence.isEmpty) return;
    final text = _generatedSentence.join(' ');
    setState(() => _isSpeaking = true);
    await _tts.speak(text);
  }

  // ── Pick & Send File ───────────────────────────────────────
  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'avi', 'mov', 'gif', 'webm', 'mkv'],
        dialogTitle: 'اختر فيديو أو GIF',
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      setState(() {
        _importedFile = file;
        _isProcessingFile = true;
        _hasResult = false;
        _prediction = "";
        _confidence = "";
        _top3 = [];
        _errorMsg = null;
      });

      print('[Import] Sending file: $path');
      final apiResult = await _api.signToText(file);
      print('[Import] API response: success=${apiResult.success}, word=${apiResult.predictedWord}');

      if (!mounted) return;

      setState(() {
        _isProcessingFile = false;
        _hasResult = true;
        if (apiResult.success) {
          _prediction = apiResult.predictedWord;
          _confidence = apiResult.confidence;
          _top3 = apiResult.top3;
          _framesProcessed = apiResult.framesProcessed;

          final confStr = apiResult.confidence.replaceAll('%', '').trim();
          final confVal = double.tryParse(confStr) ?? 0;
          _prevConfidence = _confidenceAnim.value;
          _confidenceValue = confVal / 100.0;
          _confidenceAnim = Tween<double>(
            begin: _prevConfidence,
            end: _confidenceValue,
          ).animate(CurvedAnimation(
              parent: _confidenceAnimCtrl, curve: Curves.easeOutCubic));
          _confidenceAnimCtrl.forward(from: 0);

          if (apiResult.predictedWord.isNotEmpty && confVal > 50) {
            _generatedSentence.add(apiResult.predictedWord);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_sentenceScrollCtrl.hasClients) {
                _sentenceScrollCtrl.animateTo(
                  _sentenceScrollCtrl.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        } else {
          _prediction = "Error";
          _confidence = "";
          _errorMsg = apiResult.error;
        }
      });
    } catch (e, stack) {
      print('[Import] Error: $e');
      print('[Import] Stack: $stack');
      if (!mounted) return;
      setState(() {
        _isProcessingFile = false;
        _errorMsg = "Error processing file: $e";
      });
    }
  }

  void _clearImportedFile() {
    setState(() {
      _importedFile = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────
            _buildAppBar(),

            // ── Main content ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ══ Camera Feed ══════════════════════════════════
                    _buildCameraFeed(),

                    const SizedBox(height: 14),

                    // ══ Record Button ════════════════════════════════
                    _buildRecordButton(),

                    const SizedBox(height: 14),

                    // ══ Import Video/GIF ═════════════════════════════
                    _buildImportSection(),

                    const SizedBox(height: 16),

                    // ══ Real-Time Translation Console ════════════════
                    _buildTranslationConsole(),

                    const SizedBox(height: 14),

                    // ══ Generated Sentence Row ═══════════════════════
                    _buildSentenceRow(),

                    const SizedBox(height: 14),

                    // ══ Quick Action Buttons ══════════════════════════
                    _buildQuickActions(),

                    // ══ Error Banner ═════════════════════════════════
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 14),
                      _buildErrorBanner(),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.6),
        border: Border(
          bottom: BorderSide(color: _indigo.withOpacity(0.15), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _indigo.withOpacity(0.2)),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Expanded(
            child: ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [_indigo, _purple],
              ).createShader(b),
              child: const Text(
                "التعرف على الإشارة",
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 20),
              ),
            ),
          ),
          // Flip camera
          GestureDetector(
            onTap: _isRecording ? null : _toggleCamera,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _indigo.withOpacity(0.2)),
              ),
              child: Icon(Icons.flip_camera_ios_rounded,
                  color: _isRecording ? Colors.white24 : _indigo, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── Camera Feed ────────────────────────────────────────────────────
  Widget _buildCameraFeed() {
    final borderColor = _isRecording ? Colors.red : _neonCyan;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => Center(
        child: Container(
          height: 320,
          width: 320,
          margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: borderColor.withOpacity(
                _isRecording ? 0.6 * _glowAnim.value : 0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: borderColor.withOpacity(0.2 * _glowAnim.value),
              blurRadius: 30,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: _indigo.withOpacity(0.08),
              blurRadius: 40,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera or placeholder
              if (_errorMsg != null && !_hasResult)
                _buildPlaceholder(
                  icon: Icons.videocam_off_rounded,
                  title: "الكاميرا غير متاحة",
                  subtitle: _errorMsg!,
                )
              else if (!_isInitialized)
                _buildPlaceholder(
                  icon: Icons.camera_alt_rounded,
                  title: "جاري تشغيل الكاميرا...",
                  subtitle: "يرجى الانتظار",
                  loading: true,
                )
              else
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize?.height ?? 1,
                    height: _controller!.value.previewSize?.width ?? 1,
                    child: AspectRatio(
                      aspectRatio: 1 / _controller!.value.aspectRatio,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),

              // ── Recording indicator ────────────────────────────
              if (_isRecording)
                Positioned(
                  top: 12,
                  right: 12,
                  child: AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.red.withOpacity(0.6), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red
                                .withOpacity(0.4 * _pulseAnim.value),
                            blurRadius: 16 * _pulseAnim.value,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8 * _pulseAnim.value,
                            height: 8 * _pulseAnim.value,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text("REC",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Sending overlay ────────────────────────────────
              if (_isSending)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: _neonCyan,
                            strokeWidth: 3,
                            backgroundColor: _indigo.withOpacity(0.2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: [_neonCyan, _indigo],
                          ).createShader(b),
                          child: const Text(
                            "جاري تحليل الإشارة...",
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Camera badge ───────────────────────────────────
              if (_isInitialized)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.12), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isFront
                              ? Icons.person_rounded
                              : Icons.landscape_rounded,
                          color: _neonCyan,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isFront ? "أمامية" : "خلفية",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),


            ],
          ),
        ),
      ),
      ),
    );
  }

  // ── Record Button ──────────────────────────────────────────────────
  Widget _buildRecordButton() {
    return SparkleButton(
      onTap: _isSending
          ? null
          : (_isRecording ? _stopAndSend : _startRecording),
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: LinearGradient(
            colors: _isRecording
                ? [Colors.red.shade400, Colors.red.shade700]
                : _isSending
                    ? [Colors.grey.shade800, Colors.grey.shade800]
                    : [_indigo, _purple],
          ),
          border: Border.all(
            color: (_isRecording ? Colors.red : _indigo).withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isRecording ? Colors.red : _indigo).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRecording ? Icons.stop_rounded : Icons.videocam_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              _isRecording ? "إيقاف وإرسال" : "بدء التسجيل",
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Import Video/GIF Section ───────────────────────────────────────
  Widget _buildImportSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _neonCyan.withOpacity(0.2), width: 1),
      ),
      child: _importedFile != null
          // ── File selected / processing ──────────────────────────
          ? Row(
              children: [
                // File icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isProcessingFile
                        ? _neonCyan.withOpacity(0.15)
                        : _emerald.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isProcessingFile
                          ? _neonCyan.withOpacity(0.3)
                          : _emerald.withOpacity(0.3),
                    ),
                  ),
                  child: _isProcessingFile
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _neonCyan,
                            backgroundColor: _neonCyan.withOpacity(0.15),
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded,
                          color: _emerald, size: 20),
                ),
                const SizedBox(width: 12),
                // File name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isProcessingFile
                            ? "جاري تحليل الملف..."
                            : "تم تحليل الملف",
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isProcessingFile
                              ? _neonCyan
                              : _emerald,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _importedFile!.path.split(RegExp(r'[\\/]')).last,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Clear button
                if (!_isProcessingFile)
                  GestureDetector(
                    onTap: _clearImportedFile,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white38, size: 16),
                    ),
                  ),
              ],
            )
          // ── Upload prompt ───────────────────────────────────────
          : GestureDetector(
              onTap: _isProcessingFile ? null : _pickAndSendFile,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _neonCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _neonCyan.withOpacity(0.25)),
                    ),
                    child: const Icon(Icons.upload_file_rounded,
                        color: _neonCyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "أو أدرج فيديو / GIF",
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "MP4, AVI, MOV, GIF, WebM",
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: _neonCyan.withOpacity(0.5), size: 16),
                ],
              ),
            ),
    );
  }

  // ── Translation Console ────────────────────────────────────────────
  Widget _buildTranslationConsole() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface, // Darkened for text contrast
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _indigo.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(color: _indigo.withOpacity(0.06), blurRadius: 30),
        ],
      ),
      child: Column(
        children: [
          // ── Header row ─────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: _hasResult
                      ? const LinearGradient(colors: [_neonCyan, _indigo])
                      : null,
                  color: _hasResult ? null : _indigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: (_hasResult ? _neonCyan : _indigo)
                          .withOpacity(0.3)),
                ),
                child: Icon(
                  Icons.sign_language_rounded,
                  color: _hasResult ? Colors.white : _indigo,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "الإشارة المُتعرَّف عليها",
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    _hasResult && _prediction.isNotEmpty
                        ? ShaderMask(
                            shaderCallback: (b) => const LinearGradient(
                              colors: [_neonCyan, _purple],
                            ).createShader(b),
                            child: Text(
                              _prediction,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            _isSending
                                ? "جاري التحليل..."
                                : _isRecording
                                    ? "🤟 سجّل إشارتك"
                                    : "في انتظار الإشارة...",
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                  ],
                ),
              ),

              // ── Circular Confidence Indicator ──────────────────
              if (_hasResult && _confidence.isNotEmpty)
                AnimatedBuilder(
                  animation: _confidenceAnim,
                  builder: (_, __) => SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: _confidenceAnim.value,
                            strokeWidth: 4,
                            backgroundColor: _neonCyan.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _confidenceAnim.value > 0.8
                                  ? _neonCyan
                                  : _confidenceAnim.value > 0.5
                                      ? _indigo
                                      : Colors.amber,
                            ),
                          ),
                        ),
                        Text(
                          _confidence,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _confidenceAnim.value > 0.8
                                ? _neonCyan
                                : _confidenceAnim.value > 0.5
                                    ? _indigo
                                    : Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // ── Top 3 Predictions ──────────────────────────────────
          if (_top3.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                  height: 1, color: Colors.white.withOpacity(0.08)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _top3.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final isTop = i == 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isTop
                        ? _indigo.withOpacity(0.15)
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isTop
                          ? _indigo.withOpacity(0.4)
                          : Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(p.word,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isTop ? FontWeight.bold : FontWeight.w500,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(p.confidence,
                          style: TextStyle(
                              fontSize: 11,
                              color: isTop
                                  ? _neonCyan
                                  : Colors.white54)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Generated Sentence Row ─────────────────────────────────────────
  Widget _buildSentenceRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, // Darkened for text contrast
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(color: _purple.withOpacity(0.04), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Section Header ─────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // TTS button
              GestureDetector(
                onTap: _generatedSentence.isEmpty ? null : _speakSentence,
                child: AnimatedBuilder(
                  animation: _ttsWaveCtrl,
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isSpeaking
                          ? _emerald.withOpacity(0.2)
                          : _generatedSentence.isEmpty
                              ? Colors.white.withOpacity(0.04)
                              : _indigo.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isSpeaking
                            ? _emerald.withOpacity(0.5)
                            : _generatedSentence.isEmpty
                                ? Colors.white.withOpacity(0.08)
                                : _indigo.withOpacity(0.3),
                      ),
                      boxShadow: _isSpeaking
                          ? [
                              BoxShadow(
                                color: _emerald.withOpacity(
                                    0.3 * _ttsWaveCtrl.value),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isSpeaking
                              ? Icons.graphic_eq_rounded
                              : Icons.volume_up_rounded,
                          color: _isSpeaking
                              ? _emerald
                              : _generatedSentence.isEmpty
                                  ? Colors.white24
                                  : _indigo,
                          size: 18,
                        ),
                        if (_isSpeaking) ...[
                          const SizedBox(width: 6),
                          // Animated wave bars
                          ...List.generate(3, (i) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              width: 3,
                              height: 6 +
                                  (sin(_ttsWaveCtrl.value * pi * 2 + i * 1.2) *
                                          6)
                                      .abs(),
                              decoration: BoxDecoration(
                                color: _emerald,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Label
              Text(
                "الجملة المُترجمة",
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Sentence Badges ────────────────────────────────────
          _generatedSentence.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "سجّل إشارة لبناء الجملة تلقائياً...",
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.25), fontSize: 13),
                  ),
                )
              : SizedBox(
                  height: 42,
                  child: ListView.separated(
                    controller: _sentenceScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    reverse: true, // RTL
                    itemCount: _generatedSentence.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_back_ios_rounded,
                          color: _purple.withOpacity(0.4), size: 12),
                    ),
                    itemBuilder: (_, i) {
                      final word = _generatedSentence[i];
                      final isLatest =
                          i == _generatedSentence.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isLatest
                              ? const LinearGradient(
                                  colors: [_indigo, _purple])
                              : null,
                          color: isLatest
                              ? null
                              : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isLatest
                                ? _purple.withOpacity(0.6)
                                : _indigo.withOpacity(0.2),
                            width: 1,
                          ),
                          boxShadow: isLatest
                              ? [
                                  BoxShadow(
                                    color: _indigo.withOpacity(0.3),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          word,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isLatest
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  // ── Quick Action Buttons ───────────────────────────────────────────
  Widget _buildQuickActions() {
    return Row(
      children: [
        // Delete Last Word
        Expanded(
          child: GestureDetector(
            onTap: _generatedSentence.isEmpty ? null : _deleteLastWord,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                    _generatedSentence.isEmpty ? 0.03 : 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _generatedSentence.isEmpty
                      ? Colors.white.withOpacity(0.06)
                      : Colors.amber.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.undo_rounded,
                      color: _generatedSentence.isEmpty
                          ? Colors.white24
                          : Colors.amber,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "تراجع",
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: _generatedSentence.isEmpty
                          ? Colors.white24
                          : Colors.amber,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Clear All
        Expanded(
          child: GestureDetector(
            onTap: _generatedSentence.isEmpty ? null : _clearAll,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                    _generatedSentence.isEmpty ? 0.03 : 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _generatedSentence.isEmpty
                      ? Colors.white.withOpacity(0.06)
                      : Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline_rounded,
                      color: _generatedSentence.isEmpty
                          ? Colors.white24
                          : Colors.red.shade300,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "امسح الكل",
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: _generatedSentence.isEmpty
                          ? Colors.white24
                          : Colors.red.shade300,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Error Banner ───────────────────────────────────────────────────
  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMsg!,
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMsg = null),
            child: const Icon(Icons.close_rounded,
                color: Colors.white30, size: 18),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    required String subtitle,
    bool loading = false,
  }) {
    return Container(
      color: _bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: _neonCyan,
                strokeWidth: 3,
                backgroundColor: _indigo.withOpacity(0.15),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _indigo.withOpacity(0.12),
                border: Border.all(color: _indigo.withOpacity(0.25)),
                boxShadow: [
                  BoxShadow(color: _indigo.withOpacity(0.15), blurRadius: 20),
                ],
              ),
              child: Icon(icon, color: _indigo, size: 40),
            ),
          const SizedBox(height: 16),
          Text(title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(subtitle,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const sz = 20.0;
    const tk = 3.0;
    const col = _neonCyan;
    return [
      Positioned(
          top: 0,
          left: 0,
          child: _corner(top: true, left: true, sz: sz, tk: tk, col: col)),
      Positioned(
          top: 0,
          right: 0,
          child: _corner(top: true, left: false, sz: sz, tk: tk, col: col)),
      Positioned(
          bottom: 0,
          left: 0,
          child: _corner(top: false, left: true, sz: sz, tk: tk, col: col)),
      Positioned(
          bottom: 0,
          right: 0,
          child: _corner(top: false, left: false, sz: sz, tk: tk, col: col)),
    ];
  }

  Widget _corner({
    required bool top,
    required bool left,
    required double sz,
    required double tk,
    required Color col,
  }) {
    return SizedBox(
      width: sz,
      height: sz,
      child: CustomPaint(
          painter:
              _CornerPainter(top: top, left: left, thick: tk, color: col)),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top, left;
  final double thick;
  final Color color;
  const _CornerPainter(
      {required this.top,
      required this.left,
      required this.thick,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    canvas.drawLine(
        Offset(x, y), Offset(x + (left ? size.width : -size.width), y), p);
    canvas.drawLine(
        Offset(x, y), Offset(x, y + (top ? size.height : -size.height)), p);
  }

  @override
  bool shouldRepaint(_) => false;
}
