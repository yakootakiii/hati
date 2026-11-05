/// Hati's Terms and Conditions (DECISIONS D-61).
///
/// One source for the in-app page. When the text changes in substance, bump
/// [kTermsVersion]: sign-ups record the version they agreed to.
library;

import 'legal_document.dart';

export 'legal_document.dart';

/// The version a user agrees to, stored in their auth metadata at sign-up.
const String kTermsVersion = '2026-11-05';

const String kTermsEffectiveDate = '5 November 2026';

/// Who stands behind Hati: the personal information controller for the
/// Data Privacy Act, and who to write to about the Terms.
abstract final class TermsParty {
  static const String operator = 'Nex';
  static const String email = 'yakokakiiiii@gmail.com';
}

/// The short version shown above the full text. It summarises; the sections
/// below are what bind.
const List<String> kTermsSummary = [
  'Hati only helps you keep track of shared expenses. It never holds, sends '
      'or receives money.',
  'Payments happen in GCash, Maya, your bank or in cash — outside Hati. We '
      'are not responsible if a transfer fails or if someone does not pay.',
  'Debts are between you and the people you split with. Hati does not '
      'collect, guarantee or enforce them.',
  'Your groupmates can see your name, photo, payment details, QR codes and '
      'the payment screenshots you upload.',
];

const List<LegalSection> kTermsSections = [
  LegalSection('1. About these Terms', [
    LegalParagraph(
      'These Terms and Conditions ("Terms") are an agreement between you and '
      '${TermsParty.operator} ("we", "us"), the operator of the Hati '
      'application ("Hati"). By creating an account, signing in with Google, '
      'or using Hati, you agree to these Terms. If you do not agree, do not '
      'use Hati.',
    ),
    LegalParagraph(
      'You accept these Terms electronically. Under the Electronic Commerce '
      'Act of 2000 (Republic Act No. 8792), that acceptance has the same '
      'legal effect as a signed paper agreement.',
    ),
    LegalParagraph(
      'These Terms take effect on $kTermsEffectiveDate (version '
      '$kTermsVersion).',
    ),
  ]),
  LegalSection('2. What Hati is — and is not', [
    LegalParagraph(
      'Hati is a record-keeping tool. It helps groups write down shared '
      'expenses, work out each person\'s share, show where to send payment, '
      'and keep track of who has said they paid.',
    ),
    LegalParagraph('Hati is not, and does not act as:'),
    LegalBullets([
      'a bank, e-money issuer, remittance or money-transfer service, or '
          'payment system operator under the National Payment Systems Act '
          '(Republic Act No. 11127);',
      'a party to any payment between users;',
      'an escrow agent, collection agency, guarantor or lender; or',
      'a mediator or arbiter of disputes between users.',
    ]),
    LegalParagraph(
      'Hati never holds, receives, transfers or has access to your money or '
      'to your e-wallet or bank accounts.',
    ),
  ]),
  LegalSection('3. Who can use Hati', [
    LegalBullets([
      'You must be at least 18 years old, or have the consent and supervision '
          'of a parent or legal guardian who agrees to these Terms for you.',
      'The information you give us must be true, and you must keep it up to '
          'date.',
      'Your account is for you alone. Keep your password private; you are '
          'responsible for what happens under your account.',
      'Tell us at ${TermsParty.email} if you think someone else has accessed '
          'your account.',
    ]),
  ]),
  LegalSection('4. Payments happen outside Hati', [
    LegalParagraph(
      'When you settle up, you pay the other person directly through a '
      'service of your choice — for example GCash, Maya, GoTyme, ShopeePay, '
      'GrabPay, Coins.ph, PalawanPay, a bank, or cash. Those services are '
      'run by third parties under their own terms, fees and limits, which '
      'Hati does not control.',
    ),
    LegalBullets([
      'Payment details and QR codes in Hati are entered by the users who own '
          'them. Check the name and number in your wallet before you send '
          'money.',
      'Marking a share as paid, and attaching a screenshot, only records what '
          'you say happened. It is not proof that money arrived.',
      'A share is settled in Hati only when the person who paid the bill '
          'confirms they received the money.',
      'Balances in Hati are calculated from what users enter. They are a '
          'record to help you keep track — not a bill, demand, or legal '
          'determination of what anyone owes.',
    ]),
  ]),
  LegalSection('5. No liability for transactions or unpaid settlements', [
    LegalParagraph(
      'Because payments and debts are entirely between users and outside '
      'Hati, we are not liable for, and make no promise about:',
    ),
    LegalBullets([
      'any transfer that fails, is delayed, reversed, charged a fee, sent to '
          'the wrong person or account, or made in the wrong amount;',
      'wrong, outdated or fraudulent payment details or QR codes entered by '
          'any user;',
      'outages, errors, limits or decisions of any e-wallet, bank or other '
          'payment service;',
      'any share or debt that is not paid, paid late, paid partly, disputed '
          'or refused;',
      'false claims of payment, fake or altered screenshots, or a payer '
          'wrongly confirming or rejecting a payment; and',
      'any disagreement between users about what was spent, who owes what, '
          'or whether a payment was made.',
    ]),
    LegalParagraph(
      'Any obligation to pay exists only between the users concerned. Hati '
      'does not collect, enforce or guarantee it. Users may settle disputes '
      'among themselves through the usual channels — including barangay '
      'conciliation under the Katarungang Pambarangay law, where it applies, '
      'or the courts — and Hati is not a party to them.',
    ),
  ]),
  LegalSection('6. Your content and conduct', [
    LegalParagraph(
      'You keep ownership of what you add to Hati — bills, comments, '
      'receipts, payment details, QR codes and screenshots ("your content"). '
      'You give us permission to store it, process it and show it to the '
      'members of the groups you share it with, only to run Hati.',
    ),
    LegalParagraph('You agree not to:'),
    LegalBullets([
      'enter false bills or payment details, or use Hati to deceive or '
          'defraud anyone;',
      'upload anything you have no right to share, or anything unlawful, '
          'obscene, defamatory or harassing;',
      'use Hati in connection with money laundering, terrorist financing, '
          'gambling or any other activity prohibited by Philippine law, '
          'including the Anti-Money Laundering Act (Republic Act No. 9160, '
          'as amended);',
      'interfere with Hati, try to access other people\'s data, or copy, '
          'scrape or reverse-engineer the service.',
    ]),
  ]),
  LegalSection('7. Privacy', [
    LegalParagraph(
      'We process personal information in line with the Data Privacy Act of '
      '2012 (Republic Act No. 10173) and its implementing rules. Members of '
      'your groups can see your display name, profile photo, payment methods '
      'and QR codes, and the bills, comments and payment screenshots shared '
      'in those groups.',
    ),
    LegalParagraph(
      'You have the right to be informed, to access, correct and object to '
      'the processing of your personal information, to have it erased or '
      'blocked, and to data portability. How we handle your information is '
      'set out in full in the Privacy Notice. To use these rights, write to '
      '${TermsParty.email}. You may also file a complaint with the National '
      'Privacy Commission.',
    ),
    LegalParagraph(
      'Only add another person\'s details — such as their name in a bill — '
      'where you are entitled to do so.',
    ),
  ]),
  LegalSection('8. The service', [
    LegalParagraph(
      'Hati is provided free of charge, "as is" and "as available". We work '
      'to keep it accurate and running, but we do not promise that it will '
      'always be available, error-free or secure, or that its calculations '
      'will suit every situation. Check your bills and shares before you '
      'rely on them.',
    ),
    LegalParagraph(
      'We may change, suspend or stop any part of Hati. Where a change '
      'significantly affects you, we will give reasonable notice in the app '
      'where we can.',
    ),
  ]),
  LegalSection('9. Limits on our liability', [
    LegalParagraph(
      'To the fullest extent allowed by Philippine law, we are not liable for '
      'any indirect, incidental or consequential loss, or for lost money, '
      'profits or data, arising from your use of Hati or from the acts of '
      'other users or third-party payment services. Our total liability to '
      'you for any claim relating to Hati is limited to the amount you have '
      'paid us for Hati in the twelve months before the claim — which, while '
      'Hati is free, is nothing.',
    ),
    LegalParagraph(
      'Nothing in these Terms limits or excludes liability that cannot be '
      'limited or excluded under Philippine law, including liability for '
      'fraud, bad faith or gross negligence (Articles 1170 to 1173 of the '
      'Civil Code), or your rights under the Consumer Act of the Philippines '
      '(Republic Act No. 7394) and the Data Privacy Act of 2012.',
    ),
  ]),
  LegalSection('10. Your responsibility to us', [
    LegalParagraph(
      'If you break these Terms or the law in using Hati, and a claim is '
      'brought against us because of it, you agree to answer for the loss '
      'and reasonable costs that result, to the extent the law allows.',
    ),
  ]),
  LegalSection('11. Suspension and closing your account', [
    LegalParagraph(
      'We may suspend or close an account that breaks these Terms or is used '
      'unlawfully, after notice where it is reasonable to give it. You may '
      'stop using Hati at any time, and delete your account yourself under '
      'Profile → Delete account, or by writing to ${TermsParty.email}.',
    ),
    LegalParagraph(
      'Records you share with a group, such as bills and payments, are part '
      'of the other members\' history too. When you leave or delete your '
      'account, we may keep them in a form that no longer identifies you, '
      'or as long as the law requires.',
    ),
  ]),
  LegalSection('12. Changes to these Terms', [
    LegalParagraph(
      'We may update these Terms. If a change is significant, we will tell '
      'you in the app before it takes effect. If you keep using Hati after '
      'that, you accept the updated Terms; if you do not agree, you may stop '
      'using Hati and close your account.',
    ),
  ]),
  LegalSection('13. Governing law and disputes', [
    LegalParagraph(
      'These Terms are governed by the laws of the Republic of the '
      'Philippines. If a dispute arises between you and us, we will first try '
      'to settle it amicably — contact us at ${TermsParty.email}. If that '
      'fails, it will be brought before the proper courts of the '
      'Philippines, without prejudice to any right you have to file '
      'a complaint with a government agency such as the Department of Trade '
      'and Industry or the National Privacy Commission, or to use the small '
      'claims procedure.',
    ),
  ]),
  LegalSection('14. General', [
    LegalBullets([
      'If any part of these Terms is found invalid, the rest stays in effect.',
      'If we do not enforce a term right away, we have not given up the '
          'right to enforce it later.',
      'These Terms are the whole agreement between you and us about Hati.',
      'Where anything in these Terms is unclear, it will be read in the way '
          'most favourable to you, consistent with Article 1377 of the Civil '
          'Code.',
    ]),
  ]),
  LegalSection('15. Contact us', [
    LegalParagraph('${TermsParty.operator}\n${TermsParty.email}'),
  ]),
];

const LegalDocument kTerms = LegalDocument(
  title: 'Terms and Conditions',
  effectiveDate: kTermsEffectiveDate,
  summary: kTermsSummary,
  sections: kTermsSections,
);
