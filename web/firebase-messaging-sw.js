// Hati — background notifications for the web app (DECISIONS D-72).
//
// Receives pushes while Hati is closed. FCM shows the notification itself,
// and its webpush link (set by send-push) opens the right page when tapped.
// The version matches firebase_core_web's supportedFirebaseJsSdkVersion.
// This config is public by design: every browser that loads Hati reads it.

importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBBumOcx3lkFK6hh0ukL6Qw_k0OjppN8qM',
  authDomain: 'hati-a1a23.firebaseapp.com',
  projectId: 'hati-a1a23',
  storageBucket: 'hati-a1a23.firebasestorage.app',
  messagingSenderId: '200938891937',
  appId: '1:200938891937:web:64c509229591399adedee0',
});

firebase.messaging();
