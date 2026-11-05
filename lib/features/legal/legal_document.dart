/// The shape of Hati's legal pages — the Terms and the Privacy Notice — so
/// both render the same way from plain data.
library;

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.summary,
    required this.sections,
  });

  final String title;
  final String effectiveDate;

  /// The gist, shown first. The sections are what bind.
  final List<String> summary;
  final List<LegalSection> sections;
}

/// A section: a heading, then paragraphs and bullet lists in order.
class LegalSection {
  const LegalSection(this.title, this.blocks);

  final String title;
  final List<LegalBlock> blocks;
}

sealed class LegalBlock {
  const LegalBlock();
}

class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);
  final String text;
}

class LegalBullets extends LegalBlock {
  const LegalBullets(this.items);
  final List<String> items;
}
