import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/input.dart';

void main() {
  test('plain URL', () {
    final i = classifyInput('  https://example.com/a?b=1 ');
    expect(i!.url, 'https://example.com/a?b=1');
  });

  test('shared "title + URL" is a URL', () {
    final i = classifyInput('Velký článek o něčem\nhttps://example.com/x.');
    expect(i!.url, 'https://example.com/x');
  });

  test('long text with a link is text', () {
    final long = '${'slovo ' * 60}https://example.com';
    expect(classifyInput(long)!.isUrl, isFalse);
  });

  test('text and blank', () {
    expect(classifyInput('Jen text bez odkazu')!.text, 'Jen text bez odkazu');
    expect(classifyInput('   '), isNull);
  });
}
