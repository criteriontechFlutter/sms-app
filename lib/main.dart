import 'package:flutter/material.dart';
import 'package:phone_state/phone_state.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Telephony telephony = Telephony.instance;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Reply App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AutoReplyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AutoReplyHomePage extends StatefulWidget {
  const AutoReplyHomePage({super.key});

  @override
  State<AutoReplyHomePage> createState() => _AutoReplyHomePageState();
}

class _AutoReplyHomePageState extends State<AutoReplyHomePage> {
  String _status = "Initializing...";
  String _lastCallNumber = "";
  DateTime? _lastCallTime;
  bool _isAutoReplyEnabled = true;
  String _autoReplyMessage = "Sorry, I can't take calls right now. I'll call you back later.";
  bool _hasPhonePermission = false;
  bool _hasSmsPermission = false;
  bool _isListening = false;
  final List<CallLog> _callLogs = [];
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initPermissions();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // Load saved settings
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isAutoReplyEnabled = prefs.getBool('auto_reply_enabled') ?? true;
        _autoReplyMessage = prefs.getString('auto_reply_message') ??
            "Sorry, I can't take calls right now. I'll call you back later.";
        _messageController.text = _autoReplyMessage;
      });
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  // Save settings
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_reply_enabled', _isAutoReplyEnabled);
      await prefs.setString('auto_reply_message', _autoReplyMessage);
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }

  // Request and check permissions
  Future<void> _initPermissions() async {
    setState(() {
      _status = "Requesting permissions...";
    });

    try {
      // Request phone permission
      PermissionStatus phoneStatus = await Permission.phone.request();
      _hasPhonePermission = phoneStatus == PermissionStatus.granted;

      // Request SMS permission
      PermissionStatus smsStatus = await Permission.sms.request();
      _hasSmsPermission = smsStatus == PermissionStatus.granted;

      // Also request using telephony package
      bool? smsPermTelephony = await telephony.requestSmsPermissions;
      bool? phonePermTelephony = await telephony.requestPhonePermissions;

      setState(() {
        _hasSmsPermission = _hasSmsPermission || (smsPermTelephony ?? false);
        _hasPhonePermission = _hasPhonePermission || (phonePermTelephony ?? false);
      });

      if (_hasPhonePermission && _hasSmsPermission) {
        _startListening();
      } else {
        setState(() {
          _status = "Permissions required. Please grant phone and SMS permissions.";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error requesting permissions: $e";
      });
      debugPrint("Permission error: $e");
    }
  }

  // Start listening to phone calls
  void _startListening() {
    if (!_hasPhonePermission) {
      setState(() {
        _status = "Phone permission not granted";
      });
      return;
    }

    try {
      PhoneState.stream.listen((event) async {
        await _handlePhoneStateChange(event);
      }, onError: (error) {
        debugPrint("Phone state error: $error");
        setState(() {
          _status = "Error listening to calls: $error";
        });
      });

      setState(() {
        _isListening = true;
        _status = _isAutoReplyEnabled
            ? "Auto-reply is active. Waiting for calls..."
            : "Monitoring calls. Auto-reply is disabled.";
      });
    } catch (e) {
      setState(() {
        _status = "Error starting call listener: $e";
      });
      debugPrint("Listening error: $e");
    }
  }

  // Handle phone state changes
  Future<void> _handlePhoneStateChange(PhoneState? event) async {
    if (event == null) return;

    debugPrint("Phone event: ${event.number}, status: ${event.status}");

    switch (event.status) {
      case PhoneStateStatus.CALL_INCOMING:
        await _handleIncomingCall(event);
        break;
      case PhoneStateStatus.CALL_STARTED:
        setState(() {
          _status = "Call in progress with ${event.number ?? 'Unknown'}";
        });
        break;
      case PhoneStateStatus.CALL_ENDED:
        setState(() {
          _status = _isAutoReplyEnabled
              ? "Auto-reply is active. Waiting for calls..."
              : "Monitoring calls. Auto-reply is disabled.";
        });
        break;
      case PhoneStateStatus.NOTHING:
      // Phone is idle
        break;
    }
  }

  // Handle incoming calls
  Future<void> _handleIncomingCall(PhoneState event) async {
    final callNumber = event.number ?? "Unknown";
    final callTime = DateTime.now();

    setState(() {
      _status = "Incoming call from: $callNumber";
      _lastCallNumber = callNumber;
      _lastCallTime = callTime;
    });

    // Add to call log
    _addToCallLog(callNumber, callTime, "Incoming");

    // Send auto-reply SMS if enabled and we have permission
    if (_isAutoReplyEnabled && _hasSmsPermission && event.number != null) {
      await _sendAutoReplySMS(event.number!);
    }
  }

  // Send auto-reply SMS
  Future<void> _sendAutoReplySMS(String phoneNumber) async {
    try {
      await telephony.sendSms(
        to: phoneNumber,
        message: _autoReplyMessage,
      );

      setState(() {
        _status = "Auto-reply sent to $phoneNumber";
      });

      _addToCallLog(phoneNumber, DateTime.now(), "SMS Sent");
      debugPrint("Auto-reply SMS sent to $phoneNumber");

      // Show success snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Auto-reply sent to $phoneNumber"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = "Failed to send SMS: $e";
      });

      debugPrint("SMS send error: $e");

      // Show error snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to send SMS: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Add entry to call log
  void _addToCallLog(String number, DateTime time, String type) {
    setState(() {
      _callLogs.insert(0, CallLog(number, time, type));
      if (_callLogs.length > 50) { // Keep only last 50 entries
        _callLogs.removeRange(50, _callLogs.length);
      }
    });
  }

  // Toggle auto-reply
  void _toggleAutoReply(bool value) {
    setState(() {
      _isAutoReplyEnabled = value;
      _status = _isListening
          ? (_isAutoReplyEnabled
          ? "Auto-reply is active. Waiting for calls..."
          : "Monitoring calls. Auto-reply is disabled.")
          : _status;
    });
    _saveSettings();
  }

  // Update auto-reply message
  void _updateAutoReplyMessage() {
    setState(() {
      _autoReplyMessage = _messageController.text.trim();
    });
    _saveSettings();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Auto-reply message updated"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Show message editor dialog
  void _showMessageEditor() {
    _messageController.text = _autoReplyMessage;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Auto-Reply Message"),
        content: TextField(
          controller: _messageController,
          maxLines: 3,
          maxLength: 160,
          decoration: const InputDecoration(
            hintText: "Enter your auto-reply message",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: _updateAutoReplyMessage,
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // Show call log
  void _showCallLog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Call Log"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _callLogs.isEmpty
              ? const Center(child: Text("No calls yet"))
              : ListView.builder(
            itemCount: _callLogs.length,
            itemBuilder: (context, index) {
              final log = _callLogs[index];
              return ListTile(
                title: Text(log.number),
                subtitle: Text(log.type),
                trailing: Text(
                  "${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}",
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auto Reply App"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showCallLog,
            tooltip: "Call Log",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initPermissions,
            tooltip: "Refresh Permissions",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isListening ? Icons.phone_enabled : Icons.phone_disabled,
                          color: _isListening ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Status",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Permissions Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Permissions",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _hasPhonePermission ? Icons.check_circle : Icons.cancel,
                          color: _hasPhonePermission ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text("Phone Permission: ${_hasPhonePermission ? 'Granted' : 'Denied'}"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _hasSmsPermission ? Icons.check_circle : Icons.cancel,
                          color: _hasSmsPermission ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text("SMS Permission: ${_hasSmsPermission ? 'Granted' : 'Denied'}"),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Auto-Reply Settings Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Auto-Reply Settings",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text("Enable Auto-Reply"),
                      subtitle: const Text("Send automatic SMS replies to incoming calls"),
                      value: _isAutoReplyEnabled,
                      onChanged: _toggleAutoReply,
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text("Auto-Reply Message"),
                      subtitle: Text(_autoReplyMessage),
                      trailing: const Icon(Icons.edit),
                      onTap: _showMessageEditor,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Last Call Info (if available)
            if (_lastCallNumber.isNotEmpty)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Last Call",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text("Number: $_lastCallNumber"),
                      if (_lastCallTime != null)
                        Text("Time: ${_lastCallTime!.hour.toString().padLeft(2, '0')}:${_lastCallTime!.minute.toString().padLeft(2, '0')}"),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Call log data class
class CallLog {
  final String number;
  final DateTime time;
  final String type;

  CallLog(this.number, this.time, this.type);
}
