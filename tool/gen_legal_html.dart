// Writes hosting/public/terms.html and privacy.html from the same text the
// app shows (lib/features/legal/), so the web copies can never drift.
//
//   dart run tool/gen_legal_html.dart
//
// Re-run whenever the Terms or the Privacy Notice change, then redeploy
// hosting (DECISIONS D-69).

import 'dart:io';

import 'package:hati/features/legal/privacy_content.dart';
import 'package:hati/features/legal/terms_content.dart';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\n', '<br>');

String _page(LegalDocument doc, String otherHref, String otherTitle) {
  final body = StringBuffer()
    ..writeln('<h1>${_escape(doc.title)}</h1>')
    ..writeln('<p class="muted">Effective ${_escape(doc.effectiveDate)}</p>')
    ..writeln('<div class="card"><strong>In short</strong><ul>');
  for (final line in doc.summary) {
    body.writeln('<li>${_escape(line)}</li>');
  }
  body.writeln('</ul></div>');
  for (final section in doc.sections) {
    body.writeln('<h2>${_escape(section.title)}</h2>');
    for (final block in section.blocks) {
      switch (block) {
        case LegalParagraph(:final text):
          body.writeln('<p>${_escape(text)}</p>');
        case LegalBullets(:final items):
          body.writeln('<ul>');
          for (final item in items) {
            body.writeln('<li>${_escape(item)}</li>');
          }
          body.writeln('</ul>');
      }
    }
  }

  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape(doc.title)} — Hati</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<main>
  <a class="brand" href="/" aria-label="Hati">
    <svg viewBox="0 0 48 48" aria-hidden="true"><path fill="var(--accent)" d="M21.8 7.8a16.4 16.4 0 0 0 0 32.8z"/><path fill="var(--accent)" d="M26.2 3.4a16.4 16.4 0 0 1 0 32.8z"/></svg>
    Hati
  </a>
$body
  <footer>Generated from the text in the Hati app. See also <a href="$otherHref">$otherTitle</a>.</footer>
</main>
</body>
</html>
''';
}

void main() {
  File('hosting/public/terms.html')
      .writeAsStringSync(_page(kTerms, '/privacy', 'Privacy Notice'));
  File('hosting/public/privacy.html')
      .writeAsStringSync(_page(kPrivacyNotice, '/terms', 'Terms and Conditions'));
  stdout.writeln('Wrote hosting/public/terms.html and privacy.html');
}
