/* eslint-disable no-undef */
// Service worker for Firebase Cloud Messaging on web (must live next to index.html).
// Keep firebase-app / firebase-messaging versions aligned with FlutterFire’s JS SDK.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB2-v9Tj5etvUoj8vGWU6bzvA6ysNWgsME',
  authDomain: 'schoolway-04286806.firebaseapp.com',
  projectId: 'schoolway-04286806',
  storageBucket: 'schoolway-04286806.firebasestorage.app',
  messagingSenderId: '137687591166',
  appId: '1:137687591166:web:9e23518fd76b6db18c9daf',
  measurementId: 'G-GVS8JHPH20',
});

firebase.messaging();
