import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'theme.dart';
import 'bubble_screen.dart';
import 'api_config.dart';

class TextToSignScreen extends StatefulWidget {
  const TextToSignScreen({super.key});

  @override
  State<TextToSignScreen> createState() => _TextToSignScreenState();
}

class _TextToSignScreenState extends State<TextToSignScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _sentenceCtrl = TextEditingController();

  List<String> _allSigns = [];
  List<String> _filteredSigns = [];
  String? _selectedWord;
  
  // Animation data from API (rotations or points)
  Map<String, dynamic>? _animationFrames;
  String? _animationWord;  // which word the current frames belong to
  bool _isPlayingAnimation = false;
  
  // Sentence signing state
  bool _isSentenceMode = false;
  List<String> _sentenceWords = [];  // parsed words from sentence
  int _currentWordIndex = -1;        // which word is currently being signed
  int _totalSentenceFrames = 0;
  
  bool _isLoading = false;
  bool _isLoadingSigns = true;
  String? _error;

  final _webviewController = WebviewController();
  bool _isWebviewInitialized = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadSigns();
    _initWebview();
  }

  Future<void> _initWebview() async {
    try {
      print('[WebView] Initializing...');
      await _webviewController.initialize();

      // â”€â”€ Forward JS console messages to Flutter â”€â”€
      _webviewController.webMessage.listen((msg) {
        final msgStr = msg.toString();
        print('[WebView JS] $msgStr');
        
        // Handle sentence word progress messages
        if (msgStr.startsWith('WORD_START:')) {
          final idx = int.tryParse(msgStr.substring('WORD_START:'.length));
          if (idx != null && mounted) {
            setState(() => _currentWordIndex = idx);
            print('[Sentence] Word $idx started: ${idx < _sentenceWords.length ? _sentenceWords[idx] : "?"}');
          }
        } else if (msgStr.startsWith('WORD_END:')) {
          final idx = int.tryParse(msgStr.substring('WORD_END:'.length));
          if (idx != null) {
            print('[Sentence] Word $idx ended');
          }
        } else if (msgStr == 'ANIMATION_DONE') {
          if (mounted) {
            setState(() {
              _isPlayingAnimation = false;
              _currentWordIndex = -1;
            });
          }
        }
      });

      // â”€â”€ Inject console.log/error forwarding â”€â”€
      // webview_windows doesn't have a built-in console listener,
      // so we override console methods via JS after page loads.
      _webviewController.loadingState.listen((state) async {
        print('[WebView] Loading state: $state');
        if (state == LoadingState.navigationCompleted) {
          print('[WebView] Navigation completed. Injecting console forwarder...');
          await _webviewController.executeScript('''
            (function() {
              var origLog = console.log;
              var origError = console.error;
              var origWarn = console.warn;
              console.log = function() {
                var msg = Array.from(arguments).join(' ');
                origLog.apply(console, arguments);
                if (window.chrome && window.chrome.webview) {
                  window.chrome.webview.postMessage('LOG: ' + msg);
                }
              };
              console.error = function() {
                var msg = Array.from(arguments).join(' ');
                origError.apply(console, arguments);
                if (window.chrome && window.chrome.webview) {
                  window.chrome.webview.postMessage('ERROR: ' + msg);
                }
              };
              console.warn = function() {
                var msg = Array.from(arguments).join(' ');
                origWarn.apply(console, arguments);
                if (window.chrome && window.chrome.webview) {
                  window.chrome.webview.postMessage('WARN: ' + msg);
                }
              };
              console.log('[VRM] Console forwarder injected!');
            })();
          ''');
        }
      });

      // Clear cache before loading
      await _webviewController.clearCache();
      
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = '${ApiConfig.baseUrl}/static/index.html?v=$ts';
      print('[WebView] Loading URL: $url');
      await _webviewController.loadUrl(url);
      
      if (!mounted) return;
      setState(() {
        _isWebviewInitialized = true;
      });
      print('[WebView] âœ… Initialized and URL loaded.');
    } catch (e, stack) {
      print('[WebView] â‌Œ Init error: $e');
      print('[WebView] Stack: $stack');
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    _sentenceCtrl.dispose();
    _webviewController.dispose();
    super.dispose();
  }

  Future<void> _loadSigns() async {
    setState(() {
      _isLoadingSigns = true;
      _error = null;
    });

    print('[TextToSign] Loading signs from API...');
    final signs = await _api.getAvailableSigns();
    print('[TextToSign] Got ${signs.length} signs');

    if (!mounted) return;
    setState(() {
      _allSigns = signs;
      _filteredSigns = signs;
      _isLoadingSigns = false;
      if (signs.isEmpty) {
        _error = 'Could not load signs. Is the server running?';
      }
    });
  }

  void _filterSigns(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSigns = _allSigns;
      } else {
        _filteredSigns = _allSigns
            .where((s) => s.contains(query.trim()))
            .toList();
      }
    });
  }

  Future<void> _generateSign() async {
    if (_selectedWord == null) return;
    
    final wordToGenerate = _selectedWord!;
    print('[GenerateSign] Generating for word: "$wordToGenerate"');

    setState(() {
      _isLoading = true;
      _error = null;
      _animationFrames = null;
      _animationWord = null;
      _isPlayingAnimation = false;
      _isSentenceMode = false;
      _sentenceWords = [];
      _currentWordIndex = -1;
    });

    // Stop any previous animation and reset to T-pose
    if (_isWebviewInitialized) {
      try {
        await _webviewController.executeScript("stopAnimation();");
        print('[GenerateSign] Stopped previous animation');
      } catch (e) {
        print('[GenerateSign] Stop error (non-critical): $e');
      }
    }

    final result = await _api.textToSignPoints(wordToGenerate);

    if (!mounted) return;
    
    // Verify user hasn't selected a different word while we were loading
    if (_selectedWord != wordToGenerate) {
      print('[GenerateSign] Word changed during loading, discarding result');
      setState(() { _isLoading = false; });
      return;
    }
    
    setState(() {
      _isLoading = false;
      if (result != null) {
        _animationFrames = result;
        _animationWord = wordToGenerate;
        _fadeCtrl.forward(from: 0);
        print('[GenerateSign] Got ${(result["rotations"] as List?)?.length ?? 0} frames for "$wordToGenerate"');
        _playAnimation();
      } else {
        _error = 'Could not generate sign. Please try again.';
      }
    });
  }

  Future<void> _playAnimation() async {
    if (_animationFrames == null || !_isWebviewInitialized) return;
    
    final currentWord = _animationWord ?? 'unknown';
    print('[PlayAnimation] Playing animation for "$currentWord"');
    
    setState(() {
      _isPlayingAnimation = true;
    });

    // Check if we have pre-computed rotations (preferred)
    final rotations = _animationFrames!['rotations'] as List<dynamic>?;

    if (rotations != null && rotations.isNotEmpty) {
      // â”€â”€ SMOOTH: Send ALL frames at once for smooth interpolated playback â”€â”€
      final allFramesJson = json.encode(rotations);
      // Escape single quotes in the JSON string for JS
      final escaped = allFramesJson.replaceAll("'", "\\'");
      try {
        print('[Animation] Sending ${rotations.length} frames for "$currentWord"');
        await _webviewController.executeScript("playAnimation('$escaped');");
      } catch (e) {
        print('[Animation] Error: $e');
      }
      
      // Wait for animation to complete (~100ms per frame)
      // The WebView will send ANIMATION_DONE message when finished
      final totalDuration = rotations.length * 100 + 500; // extra buffer
      await Future.delayed(Duration(milliseconds: totalDuration));
    }
    
    if (mounted) {
      setState(() {
        _isPlayingAnimation = false;
      });
    }
  }

  // â•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گ
  //  SENTENCE SIGNING â€” Parse, fetch, and play sequentially
  // â•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گâ•گ

  /// Split a sentence into words that match available signs.
  List<String> _parseSentence(String sentence) {
    final words = sentence.trim().split(RegExp(r'\s+'));
    final matched = <String>[];
    
    // Try to match multi-word signs first, then single words
    int i = 0;
    while (i < words.length) {
      bool found = false;
      // Try 3-word, 2-word, then 1-word matches
      for (int len = 3; len >= 1; len--) {
        if (i + len <= words.length) {
          final phrase = words.sublist(i, i + len).join(' ');
          if (_allSigns.contains(phrase)) {
            matched.add(phrase);
            i += len;
            found = true;
            break;
          }
        }
      }
      if (!found) {
        // Try partial match (sign contains this word)
        final word = words[i];
        final partial = _allSigns.where((s) => s == word).toList();
        if (partial.isNotEmpty) {
          matched.add(partial.first);
        } else {
          print('[Sentence] Skipping unmatched word: "$word"');
        }
        i++;
      }
    }
    return matched;
  }

  /// Generate and play a full sentence animation.
  Future<void> _generateSentence() async {
    final sentence = _sentenceCtrl.text.trim();
    if (sentence.isEmpty) return;

    // Parse sentence into matched words
    final words = _parseSentence(sentence);
    if (words.isEmpty) {
      setState(() => _error = 'ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط¥ط´ط§ط±ط§طھ ظ…ط·ط§ط¨ظ‚ط© ظپظٹ ط§ظ„ط¬ظ…ظ„ط©');
      return;
    }

    print('[Sentence] Parsed ${words.length} words: $words');

    setState(() {
      _isLoading = true;
      _error = null;
      _isSentenceMode = true;
      _sentenceWords = words;
      _currentWordIndex = -1;
      _animationFrames = null;
      _isPlayingAnimation = false;
    });

    // Stop any previous animation
    if (_isWebviewInitialized) {
      try {
        await _webviewController.executeScript("stopAnimation();");
      } catch (_) {}
    }

    // Fetch animation data for each word sequentially
    final List<List<dynamic>> allWordRotations = [];
    for (int i = 0; i < words.length; i++) {
      if (!mounted) return;
      setState(() => _currentWordIndex = i);
      print('[Sentence] Fetching word ${i + 1}/${words.length}: "${words[i]}"');
      
      final result = await _api.textToSignPoints(words[i]);
      if (result != null) {
        final rotations = result['rotations'] as List<dynamic>?;
        if (rotations != null && rotations.isNotEmpty) {
          allWordRotations.add(rotations);
        }
      }
    }

    if (!mounted) return;

    if (allWordRotations.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'ظپط´ظ„ ظپظٹ طھظˆظ„ظٹط¯ ط§ظ„ط­ط±ظƒط§طھ';
      });
      return;
    }

    // Calculate total frames for progress tracking
    int totalFrames = 0;
    for (final r in allWordRotations) {
      totalFrames += r.length;
    }
    // Subtract cross-fade overlap
    totalFrames -= (allWordRotations.length - 1) * 5;

    setState(() {
      _isLoading = false;
      _totalSentenceFrames = totalFrames;
      _fadeCtrl.forward(from: 0);
    });

    // Play sentence animation with cross-fading
    await _playSentenceAnimation(allWordRotations);
  }

  /// Send all word frame arrays to JS for cross-faded playback.
  Future<void> _playSentenceAnimation(List<List<dynamic>> wordRotations) async {
    if (!_isWebviewInitialized) return;

    setState(() {
      _isPlayingAnimation = true;
      _currentWordIndex = 0;
    });

    // Encode the array of word rotation arrays
    final wordsJson = json.encode(wordRotations);
    final escaped = wordsJson.replaceAll("'", "\\'");

    try {
      print('[Sentence] Sending ${wordRotations.length} words to playSentenceAnimation()');
      await _webviewController.executeScript("playSentenceAnimation('$escaped');");
    } catch (e) {
      print('[Sentence] Error: $e');
    }

    // Wait for animation to complete
    // Total duration = totalFrames * 100ms + return-to-idle buffer
    final totalDuration = _totalSentenceFrames * 100 + 1200;
    await Future.delayed(Duration(milliseconds: totalDuration));

    if (mounted) {
      setState(() {
        _isPlayingAnimation = false;
        _currentWordIndex = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppColors.background;
    final cardColor = Colors.white.withOpacity(0.06);
    const textColor = Colors.white;
    final subColor = Colors.white.withOpacity(0.5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
          child: const Text(
            "ترجمة النص",
            textDirection: TextDirection.rtl,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
          ),
        ),
      ),
      body: _isLoadingSigns
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text("Loading available signs...",
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : (_allSigns.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded,
                            size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _error ?? "Could not load signs",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Make sure the backend server is running\nat ${ApiConfig.baseUrl}",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _loadSigns,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text("Retry"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // ══ TOP PANEL: Search + Word Grid (fixed) ══════════════
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.primary.withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Search Field ──────────────────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              style: const TextStyle(color: Colors.white),
                              onChanged: _filterSigns,
                              textDirection: TextDirection.rtl,
                              decoration: InputDecoration(
                                filled: false,
                                hintText: "ابحث عن كلمة لإضافتها للجملة...",
                                hintTextDirection: TextDirection.rtl,
                                hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.4)),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    color: AppColors.primary),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ── Words Grid ────────────────────────────────
                          SizedBox(
                            height: 116,
                            child: _filteredSigns.isEmpty
                                ? Center(
                                    child: Text("لم يتم العثور على إشارات",
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.4))))
                                : GridView.builder(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                      childAspectRatio: 2.8,
                                    ),
                                    itemCount: _filteredSigns.length,
                                    itemBuilder: (_, i) {
                                      final word = _filteredSigns[i];
                                      final isSelected = word == _selectedWord;
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() => _selectedWord = word);
                                          // Append word to sentence field
                                          final current =
                                              _sentenceCtrl.text.trim();
                                          _sentenceCtrl.text = current.isEmpty
                                              ? word
                                              : '$current $word';
                                          _sentenceCtrl.selection =
                                              TextSelection.fromPosition(
                                            TextPosition(
                                                offset:
                                                    _sentenceCtrl.text.length),
                                          );
                                        },
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          decoration: BoxDecoration(
                                            gradient: isSelected
                                                ? AppColors.primaryGradient
                                                : null,
                                            color: isSelected
                                                ? null
                                                : Colors.white.withOpacity(0.05),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.accent
                                                  : AppColors.primary
                                                      .withOpacity(0.2),
                                              width: isSelected ? 1.5 : 1,
                                            ),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withOpacity(0.3),
                                                      blurRadius: 8,
                                                    )
                                                  ]
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            word,
                                            textDirection: TextDirection.rtl,
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),

                    // ══ BOTTOM PANEL: Scrollable content ═══════════════════
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Sentence Input ───────────────────────────
                            Text(
                              "اكتب جملة أو اختر كلمات من الأعلى",
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: subColor,
                                  letterSpacing: 1),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _sentenceCtrl,
                                style:
                                    const TextStyle(color: textColor, fontSize: 15),
                                textDirection: TextDirection.rtl,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  filled: false,
                                  hintText: "مثال: هيكل عظمي قلب جمجة...",
                                  hintTextDirection: TextDirection.rtl,
                                  hintStyle: TextStyle(color: subColor),
                                  prefixIcon: const Icon(Icons.edit_note_rounded,
                                      color: AppColors.primary),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.clear_rounded,
                                        color: Colors.white.withOpacity(0.3),
                                        size: 18),
                                    onPressed: () {
                                      _sentenceCtrl.clear();
                                      setState(() => _selectedWord = null);
                                    },
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Translate Sentence Button ────────────────
                            SparkleButton(
                              onTap: !_isLoading ? _generateSentence : null,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [AppColors.primary, AppColors.accent],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isLoading && _isSentenceMode)
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5),
                                      )
                                    else ...[
                                      const Icon(Icons.play_arrow_rounded,
                                          color: Colors.white, size: 24),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "ترجم الجملة",
                                        textDirection: TextDirection.rtl,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            // ── Word Progress + Replay ───────────────────
                            if (_isSentenceMode && _sentenceWords.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Replay button (left in RTL)
                                          if (!_isPlayingAnimation && !_isLoading)
                                            GestureDetector(
                                              onTap: _generateSentence,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      AppColors.primaryGradient,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withOpacity(0.4),
                                                      blurRadius: 10,
                                                    ),
                                                  ],
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.replay_rounded,
                                                        color: Colors.white,
                                                        size: 16),
                                                    SizedBox(width: 6),
                                                    Text(
                                                      "إعادة",
                                                      style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else
                                            const SizedBox(),
                                          Text(
                                            "تقدم الترجمة",
                                            textDirection: TextDirection.rtl,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: subColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        textDirection: TextDirection.rtl,
                                        children: List.generate(
                                            _sentenceWords.length, (i) {
                                          final isActive =
                                              i == _currentWordIndex;
                                          final isDone = _currentWordIndex > i ||
                                              (!_isPlayingAnimation &&
                                                  !_isLoading &&
                                                  _currentWordIndex == -1 &&
                                                  _sentenceWords.isNotEmpty);
                                          return AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? AppColors.primary
                                                  : isDone
                                                      ? AppColors.primary
                                                          .withOpacity(0.3)
                                                      : AppColors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: isActive
                                                  ? Border.all(
                                                      color: AppColors.accent,
                                                      width: 2)
                                                  : null,
                                              boxShadow: isActive
                                                  ? [
                                                      BoxShadow(
                                                        color: AppColors.primary
                                                            .withOpacity(0.4),
                                                        blurRadius: 10,
                                                      )
                                                    ]
                                                  : null,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isDone && !isActive)
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.only(left: 4),
                                                    child: Icon(
                                                        Icons
                                                            .check_circle_rounded,
                                                        color: Colors.white,
                                                        size: 14),
                                                  ),
                                                if (isActive)
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.only(left: 4),
                                                    child: SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child:
                                                          CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  _sentenceWords[i],
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isActive
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                    color: isActive || isDone
                                                        ? Colors.white
                                                        : textColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // ── Divider ──────────────────────────────────
                            Row(
                              children: [
                                Expanded(
                                    child: Divider(
                                        color: subColor.withOpacity(0.3))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Text("أو ترجم كلمة مفردة",
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                          color: subColor, fontSize: 12)),
                                ),
                                Expanded(
                                    child: Divider(
                                        color: subColor.withOpacity(0.3))),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ── Generate Single Word Button ──────────────
                            SparkleButton(
                              onTap: (_selectedWord != null && !_isLoading)
                                  ? _generateSign
                                  : null,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: _selectedWord != null
                                      ? AppColors.primaryGradient
                                      : null,
                                  color: _selectedWord == null
                                      ? Colors.white.withOpacity(0.08)
                                      : null,
                                  border: _selectedWord == null
                                      ? Border.all(
                                          color: Colors.white.withOpacity(0.15))
                                      : null,
                                  boxShadow: _selectedWord != null
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withOpacity(0.35),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isLoading && !_isSentenceMode)
                                      const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5),
                                      )
                                    else ...[
                                      const Icon(Icons.sign_language_rounded,
                                          color: Colors.white, size: 22),
                                      const SizedBox(width: 10),
                                      Text(
                                        _selectedWord != null
                                            ? 'ترجمة "$_selectedWord"'
                                            : "اختر كلمة من الأعلى",
                                        textDirection: TextDirection.rtl,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // ── Error Banner ─────────────────────────────
                            if (_error != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: Colors.red),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: Colors.red))),
                                  ],
                                ),
                              ),

                            // ── Avatar WebView — Always Visible ──────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.12),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.sign_language_rounded,
                                          color: AppColors.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _isSentenceMode &&
                                                  _sentenceWords.isNotEmpty
                                              ? 'ترجمة الجملة'
                                              : _selectedWord != null
                                                  ? 'إشارة "$_selectedWord"'
                                                  : 'الأفاتار',
                                          textDirection: TextDirection.rtl,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      if (_isPlayingAnimation) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(
                                                width: 10,
                                                height: 10,
                                                child:
                                                    CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 1.5),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                _isSentenceMode &&
                                                        _currentWordIndex >= 0 &&
                                                        _currentWordIndex <
                                                            _sentenceWords.length
                                                    ? "🤟 ${_sentenceWords[_currentWordIndex]}"
                                                    : "جارٍ...",
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: 420,
                                      child: _isWebviewInitialized
                                          ? Webview(_webviewController)
                                          : const Center(
                                              child: CircularProgressIndicator(
                                                  color: AppColors.primary)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
