import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {

  CameraController? controller;
  List<CameraDescription>? cameras;

  String prediction = "Waiting for input...";

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    cameras = await availableCameras();

    controller = CameraController(
      cameras![0],
      ResolutionPreset.medium,
    );

    await controller!.initialize();

    if (!mounted) return;

    setState(() {});
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),

      appBar: AppBar(
        title: const Text("Sign Recognition"),
        backgroundColor: const Color(0xff1E88E5),
      ),

      body: Column(
        children: [

          /// Camera Preview
          Expanded(
            flex: 4,
            child: controller == null || !controller!.value.isInitialized
                ? const Center(child: Text("Camera initializing..."))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CameraPreview(controller!),
                  ),
          ),

          const SizedBox(height: 20),

          /// Prediction Text
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                )
              ],
            ),
            child: Column(
              children: [
                const Text(
                  "Predicted Sign:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  prediction,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xff1E88E5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}