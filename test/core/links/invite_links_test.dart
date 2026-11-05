import 'package:flutter_test/flutter_test.dart';
import 'package:hati/core/links/invite_links.dart';
import 'package:hati/features/groups/domain/group_models.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';

void main() {
  group('inviteTokenFrom (DECISIONS D-69)', () {
    test('reads the shared link', () {
      expect(
        inviteTokenFrom(Uri.parse('https://hati-a1a23.web.app/join/abc_123-X')),
        'abc_123-X',
      );
    });

    test("reads the invite page's button link", () {
      expect(
        inviteTokenFrom(Uri.parse('com.hati.hati://join/abc123')),
        'abc123',
      );
    });

    test('ignores sign-in callbacks, other sites and other paths', () {
      for (final link in [
        'com.hati.hati://auth-callback?code=xyz',
        'https://example.com/join/abc123',
        'https://hati-a1a23.web.app/privacy',
        'https://hati-a1a23.web.app/join/',
        'https://hati-a1a23.web.app/join/abc/extra',
        'https://hati-a1a23.web.app/join/abc%3Cscript',
      ]) {
        expect(inviteTokenFrom(Uri.parse(link)), isNull, reason: link);
      }
    });

    test('the links Hati shares are ones it opens', () {
      const link = InviteLink(id: 'i1', token: 'tok123');
      expect(inviteTokenFrom(Uri.parse(link.url)), 'tok123');
    });
  });

  group('opening an invite link', () {
    testWidgets('a link that arrives opens the join screen', (tester) async {
      final links = FakeLinkSource();
      final harness = await pumpApp(tester, session: signedIn, links: links);

      links.open('https://hati-a1a23.web.app/join/tok123');
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/join/tok123');
    });

    testWidgets('the link Hati was opened with is followed too', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        session: signedIn,
        links: FakeLinkSource(
          launchLink: Uri.parse('https://hati-a1a23.web.app/join/tok123'),
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.router.state.matchedLocation, '/join/tok123');
    });

    testWidgets('signed out, the invite waits for sign-in', (tester) async {
      final links = FakeLinkSource();
      final harness = await pumpApp(tester, links: links);

      links.open('https://hati-a1a23.web.app/join/tok123');
      await tester.pumpAndSettle();
      expect(harness.router.state.matchedLocation, '/welcome');

      harness.auth.signInAs('bea');
      await tester.pumpAndSettle();
      expect(harness.router.state.matchedLocation, '/join/tok123');
    });
  });
}
