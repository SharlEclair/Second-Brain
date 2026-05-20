import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/audio_ingest_service.dart';
import '../screens/debug_logs_screen.dart';

class BrainDumpButton extends StatefulWidget {
  const BrainDumpButton({super.key});

  @override
  State<BrainDumpButton> createState() => _BrainDumpButtonState();
}

class _BrainDumpButtonState extends State<BrainDumpButton> with SingleTickerProviderStateMixin {
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  bool _isUploading = false;
  int _recordDuration = 0;
  Timer? _timer;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _startTimer() {
    _recordDuration = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        _recordDuration++;
      });
    });
    _pulseController?.repeat(reverse: true);
  }

  void _stopTimer() {
    _timer?.cancel();
    _pulseController?.stop();
    _pulseController?.value = 0.0;
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        // Stop recording
        _stopTimer();
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
        });

        if (path != null) {
          if (!mounted) return;
          setState(() {
            _isUploading = true;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Processing Voice Brain Dump...'),
              duration: Duration(seconds: 2),
            ),
          );

          final success = await AudioIngestService.uploadAudio(path);
          
          if (mounted) {
            setState(() {
              _isUploading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? '✓ Voice brain dump ingested successfully!'
                      : '❌ Failed to upload voice brain dump.',
                ),
                backgroundColor: success ? Colors.green : Colors.red,
              ),
            );
          }
        }
      } else {
        // Check permissions
        if (await _audioRecorder.hasPermission()) {
          final directory = await getTemporaryDirectory();
          final path = '${directory.path}/brain_dump_${DateTime.now().millisecondsSinceEpoch}.m4a';

          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc),
            path: path,
          );

          setState(() {
            _isRecording = true;
          });
          _startTimer();
          DebugLogger.log('Started voice recording: $path', type: 'SYSTEM');
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission denied.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      DebugLogger.log('Error recording/uploading audio: $e', type: 'ERROR');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isUploading = false;
        });
        _stopTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return FloatingActionButton(
        onPressed: null,
        backgroundColor: Colors.grey[800],
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFFF97316),
          ),
        ),
      );
    }

    if (_isRecording) {
      return FloatingActionButton.extended(
        onPressed: _toggleRecording,
        backgroundColor: const Color(0xFFDC2626),
        icon: AnimatedBuilder(
          animation: _pulseController!,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseController!.value * 0.25),
              child: child,
            );
          },
          child: const Icon(Icons.stop, color: Colors.white, size: 28),
        ),
        label: Text(
          _formatDuration(_recordDuration),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 16,
          ),
        ),
      );
    }

    return FloatingActionButton(
      onPressed: _toggleRecording,
      backgroundColor: const Color(0xFFF97316),
      child: const Icon(Icons.mic, color: Colors.black, size: 28),
    );
  }
}
