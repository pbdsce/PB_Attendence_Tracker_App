import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isProcessing = false;
  bool _isSuccess = false;
  String _statusMessage = '';

  final Set<String> _processedParticipantIds = {};
  final Set<String> _processedEmails = {};

  final List<String> _requiredFields = [
    'participant_name',
    'participant_email',
    'participant_id',
    'event_name'
  ];

  @override
  void initState() {
    super.initState();
    _loadProcessedIdsAndEmails();
  }

  Future<void> _loadProcessedIdsAndEmails() async {
    try {

      final QuerySnapshot querySnapshot = await _firestore
          .collection('Main')
          .orderBy('created_at', descending: true)
          .limit(10) //10 most recent events
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['attended'] != null) {
          final attended = List<Map<String, dynamic>>.from(data['attended']);

          for (var record in attended) {
            _processedParticipantIds.add(record['participant_id']);
            _processedEmails.add(record['participant_email']);
          }
        }
      }
    } catch (e) {
      print('Error loading processed IDs and emails: $e');
    }
  }

  Future<Map<String, bool>> _checkForExistingAttendance(
      String eventName, String participantEmail, String participantId) async {
    try {
      final docRef = _firestore.collection('Main').doc(eventName);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        return {
          'emailExists': false,
          'participantIdExists': false,
        };
      }

      final data = docSnapshot.data() as Map<String, dynamic>;
      final attended = List<Map<String, dynamic>>.from(data['attended'] ?? []);

      bool emailExists = attended
          .any((record) => record['participant_email'] == participantEmail);
      bool participantIdExists =
          attended.any((record) => record['participant_id'] == participantId);

      return {
        'emailExists': emailExists,
        'participantIdExists': participantIdExists,
      };
    } catch (e) {
      print('Error checking for existing attendance: $e');
      return {
        'emailExists': false,
        'participantIdExists': false,
      };
    }
  }

  void _validateRequiredFields(Map<String, dynamic> data) {
    for (var field in _requiredFields) {
      if (!data.containsKey(field) ||
          data[field] == null ||
          data[field].toString().trim().isEmpty) {
        throw Exception('Missing or empty required field: $field');
      }
    }
  }

  Future<void> _updateFirebaseAttendance(
    Map<String, dynamic> attendeeData) async {
  try {
    _validateRequiredFields(attendeeData);

    String eventName = attendeeData['event_name'];
    String participantEmail = attendeeData['participant_email'];
    String participantId = attendeeData['participant_id'];

    
    await _firestore.runTransaction((transaction) async {
      final docRef = _firestore.collection('Main').doc(eventName);
      final docSnapshot = await transaction.get(docRef);
      
      //current timestamp
      final now = DateTime.now().toIso8601String();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        final attended =
            List<Map<String, dynamic>>.from(data['attended'] ?? []);

        if (attended.any((record) =>
            record['participant_email'] == participantEmail ||
            record['participant_id'] == participantId)) {
          throw Exception("$participantId has already been registered");
        }

        //add new attendance record
        final attendanceRecord = Map<String, dynamic>.from(attendeeData);
        attendanceRecord['check_in_time'] = now;

        //update document with new attendance record and latest_checkin
        transaction.update(docRef, {
          'attended': FieldValue.arrayUnion([attendanceRecord]),
          'latest_checkin': now  // Add this field for efficient sorting
        });
      } else {
        //creating new doc if it doesn't exist
        final attendanceRecord = Map<String, dynamic>.from(attendeeData);
        attendanceRecord['check_in_time'] = now;

        transaction.set(docRef, {
          'event_name': eventName,
          'created_at': FieldValue.serverTimestamp(),
          'latest_checkin': now,  // Include the latest_checkin field
          'attended': [attendanceRecord]
        });
      }
    });

    setState(() {
      _isSuccess = true;
      _statusMessage = 'Attendance marked successfully';
      _processedParticipantIds.add(participantId);
      _processedEmails.add(participantEmail);
    });
  } catch (e) {
    print('Firebase error: $e');
    setState(() {
      _isSuccess = false;
      _statusMessage = e.toString();
    });
    throw e;
  }
}

  Future<void> _processScannedCode(String? rawValue) async {
    if (rawValue == null || rawValue.isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final decodedBytes = base64.decode(rawValue);
      final decodedString = utf8.decode(decodedBytes);
      final decodedData = jsonDecode(decodedString);


      final String participantEmail = decodedData['participant_email'];
      final String participantId = decodedData['participant_id'];
      final String participantName = decodedData['participant_name'];

      if (participantEmail.isEmpty ||
          participantId.isEmpty ||
          participantName.isEmpty) {
        throw Exception('Missing required fields in QR code');
      }

      bool emailProcessed = _processedEmails.contains(participantEmail);
      bool participantProcessed =
          _processedParticipantIds.contains(participantId);

      if (emailProcessed || participantProcessed) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 10),
                  Text('Duplicate Scan'),
                ],
              ),
              content: Text(
                  "participant $participantId/$participantName already scanned with email $participantEmail"),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _isProcessing = false;
                    });
                  },
                ),
              ],
            );
          },
        );
        return;
      }

      //confirmationdialogebox

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 10),
                Text('Confirm Attendance'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.blue),
                  title: Text(decodedData['participant_name']),
                  subtitle: const Text('Participant Name'),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.confirmation_number, color: Colors.blue),
                  title: Text(participantId),
                  subtitle: const Text('Participant ID'),
                ),
                ListTile(
                  leading: const Icon(Icons.email, color: Colors.blue),
                  title: Text(participantEmail),
                  subtitle: const Text('Email'),
                ),
                ListTile(
                  leading: const Icon(Icons.event, color: Colors.blue),
                  title: Text(decodedData['event_name']),
                  subtitle: const Text('Event'),
                ),
                if (decodedData['department'] != null)
                  ListTile(
                    leading: const Icon(Icons.business, color: Colors.blue),
                    title: Text(decodedData['department']),
                    subtitle: const Text('Department'),
                  ),
                if (decodedData['role'] != null)
                  ListTile(
                    leading: const Icon(Icons.work, color: Colors.blue),
                    title: Text(decodedData['role']),
                    subtitle: const Text('Role'),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isProcessing = false;
                  });
                },
              ),
              TextButton(
                child: const Text('Confirm'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _sendDataAndShowResult(decodedData);
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error processing QR: $e');
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 10),
                Text('Error'),
              ],
            ),
            content: Text('Error processing QR code: $e'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isProcessing = false;
                  });
                },
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _sendDataAndShowResult(Map<String, dynamic> decodedData) async {
    try {
      await _updateFirebaseAttendance(decodedData);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  _isSuccess ? Icons.check_circle : Icons.cancel,
                  color: _isSuccess ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(_isSuccess ? 'Attendance Marked' : 'Failed'),
              ],
            ),
            content: Text(_isSuccess
                ? 'Successfully marked attendance for ${decodedData['participant_name']}'
                : 'Failed to mark attendance: $_statusMessage'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isProcessing = false;
                  });
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 10),
                Text('Firebase Error'),
              ],
            ),
            content: Text('Failed to update attendance: $e'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _isProcessing = false;
                  });
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: MobileScanner(
              controller: MobileScannerController(
                detectionSpeed: DetectionSpeed.normal,
                facing: CameraFacing.back,
                
              ),
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && !_isProcessing) {
                  
                  
                  _processScannedCode(barcodes.first.rawValue);
                  
                }
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Position QR code in the camera view',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
