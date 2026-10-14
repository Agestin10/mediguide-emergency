import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EmergencyRequestsScreen extends StatefulWidget {
  const EmergencyRequestsScreen({super.key});

  @override
  State<EmergencyRequestsScreen> createState() =>
      _EmergencyRequestsScreenState();
}

class _EmergencyRequestsScreenState extends State<EmergencyRequestsScreen> {
  Future<List<dynamic>> getEmergencyRequests() async {
    const String apiUrl = "http://10.0.2.2:8000/emergencies";

    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception("Failed to load emergency requests");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Requests")),

      body: FutureBuilder<List<dynamic>>(
        future: getEmergencyRequests(),

        builder: (context, snapshot) {
          // Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final requests = snapshot.data ?? [];

          // No data
          if (requests.isEmpty) {
            return const Center(child: Text("No emergency requests found"));
          }

          // Display data
          return ListView.builder(
            itemCount: requests.length,

            itemBuilder: (context, index) {
              final request = requests[index];

              return Card(
                margin: const EdgeInsets.all(10),

                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.emergency)),

                  title: Text(request["patient_name"]),

                  subtitle: Text(
                    "Age: ${request["age"]}\n"
                    "Condition: ${request["emergency_condition"]}\n"
                    "Status: ${request["status"]}",
                  ),

                  trailing: Text("#${request["id"]}"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
