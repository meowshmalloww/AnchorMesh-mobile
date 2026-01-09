import 'dart:math' as math;
import 'dart:typed_data';

/// FFT-based audio analyzer for detecting ultrasonic frequencies
class FFTAnalyzer {
  final int sampleRate;
  final int fftSize;

  FFTAnalyzer({this.sampleRate = 44100, this.fftSize = 4096});

  /// Analyze audio samples and return the magnitude at ultrasonic frequencies (15-22 kHz)
  /// Returns a value between 0.0 and 1.0 representing signal strength
  double analyzeUltrasonicLevel(List<double> samples) {
    if (samples.length < fftSize) {
      return 0.0;
    }

    // Apply Hanning window to reduce spectral leakage
    final windowedSamples = _applyHanningWindow(samples.sublist(0, fftSize));

    // Perform FFT
    final fftResult = _fft(windowedSamples);

    // Calculate frequency resolution
    final freqResolution = sampleRate / fftSize;

    // Find indices for ultrasonic range (15kHz - 22kHz)
    final minFreq = 15000;
    final maxFreq = 22000;
    final minIndex = (minFreq / freqResolution).round();
    final maxIndex = (maxFreq / freqResolution).round().clamp(0, fftSize ~/ 2);

    // Calculate average magnitude in ultrasonic range
    double ultrasonicMagnitude = 0.0;
    int count = 0;

    for (int i = minIndex; i < maxIndex && i < fftResult.length ~/ 2; i++) {
      final real = fftResult[i * 2];
      final imag = fftResult[i * 2 + 1];
      final magnitude = math.sqrt(real * real + imag * imag);
      ultrasonicMagnitude += magnitude;
      count++;
    }

    if (count == 0) return 0.0;

    ultrasonicMagnitude /= count;

    // Calculate overall magnitude for normalization
    double totalMagnitude = 0.0;
    for (int i = 0; i < fftResult.length ~/ 2; i++) {
      final real = fftResult[i * 2];
      final imag = fftResult[i * 2 + 1];
      totalMagnitude += math.sqrt(real * real + imag * imag);
    }

    if (totalMagnitude == 0) return 0.0;

    // Return ratio of ultrasonic to total, scaled and clamped
    final ratio = (ultrasonicMagnitude / (totalMagnitude / (fftSize ~/ 2))) * 5;
    return ratio.clamp(0.0, 1.0);
  }

  /// Get the dominant frequency in the ultrasonic range
  double? getDominantUltrasonicFrequency(List<double> samples) {
    if (samples.length < fftSize) return null;

    final windowedSamples = _applyHanningWindow(samples.sublist(0, fftSize));
    final fftResult = _fft(windowedSamples);
    final freqResolution = sampleRate / fftSize;

    final minFreq = 15000;
    final maxFreq = 22000;
    final minIndex = (minFreq / freqResolution).round();
    final maxIndex = (maxFreq / freqResolution).round().clamp(0, fftSize ~/ 2);

    double maxMagnitude = 0.0;
    int maxIndex_ = minIndex;

    for (int i = minIndex; i < maxIndex && i < fftResult.length ~/ 2; i++) {
      final real = fftResult[i * 2];
      final imag = fftResult[i * 2 + 1];
      final magnitude = math.sqrt(real * real + imag * imag);
      if (magnitude > maxMagnitude) {
        maxMagnitude = magnitude;
        maxIndex_ = i;
      }
    }

    // Only return if there's a significant peak
    if (maxMagnitude < 100) return null;

    return maxIndex_ * freqResolution;
  }

  List<double> _applyHanningWindow(List<double> samples) {
    final result = List<double>.filled(samples.length, 0.0);
    for (int i = 0; i < samples.length; i++) {
      final window = 0.5 * (1 - math.cos(2 * math.pi * i / (samples.length - 1)));
      result[i] = samples[i] * window;
    }
    return result;
  }

  /// Cooley-Tukey FFT implementation
  /// Returns interleaved real and imaginary parts [r0, i0, r1, i1, ...]
  Float64List _fft(List<double> input) {
    final n = input.length;

    // Ensure power of 2
    final paddedLength = _nextPowerOf2(n);
    final paddedInput = List<double>.filled(paddedLength, 0.0);
    for (int i = 0; i < n; i++) {
      paddedInput[i] = input[i];
    }

    // Result array with interleaved real and imaginary parts
    final result = Float64List(paddedLength * 2);

    // Initialize with input (real parts)
    for (int i = 0; i < paddedLength; i++) {
      result[i * 2] = paddedInput[i];
      result[i * 2 + 1] = 0.0;
    }

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < paddedLength - 1; i++) {
      if (i < j) {
        // Swap real
        final tempReal = result[i * 2];
        result[i * 2] = result[j * 2];
        result[j * 2] = tempReal;
        // Swap imaginary
        final tempImag = result[i * 2 + 1];
        result[i * 2 + 1] = result[j * 2 + 1];
        result[j * 2 + 1] = tempImag;
      }
      int k = paddedLength ~/ 2;
      while (k <= j) {
        j -= k;
        k ~/= 2;
      }
      j += k;
    }

    // FFT computation
    int step = 1;
    while (step < paddedLength) {
      final halfStep = step;
      step *= 2;
      final angle = -math.pi / halfStep;
      final wReal = math.cos(angle);
      final wImag = math.sin(angle);

      for (int i = 0; i < paddedLength; i += step) {
        double curReal = 1.0;
        double curImag = 0.0;

        for (int k = 0; k < halfStep; k++) {
          final idx1 = i + k;
          final idx2 = i + k + halfStep;

          final t1Real = result[idx1 * 2];
          final t1Imag = result[idx1 * 2 + 1];
          final t2Real = result[idx2 * 2] * curReal - result[idx2 * 2 + 1] * curImag;
          final t2Imag = result[idx2 * 2] * curImag + result[idx2 * 2 + 1] * curReal;

          result[idx1 * 2] = t1Real + t2Real;
          result[idx1 * 2 + 1] = t1Imag + t2Imag;
          result[idx2 * 2] = t1Real - t2Real;
          result[idx2 * 2 + 1] = t1Imag - t2Imag;

          final newReal = curReal * wReal - curImag * wImag;
          final newImag = curReal * wImag + curImag * wReal;
          curReal = newReal;
          curImag = newImag;
        }
      }
    }

    return result;
  }

  int _nextPowerOf2(int n) {
    int power = 1;
    while (power < n) {
      power *= 2;
    }
    return power;
  }
}
