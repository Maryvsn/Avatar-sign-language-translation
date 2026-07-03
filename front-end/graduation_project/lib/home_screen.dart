import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'camera_screen.dart';

late AnimationController _controller;
late Animation<double> _animation;

bool isListening = false;
String spokenText = "";

final speech = SpeechToText();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int currentIndex = 0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void listen() async {
    if (!isListening) {
      bool available = await speech.initialize();

      if (available) {
        setState(() => isListening = true);
        _controller.repeat(reverse: true);

        speech.listen(
          onResult: (result) {
            setState(() {
              spokenText = result.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => isListening = false);
      _controller.stop();
      speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF7F9FC),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "SIGN SENSE",
          style: TextStyle(
            color: Color(0xff1E88E5),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: CircleAvatar(
            backgroundColor: Color(0xffE3F2FD),
            child: Icon(Icons.help_outline, color: Color(0xff1E88E5)),
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            const Text(
              "Welcome Celestine",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "What would you like to do today?",
              style: TextStyle(color: Colors.grey),
            ),

            const SizedBox(height: 30),

            Center(
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _animation,
                    child: GestureDetector(
                      onTap: listen,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 150,
                        width: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: isListening
                                ? [
                                    Colors.red.shade200,
                                    Colors.red,
                                  ]
                                : [
                                    const Color(0xffE3F2FD),
                                    const Color(0xff90CAF9),
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isListening
                                  ? Colors.red.withOpacity(0.6)
                                  : const Color(0xff1E88E5)
                                      .withOpacity(0.4),
                              blurRadius: 25,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                        child: Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    isListening ? "Listening..." : "Tap to Speak",
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    spokenText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            Row(
              children: [
                Expanded(child: _smallButton("Translate to sign language")),
                const SizedBox(width: 15),
                Expanded(child: _smallButton("Translate to text")),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: _smallButton("Open Camera")),
              ],
            ),

            const Spacer(),

            _bigButton("Translate to sign language"),
            const SizedBox(height: 15),
            _bigButton("Translate to text"),

            const SizedBox(height: 20),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: const Color(0xff1E88E5),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });

          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CameraScreen(),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt), label: "Camera"),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: "Settings"),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  static Widget _smallButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  static Widget _bigButton(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff1E88E5)),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xff1E88E5),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}