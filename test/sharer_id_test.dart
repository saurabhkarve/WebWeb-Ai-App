import 'package:flutter_test/flutter_test.dart';
import 'package:webweb_app/contact_sync.dart';

void main() {
  // the server (api/src/routes/service-contacts.ts sharerId) computes the same value for the same number
  test('sharerId matches the server', () {
    expect(ContactSync.sharerId('9822012345'), 'db6f642207d5cf91');
  });
}
