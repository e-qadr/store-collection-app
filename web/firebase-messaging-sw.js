/*
 * FCM background notifications for the browser application. The Firebase
 * configuration below is public client configuration, not an Admin key.
 */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBs5cOHbWHSXprL_DnG8ik3cnm1PNqEp4U',
  authDomain: 'store-collection-app.firebaseapp.com',
  projectId: 'store-collection-app',
  storageBucket: 'store-collection-app.firebasestorage.app',
  messagingSenderId: '385756153909',
  appId: '1:385756153909:web:46506ba1eeb65987f8097c',
});

firebase.messaging();
