class MorseCodeTranslator {
  static const Map<String, String> _morseCodeMap = {
    'A': '.-',
    'B': '-...',
    'C': '-.-.',
    'D': '-..',
    'E': '.',
    'F': '..-.',
    'G': '--.',
    'H': '....',
    'I': '..',
    'J': '.---',
    'K': '-.-',
    'L': '.-..',
    'M': '--',
    'N': '-.',
    'O': '---',
    'P': '.--.',
    'Q': '--.-',
    'R': '.-.',
    'S': '...',
    'T': '-',
    'U': '..-',
    'V': '...-',
    'W': '.--',
    'X': '-..-',
    'Y': '-.--',
    'Z': '--..',
    '1': '.----',
    '2': '..---',
    '3': '...--',
    '4': '....-',
    '5': '.....',
    '6': '-....',
    '7': '--...',
    '8': '---..',
    '9': '----.',
    '0': '-----',
    ' ': '/',
  };

  static String textToMorse(String text) {
    return text
        .toUpperCase()
        .split('')
        .map((char) {
          return _morseCodeMap[char] ?? '';
        })
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  // Returns a stream of booleans (true = toggle on, false = toggle off)
  // or simple durations? Better to have a controller logic.
  // 1 unit = dot duration.
  // dot = 1 unit on
  // dash = 3 units on
  // inter-element gap = 1 unit off
  // inter-letter gap = 3 units off
  // inter-word gap = 7 units off
}
