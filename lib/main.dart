import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBGTxUQbuOtTmwBbH7YYt9ZC2Ct393kRsA",
      authDomain: "uddd-e0e1f.firebaseapp.com",
      databaseURL: "https://uddd-e0e1f-default-rtdb.firebaseio.com",
      projectId: "uddd-e0e1f",
      storageBucket: "uddd-e0e1f.firebasestorage.app",
      messagingSenderId: "99119582981",
      appId: "1:99119582981:web:629bc0e99571f012a5716c",
      measurementId: "G-DXJ96NTL7D",
    ),
  );
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: HomeScreen());
  }
}
