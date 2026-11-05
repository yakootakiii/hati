import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/widgets/surfaces.dart';
import 'privacy_content.dart';
import 'terms_content.dart';

/// Terms and Conditions (DECISIONS D-61). Reachable signed in or out, so it
/// can be read before agreeing to it.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalScreen(document: kTerms);
}

/// Privacy Notice (DECISIONS D-63). Reachable signed in or out.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const LegalScreen(document: kPrivacyNotice);
}

/// One legal document: the gist in a box, then the numbered sections, all
/// selectable so a clause can be copied.
class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Effective ${document.effectiveDate}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: kSpace * 2),
                  Container(
                    padding: const EdgeInsets.all(kSpace * 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(kRadiusLg),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('In short', style: theme.textTheme.titleSmall),
                        const SizedBox(height: kSpace),
                        for (final line in document.summary)
                          _Bullet(line, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  for (final section in document.sections) ...[
                    const SizedBox(height: kSpace * 3.5),
                    Semantics(
                      header: true,
                      child: Text(
                        section.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: kSpace),
                    for (final block in section.blocks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: kSpace),
                        child: switch (block) {
                          LegalParagraph(:final text) => Text(
                            text,
                            style: theme.textTheme.bodyMedium,
                          ),
                          LegalBullets(:final items) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final item in items)
                                _Bullet(
                                  item,
                                  style: theme.textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
