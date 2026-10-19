import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/contact_sync.dart';

bool matches(String saved, String word) => ' ${ContactSync.norm(saved)} '.contains(' ${ContactSync.norm(word)} ');

void main() {
  test('keywords match whole words in any script', () {
    expect(matches('Ramesh Plumber', 'plumber'), isTrue);
    expect(matches('Sai Cab Service', 'cab'), isTrue);
    expect(matches('Jacob', 'cab'), isFalse);
    expect(matches('Dr. Mehta', 'dr'), isTrue);
    expect(matches('Andrew', 'dr'), isFalse);
    expect(matches('AC-repair Sunil', 'ac'), isTrue);
    expect(matches('Isaac', 'ac'), isFalse);
    expect(matches('ABC Pest Control', 'pest control'), isTrue);
    expect(matches('सुनील प्लंबर', 'प्लंबर'), isTrue);
    expect(matches('रिक्षा वाला राजू', 'रिक्षा'), isTrue);
    expect(matches('डॉ. पाटील', 'डॉ'), isTrue);
  });

  test('Indian mobiles in any saved format', () {
    expect(ContactSync.mobile10('+91 98200 12345'), '9820012345');
    expect(ContactSync.mobile10('098200-12345'), '9820012345');
    expect(ContactSync.mobile10('9820012345'), '9820012345');
    expect(ContactSync.mobile10('022 2345 6789'), isNull);
    expect(ContactSync.mobile10('+1 415 555 0100'), isNull);
  });
}
