import 'package:flutter/widgets.dart' show StringCharacters;

/// Text in Indian languages (api/src/indic.ts and web/src/lib/indic.ts do the same). Members write asks,
/// names and pages in any script; nothing here changes what they wrote. It gives a Latin spelling for page
/// links (handles), made by a fixed letter table, never AI, and the first letter for avatars.

final _indic = RegExp(r'[ऀ-ൿ؀-ۿ]');
bool hasIndic(String s) => _indic.hasMatch(s);

// Devanagari offsets (U+0900 + n) to Latin. Bengali, Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada and
// Malayalam sit in 128-letter blocks laid out like Devanagari, so their letters read through the same table.
const _vowels = <int, String>{
  0x05: 'a', 0x06: 'a', 0x07: 'i', 0x08: 'i', 0x09: 'u', 0x0a: 'u', 0x0b: 'ri', 0x0c: 'li', 0x0d: 'e', 0x0e: 'e', 0x0f: 'e',
  0x10: 'ai', 0x11: 'o', 0x12: 'o', 0x13: 'o', 0x14: 'au', 0x60: 'ri', 0x61: 'li',
};
const _consonants = <int, String>{
  0x15: 'k', 0x16: 'kh', 0x17: 'g', 0x18: 'gh', 0x19: 'n', 0x1a: 'ch', 0x1b: 'chh', 0x1c: 'j', 0x1d: 'jh', 0x1e: 'n',
  0x1f: 't', 0x20: 'th', 0x21: 'd', 0x22: 'dh', 0x23: 'n', 0x24: 't', 0x25: 'th', 0x26: 'd', 0x27: 'dh', 0x28: 'n',
  0x29: 'n', 0x2a: 'p', 0x2b: 'ph', 0x2c: 'b', 0x2d: 'bh', 0x2e: 'm', 0x2f: 'y', 0x30: 'r', 0x31: 'r', 0x32: 'l',
  0x33: 'l', 0x34: 'l', 0x35: 'v', 0x36: 'sh', 0x37: 'sh', 0x38: 's', 0x39: 'h',
  0x58: 'q', 0x59: 'kh', 0x5a: 'g', 0x5b: 'z', 0x5c: 'd', 0x5d: 'rh', 0x5e: 'f', 0x5f: 'y',
};
const _signs = <int, String>{
  0x3e: 'a', 0x3f: 'i', 0x40: 'i', 0x41: 'u', 0x42: 'u', 0x43: 'ri', 0x44: 'ri', 0x45: 'e', 0x46: 'e', 0x47: 'e',
  0x48: 'ai', 0x49: 'o', 0x4a: 'o', 0x4b: 'o', 0x4c: 'au', 0x62: 'li', 0x63: 'li',
};
const _marks = <int, String>{0x01: 'n', 0x02: 'n', 0x03: 'h', 0x70: 'n'}; // 0x70: Gurmukhi tippi
const _virama = 0x4d;
const _urdu = <String, String>{
  'ا': 'a', 'آ': 'a', 'ب': 'b', 'پ': 'p', 'ت': 't', 'ٹ': 't', 'ث': 's', 'ج': 'j', 'چ': 'ch', 'ح': 'h', 'خ': 'kh', 'د': 'd',
  'ڈ': 'd', 'ذ': 'z', 'ر': 'r', 'ڑ': 'r', 'ز': 'z', 'ژ': 'zh', 'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'z', 'ط': 't', 'ظ': 'z',
  'ع': '', 'غ': 'gh', 'ف': 'f', 'ق': 'q', 'ک': 'k', 'ك': 'k', 'گ': 'g', 'ل': 'l', 'م': 'm', 'ن': 'n', 'ں': 'n', 'و': 'o',
  'ہ': 'h', 'ه': 'h', 'ھ': 'h', 'ء': '', 'ی': 'i', 'ي': 'i', 'ے': 'e', 'ۓ': 'e',
};

int _offsetOf(int cp) => cp >= 0x0900 && cp <= 0x0d7f ? cp & 0x7f : -1;

/// A Latin spelling of text in Indian scripts ("राजेश पाटील" → "rajesh patil"); Latin passes through, lower case.
String toLatin(String input) {
  final out = StringBuffer();
  final cps = input.runes.toList();
  int off(int k) => k >= 0 && k < cps.length ? _offsetOf(cps[k]) : -1;
  bool endsVowel() => RegExp(r'[aeiou]$').hasMatch(out.toString());
  for (var i = 0; i < cps.length; i++) {
    final cp = cps[i];
    final o = _offsetOf(cp);
    if (o < 0) {
      final ch = String.fromCharCode(cp);
      if (_urdu.containsKey(ch)) {
        out.write(_urdu[ch]);
      } else if ((cp >= 0x0660 && cp <= 0x0669) || (cp >= 0x06f0 && cp <= 0x06f9)) {
        out.write((cp & 0xf) % 10);
      } else {
        out.write(ch);
      }
      continue;
    }
    if (o >= 0x66 && o <= 0x6f) {
      out.write(o - 0x66); // native digits
    } else if (_vowels.containsKey(o)) {
      out.write(_vowels[o]);
    } else if (_consonants.containsKey(o)) {
      final before = endsVowel();
      out.write(_consonants[o]);
      // the inherent "a", unless a vowel sign or virama follows, or the word ends here
      final nukta = off(i + 1) == 0x3c;
      final a = nukta ? i + 2 : i + 1;
      final ao = off(a);
      final endsWord = ao < 0 || ao == 0x64 || ao == 0x65;
      // a word ending in a cluster with r, y or v keeps its "a" (महाराष्ट्र maharashtra, मिश्र mishra)
      final inCluster = off(i - 1) == _virama && (o == 0x30 || o == 0x2f || o == 0x35);
      // mid-word "a" before a syllable with its own vowel is not spoken (कमला kamla, गुरप्रीत gurprit)
      final nextHasVowel = _consonants.containsKey(ao) &&
          (_signs.containsKey(off(a + 1)) || (off(a + 1) == _virama && _consonants.containsKey(off(a + 2)) && off(a + 3) >= 0 && off(a + 3) != 0x64));
      if (_marks.containsKey(ao)) {
        out.write('a');
      } else if (endsWord) {
        if (inCluster) out.write('a');
      } else if (!(_signs.containsKey(ao) || ao == _virama) && !(before && nextHasVowel)) {
        out.write('a');
      }
      if (nukta) i++;
    } else if (_signs.containsKey(o)) {
      out.write(_signs[o]);
    } else if (_marks.containsKey(o)) {
      out.write(_marks[o]);
    } else if (o == 0x64 || o == 0x65) {
      out.write(' '); // danda
    }
  }
  return out.toString().toLowerCase();
}

/// Lowercase letters and digits for a page link, from a name in any script.
String linkSlug(String name, [int max = 20]) {
  final s = toLatin(name).replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return s.length > max ? s.substring(0, max) : s;
}

/// The first letter of a word as people see it: a whole letter with its vowel sign in Indian scripts (रा, not र).
String firstLetter(String w) => w.characters.isEmpty ? '' : w.characters.first;
