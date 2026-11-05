import 'package:firebase_core/firebase_core.dart';

/// Firebase settings for the web app (DECISIONS D-72), from the "Hati Web" app
/// in the hati-a1a23 project. Public by design — browsers read them — unlike
/// the service-account key, which stays in Supabase secrets.
const FirebaseOptions kFirebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyBBumOcx3lkFK6hh0ukL6Qw_k0OjppN8qM',
  authDomain: 'hati-a1a23.firebaseapp.com',
  projectId: 'hati-a1a23',
  storageBucket: 'hati-a1a23.firebasestorage.app',
  messagingSenderId: '200938891937',
  appId: '1:200938891937:web:64c509229591399adedee0',
);

/// The web push (VAPID) public key, from Firebase → Project settings → Cloud
/// Messaging → Web Push certificates. Passed in from `.env`; without it the
/// web app simply has no push.
const String kFirebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');
