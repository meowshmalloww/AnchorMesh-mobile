// ignore_for_file: deprecated_member_use, experimental_member_use
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:fftea/fftea.dart';

class UltrasonicControl extends StatefulWidget {
  const UltrasonicControl({super.key});

  @override
  State<UltrasonicControl> createState() => _UltrasonicControlState();
}

class _UltrasonicControlState extends State<UltrasonicControl> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Modem Configuration
  static const int sampleRate = 44100;
  static const double freq0 = 18500.0; // Bit 0
  static const double freq1 = 19500.0; // Bit 1
  static const double baudRate = 20.0; // Slow but reliable (50ms/bit)
  static const int samplesPerBit = (sampleRate / baudRate) ~/ 1;

  // State
  bool _isSending = false;
  bool _isListening = false;
  bool _micPermissionGranted = false;

  // Receiver State
  StreamSubscription<List<int>>? _micSubscription;
  final List<String> _receivedLog = [];
  // _decodingBuffer used for future ASCII decoding implementation
  // final String _decodingBuffer = "";
  double _currentEnergy = 0.0;
  double _dominantFreq = 0.0;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.status;
    if (mounted) setState(() => _micPermissionGranted = status.isGranted);
  }

  @override
  void dispose() {
    _micSubscription?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ==================
  // TRANSMITTER (TX)
  // ==================

  Future<void> _sendSOS() async {
    if (_isSending || _isListening) return;

    HapticFeedback.heavyImpact();
    setState(() => _isSending = true);

    try {
      // 1. Prepare Data "SOS: <UserHash>"
      final message = "SOS:${math.Random().nextInt(999)}";
      final dataParams = utf8.encode(message);

      // 2. Encode to Bits (UART: Start + 8 bits + Stop)
      final List<int> bits = [];
      // Preamble (0xAA) to wake up receiver
      _encodeByte(bits, 0xAA);
      _encodeByte(bits, 0xAA);

      // Data
      for (final byte in dataParams) {
        _encodeByte(bits, byte);
      }

      // 3. Generate PCM Audio
      final pcmData = _generatePCM(bits);

      // 4. Play
      await _playPCM(pcmData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent: "$message"'),
            backgroundColor: Colors.purple,
          ),
        );
        setState(() => _receivedLog.insert(0, "Sent: $message"));
      }
    } catch (e) {
      debugPrint("Tx Error: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _encodeByte(List<int> bits, int byte) {
    // Start Bit (0)
    bits.add(0);
    // Data Bits (LSB First)
    for (int i = 0; i < 8; i++) {
      bits.add((byte >> i) & 1);
    }
    // Stop Bit (1)
    bits.add(1);
    // Extra Stop Bit for safety
    bits.add(1);
  }

  Uint8List _generatePCM(List<int> bits) {
    final totalSamples = bits.length * samplesPerBit;
    final bytes = BytesBuilder();

    // Header
    bytes.add(_buildWavHeader(totalSamples, sampleRate));

    // Waveform
    double phase = 0.0;
    for (final bit in bits) {
      final freq = bit == 1 ? freq1 : freq0;
      final phaseInc = 2 * math.pi * freq / sampleRate;

      for (int i = 0; i < samplesPerBit; i++) {
        final sample = (math.sin(phase) * 32767).toInt();
        bytes.addByte(sample & 0xFF);
        bytes.addByte((sample >> 8) & 0xFF);
        phase += phaseInc;
      }

      // Soft transition smoothing could be added here
    }

    return bytes.toBytes();
  }

  Future<void> _playPCM(Uint8List audioBytes) async {
    await _audioPlayer.setAudioSource(_ByteAudioSource(audioBytes));
    await _audioPlayer.play();
    await _audioPlayer.stop(); // Ensure reset
  }

  // ==================
  // RECEIVER (RX)
  // ==================

  Future<void> _toggleListener() async {
    if (_isListening) {
      _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_micPermissionGranted) {
      if (await _audioRecorder.hasPermission()) {
        setState(() => _micPermissionGranted = true);
      } else {
        return;
      }
    }

    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );

      setState(() => _isListening = true);

      // Buffer for FFT
      final int fftSize = 2048;
      final buffer = <double>[];

      _micSubscription = stream.listen((chunk) {
        // chunk is Uint8List of PCM 16-bit
        // Convert to doubles [-1.0, 1.0]
        for (int i = 0; i < chunk.length; i += 2) {
          if (i + 1 < chunk.length) {
            int val = chunk[i] | (chunk[i + 1] << 8);
            if (val > 32767) val -= 65536;
            buffer.add(val / 32768.0);
          }
        }

        while (buffer.length >= fftSize) {
          final segment = buffer.sublist(0, fftSize);
          buffer.removeRange(0, fftSize);
          _processFFT(segment);
        }
      });
    } catch (e) {
      debugPrint("Mic Error: $e");
      _stopListening();
    }
  }

  Future<void> _stopListening() async {
    _micSubscription?.cancel();
    await _audioRecorder.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _currentEnergy = 0;
        _dominantFreq = 0;
      });
    }
  }

  void _processFFT(List<double> samples) {
    if (samples.length < 2048) return;

    final fft = FFT(samples.length);
    final freqData = fft.realFft(samples);

    // Analyze 18kHz - 20kHz range
    // Bin resolution = 44100 / 2048 = ~21.5 Hz

    double maxMag = 0;
    int maxBin = 0;

    // 18000 Hz / 21.5 = ~837
    // 20000 Hz / 21.5 = ~930
    final startBin = (18000 / (sampleRate / samples.length)).round();
    final endBin = (20000 / (sampleRate / samples.length)).round();

    for (int i = startBin; i <= endBin && i < freqData.length; i++) {
      // fftea returns Float64x2 list for complex numbers (real, imaginary)
      // Magnitude = sqrt(re^2 + im^2). Float64x2 stores 2 complex numbers?
      // No, 'realFft' returns List<Float64x2> where each is ONE complex number (x, y)?
      // Actually, fftea docs say: "Returns a Float64x2List..."

      // We need .x (real) and .y (imag).
      final complex = freqData[i];
      final mag = math.sqrt(complex.x * complex.x + complex.y * complex.y);

      if (mag > maxMag) {
        maxMag = mag;
        maxBin = i;
      }
    }

    final peakFreq = maxBin * (sampleRate / samples.length);

    if (mounted) {
      setState(() {
        _currentEnergy = maxMag;
        _dominantFreq = peakFreq;
      });
    }

    // Threshold detection
    if (maxMag > 10.0) {
      // Tune this threshold
      // BFSK Demodulation Logic (Simple)
      // This is a naive visualizer/detector.
      // Robust ASCII decoding requires state machine (Start bit detection, sampling).
      // Implementing full UART decoding over audio in realtime is complex.
      // We will just show "Signal Detected" and the Freq.
    }
  }

  // ==================
  // UI
  // ==================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          _buildStatusCard(colors),
          const SizedBox(height: 30),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildBigButton(
                icon: Icons.record_voice_over,
                label: _isListening ? "LISTENING" : "RECEIVE",
                color: Colors.teal,
                isActive: _isListening,
                onTap: _isSending ? null : _toggleListener,
              ),
              _buildBigButton(
                icon: Icons.broadcast_on_personal,
                label: _isSending ? "SENDING..." : "SEND SOS",
                color: Colors.purple,
                isActive: _isSending,
                onTap: _isListening ? null : _sendSOS,
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Visualizer
          if (_isListening) ...[
            const Text(
              "SPECTRAL ANALYSIS",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (_currentEnergy / 50).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 5),
            Text(
              "${_dominantFreq.toStringAsFixed(0)} Hz",
              style: const TextStyle(
                fontFamily: 'Monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _getFreqLabel(_dominantFreq),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Log
          Container(
            height: 200,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              itemCount: _receivedLog.length,
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _receivedLog[i],
                  style: const TextStyle(fontSize: 12, fontFamily: 'Monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getFreqLabel(double freq) {
    if ((freq - freq0).abs() < 200) return "BIT 0 (18.5 kHz)";
    if ((freq - freq1).abs() < 200) return "BIT 1 (19.5 kHz)";
    return "NOISE";
  }

  Widget _buildStatusCard(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.waves, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ULTRASONIC DATA MODEM",
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Encodes text into 18-20kHz audio.",
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: isActive ? color : color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.5), width: 2),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 5,
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: isActive ? Colors.white : color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Uint8List _buildWavHeader(int numSamples, int sampleRate) {
    final byteRate = sampleRate * 2;
    final dataSize = numSamples * 2;
    final fileSize = 36 + dataSize;
    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46); // RIFF
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45); // WAVE
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20); // fmt
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61); // data
    header.setUint32(40, dataSize, Endian.little);
    return header.buffer.asUint8List();
  }
}

class _ByteAudioSource extends StreamAudioSource {
  final Uint8List _buffer;
  _ByteAudioSource(List<int> bytes) : _buffer = Uint8List.fromList(bytes);
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
