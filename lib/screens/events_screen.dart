import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool _showAllEvents = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showAllEvents ? 'All Events' : 'Recent Event'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Main').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No events found'),
            );
          }

          final documents = snapshot.data!.docs;
          documents.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final String? aLatestTime = aData['latest_checkin'] as String?;
            final String? bLatestTime = bData['latest_checkin'] as String?;

            if (aLatestTime == null) return 1;
            if (bLatestTime == null) return -1;
            return bLatestTime.compareTo(aLatestTime); // Descending order
          });

          //show most recent event or all events based on state
          final displayDocuments =
              _showAllEvents ? documents : documents.take(1).toList();

          return ListView.builder(
            itemCount: displayDocuments.length,
            itemBuilder: (context, index) {
              final eventDoc = displayDocuments[index];
              final eventData = eventDoc.data() as Map<String, dynamic>;
              final attendees =
                  List<Map<String, dynamic>>.from(eventData['attended'] ?? []);

              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  title: Text(
                    eventData['event_name'] ?? 'Unknown Event',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    '${attendees.length} Participants${attendees.isNotEmpty ? ' · Last check-in: ${_formatCheckInTime(eventData['latest_checkin'])}' : ''}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: attendees.length,
                      itemBuilder: (context, index) {
                        final attendee = attendees[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title:
                              Text(attendee['participant_name'] ?? 'Unknown'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(attendee['participant_email'] ?? 'No email'),
                              Text(
                                  'ID: ${attendee['participant_id'] ?? 'No ID'}'),
                            ],
                          ),
                          trailing: Text(
                            _formatCheckInTime(attendee['check_in_time']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() {
            _showAllEvents = !_showAllEvents;
          });
        },
        icon: Icon(_showAllEvents ? Icons.history : Icons.history_toggle_off),
        label: Text(_showAllEvents ? 'Show Recent Only' : 'View Past Events'),
      ),
    );
  }

  String _formatCheckInTime(String? isoString) {
    if (isoString == null) return 'No time';
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();

      // Show date if not today
      if (dateTime.year == now.year &&
          dateTime.month == now.month &&
          dateTime.day == now.day) {
        return '${dateTime.hour.toString().padLeft(2, '0')}:'
            '${dateTime.minute.toString().padLeft(2, '0')}';
      } else {
        return '${dateTime.day}/${dateTime.month} '
            '${dateTime.hour.toString().padLeft(2, '0')}:'
            '${dateTime.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return 'Invalid time';
    }
  }
}
