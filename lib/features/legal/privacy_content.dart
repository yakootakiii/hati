/// Hati's Privacy Notice (DECISIONS D-63), under the Data Privacy Act of 2012
/// (Republic Act No. 10173).
///
/// Written from what the app actually stores — see the tables in
/// supabase/migrations — so keep it in step when a feature collects something
/// new.
library;

import 'legal_document.dart';
import 'terms_content.dart' show TermsParty;

export 'legal_document.dart';

const String kPrivacyEffectiveDate = '5 November 2026';

const List<String> kPrivacySummary = [
  'We collect only what Hati needs to split bills: your account, the bills '
      'and payments you record, and the payment details you choose to add.',
  'The people in your groups see your name, photo, payment details, QR '
      'codes, and what you share in those groups. Nobody else does.',
  'We do not sell your information, show ads, or use third-party analytics.',
  'You can delete your account in the app at any time, under Profile.',
];

const List<LegalSection> kPrivacySections = [
  LegalSection('1. Who we are', [
    LegalParagraph(
      'Hati is operated by ${TermsParty.operator}, the personal information '
      'controller for the information described here. Our data protection '
      'contact is ${TermsParty.operator}, at ${TermsParty.email}.',
    ),
    LegalParagraph(
      'This notice explains how we collect, use, share, keep and protect your '
      'personal information, in line with the Data Privacy Act of 2012 '
      '(Republic Act No. 10173), its implementing rules, and issuances of '
      'the National Privacy Commission.',
    ),
  ]),
  LegalSection('2. What we collect', [
    LegalParagraph('Information you give us:'),
    LegalBullets([
      'Account details: your email address and password (stored only in '
          'hashed form), or, if you sign in with Google, the name, email '
          'address and profile picture link Google shares with us.',
      'Profile: your display name and, if you add one, a profile photo.',
      'Payment methods: the wallet or bank, account name, account or mobile '
          'number, and QR code images you choose to add.',
      'Bills and settlements: group names, bill titles, notes, amounts, '
          'dates, splits, item lists, receipt photos, payment method, '
          'reference numbers and payment screenshots.',
      'Comments you post on bills.',
    ]),
    LegalParagraph('Information created as you use Hati:'),
    LegalBullets([
      'Group membership, invitations, activity history and in-app '
          'notifications.',
      'Your notification settings, and — if you allow notifications — a '
          'device token so we can send them to your phone.',
      'The version of the Terms and Conditions you agreed to.',
    ]),
    LegalParagraph(
      'Your light or dark mode setting stays on your phone. Hati does not ask '
      'for government IDs, your location, or your contacts, and does not '
      'collect information about other apps on your phone. Please do not '
      'upload images of IDs or other documents Hati does not need.',
    ),
  ]),
  LegalSection('3. Why we use it', [
    LegalBullets([
      'To create and secure your account and sign you in.',
      'To record bills, work out shares, and show who has paid.',
      'To show your payment details and QR codes to the people who owe you, '
          'so they can pay you.',
      'To send the notifications you have switched on, such as a new bill, '
          'a payment to confirm, or a reminder.',
      'To keep Hati working, investigate problems, and prevent misuse.',
      'To comply with the law and respond to lawful requests from '
          'authorities.',
    ]),
    LegalParagraph(
      'We process your information because it is needed to provide Hati '
      'under the Terms you agreed to, because you consent (for example, to '
      'notifications or to adding payment details), and for our legitimate '
      'interest in keeping Hati secure — the grounds allowed by Section 12 '
      'of the Data Privacy Act.',
    ),
  ]),
  LegalSection('4. Who can see it', [
    LegalParagraph(
      'The members of each group you belong to can see your display name, '
      'profile photo, payment methods and QR codes, and the bills, payments, '
      'payment screenshots, receipts and comments shared in that group. '
      'People outside your groups cannot, except that anyone who can invite '
      'others to a group can search for you by your display name or your '
      'exact email address — the search shows your name, never your email.',
    ),
    LegalParagraph(
      'We use these service providers to run Hati. They process information '
      'only for us, under their own security and privacy commitments:',
    ),
    LegalBullets([
      'Supabase — the database, sign-in and file storage behind Hati.',
      'Google — sign-in with Google, and Firebase Cloud Messaging to deliver '
          'notifications to your phone.',
    ]),
    LegalParagraph(
      'We do not sell, rent or trade your personal information, and we do not '
      'share it with advertisers. Opening a wallet app from Hati only opens '
      'that app — Hati sends it nothing. We may disclose information when the '
      'law requires it, such as under a court order.',
    ),
  ]),
  LegalSection('5. Where it is kept', [
    LegalParagraph(
      'Our service providers may store and process your information on '
      'servers outside the Philippines. Where they do, we rely on their '
      'contractual and security commitments so that your information keeps a '
      'level of protection consistent with the Data Privacy Act.',
    ),
  ]),
  LegalSection('6. How long we keep it', [
    LegalParagraph(
      'We keep your information while your account is open. When you delete '
      'your account:',
    ),
    LegalBullets([
      'your sign-in details, profile photo, payment methods and QR codes, '
          'device tokens, notifications and settings are deleted;',
      'your name is replaced with "Deleted user" everywhere it appears; and',
      'bills, payments, receipts, payment screenshots and comments you shared '
          'stay in your groups, because they are part of the other members\' '
          'records too — but they no longer identify you by name.',
    ]),
    LegalParagraph(
      'Copies may remain in our providers\' backups for a limited time until '
      'they are overwritten, and we keep information longer only where the '
      'law requires it.',
    ),
  ]),
  LegalSection('7. How we protect it', [
    LegalBullets([
      'Information travels between your phone and our servers encrypted.',
      'Passwords are stored hashed, never in readable form.',
      'Database rules let each person reach only their own information and '
          'that of the groups they belong to.',
      'Photos, QR codes and screenshots are kept in private storage and '
          'shown through links that expire.',
    ]),
    LegalParagraph(
      'No system is perfectly secure. If a breach puts your information at '
      'real risk, we will notify the National Privacy Commission and you as '
      'the law requires.',
    ),
  ]),
  LegalSection('8. Your rights', [
    LegalParagraph('Under the Data Privacy Act you have the right to:'),
    LegalBullets([
      'be informed about how your information is processed;',
      'access the information we hold about you;',
      'correct information that is wrong or out of date — most of it you can '
          'edit yourself in the app;',
      'object to processing, and withdraw consent you have given — for '
          'example by turning notifications off;',
      'have your information erased or blocked — you can delete your account '
          'under Profile → Delete account;',
      'receive your information in a commonly used electronic format '
          '(data portability);',
      'be compensated for damages caused by unlawful processing; and',
      'file a complaint with the National Privacy Commission '
          '(privacy.gov.ph).',
    ]),
    LegalParagraph(
      'To use any of these rights, write to ${TermsParty.email}. We may ask '
      'you to confirm your identity first.',
    ),
  ]),
  LegalSection('9. Children', [
    LegalParagraph(
      'Hati is for people 18 and over, or younger users with the consent and '
      'supervision of a parent or guardian. If you believe a child has given '
      'us information without that consent, contact us and we will delete it.',
    ),
  ]),
  LegalSection('10. Changes to this notice', [
    LegalParagraph(
      'If we change how we handle your information, we will update this '
      'notice and, where the change is significant, tell you in the app '
      'before it takes effect.',
    ),
  ]),
  LegalSection('11. Contact us', [
    LegalParagraph('${TermsParty.operator}\n${TermsParty.email}'),
  ]),
];

const LegalDocument kPrivacyNotice = LegalDocument(
  title: 'Privacy Notice',
  effectiveDate: kPrivacyEffectiveDate,
  summary: kPrivacySummary,
  sections: kPrivacySections,
);
