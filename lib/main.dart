import 'package:flutter/material.dart';
import 'package:phone_state/phone_state.dart';
import 'package:telephony/telephony.dart';

final Telephony telephony = Telephony.instance;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = "Waiting for calls...";

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _listenToCalls();
  }

  // Request permissions for phone and SMS
  Future<void> _initPermissions() async {
    bool? sms = await telephony.requestSmsPermissions;
    bool? phone = await telephony.requestPhonePermissions;
    debugPrint("SMS Permission: $sms, Phone Permission: $phone");
  }

  // Listen to incoming calls
  void _listenToCalls() {
    PhoneState.stream.listen((event) async {
      debugPrint("Incoming call event: ${event?.number}, status: ${event?.status}");

      if (event != null && event.status == PhoneStateStatus.CALL_INCOMING) {
        setState(() {
          _status = "Incoming call from: ${event.number ?? "Unknown"}";
        });

        // Send auto-reply SMS
        if (event.number != null) {
          await telephony.sendSms(
            to: event.number!,
            message: "Sorry, I can’t take calls right now. Harsh I’ll call you later.",
          );
          debugPrint("Auto-reply SMS sent to ${event.number}");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Auto Reply on Incoming Call")),
        body: Center(child: Text(_status)),
      ),
    );
  }
}
