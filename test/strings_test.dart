import 'package:chameleon_cli/l10n/strings.dart';
import 'package:chameleon_cli/protocol/key_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Turkish table covers every English key', () {
    final missing = Strings.en.keys.where((key) => !Strings.tr.containsKey(key)).toList();
    expect(missing, isEmpty, reason: 'Missing Turkish translations: $missing');
  });

  test('placeholder substitution works', () {
    expect(Strings.get('en', 'slotActions', {'slot': 3}), 'Slot 3 actions');
    expect(Strings.get('tr', 'slotActions', {'slot': 3}), 'Slot 3 işlemleri');
  });

  test('48-bit key conversion is big endian', () {
    expect(KeyRecovery.keyHex(0xA0A1A2A3A4A5), 'A0A1A2A3A4A5');
    expect(KeyRecovery.keyFromInt(0x010203040506), [1, 2, 3, 4, 5, 6]);
  });
}
