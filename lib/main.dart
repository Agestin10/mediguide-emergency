import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'dart:convert';

void main() {
  runApp(const MediGuideApp());
}

class MediGuideApp extends StatelessWidget {
  const MediGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MediGuide AI',

      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      home: const AppStartupScreen(),
    );
  }
}

// ======================================================
// APP STARTUP: CHECK DATABASE FOR A SAVED JOURNEY
// ======================================================

class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  static const String baseUrl = 'http://10.0.2.2:8000';

  @override
  void initState() {
    super.initState();
    _restoreSavedJourney();
  }

  List<dynamic> _extractList(dynamic decoded, List<String> possibleKeys) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      for (final key in possibleKeys) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }

    return <dynamic>[];
  }

  Future<void> _restoreSavedJourney() async {
    try {
      // Step 1: Load saved emergency requests.
      final emergenciesResponse = await http
          .get(Uri.parse('$baseUrl/emergencies'))
          .timeout(const Duration(seconds: 10));

      if (emergenciesResponse.statusCode != 200) {
        _openWelcome();
        return;
      }

      final emergenciesJson = jsonDecode(emergenciesResponse.body);
      final emergencies = _extractList(emergenciesJson, const [
        'emergencies',
        'requests',
        'data',
      ]);

      // Find the newest request with a selected hospital.
      Map<String, dynamic>? latestRequest;
      int latestId = -1;

      for (final item in emergencies) {
        if (item is! Map) continue;

        final request = Map<String, dynamic>.from(item);

        final id = int.tryParse(
          (request['id'] ?? request['request_id'] ?? '').toString(),
        );

        final hospitalId =
            request['selected_hospital_id'] ?? request['hospital_id'];

        if (id != null && id > latestId && hospitalId != null) {
          latestId = id;
          latestRequest = request;
        }
      }

      if (latestRequest == null) {
        _openWelcome();
        return;
      }

      final requestId = int.parse(
        (latestRequest['id'] ?? latestRequest['request_id']).toString(),
      );

      // Step 2: Get the actual saved journey status.
      final statusResponse = await http
          .get(Uri.parse('$baseUrl/emergencies/$requestId/journey-status'))
          .timeout(const Duration(seconds: 10));

      if (statusResponse.statusCode != 200) {
        _openWelcome();
        return;
      }

      final statusData = jsonDecode(statusResponse.body);
      final journeyStatus = statusData['journey_status']?.toString();

      // Completed journey must NOT resume.
      if (journeyStatus == 'PATIENT_HANDED_OVER') {
        _openWelcome();
        return;
      }

      // Resume only a recognised active journey.
      const activeStatuses = {
        'AMBULANCE_STARTED',
        'ON_THE_WAY',
        'REACHED_HOSPITAL',
      };

      if (!activeStatuses.contains(journeyStatus)) {
        _openWelcome();
        return;
      }

      // Step 3: Load hospital details.
      final hospitalsResponse = await http
          .get(Uri.parse('$baseUrl/hospitals'))
          .timeout(const Duration(seconds: 10));

      if (hospitalsResponse.statusCode != 200) {
        _openWelcome();
        return;
      }

      final hospitalsJson = jsonDecode(hospitalsResponse.body);
      final hospitals = _extractList(hospitalsJson, const [
        'hospitals',
        'data',
      ]);

      final selectedId =
          (latestRequest['selected_hospital_id'] ??
                  latestRequest['hospital_id'])
              .toString();

      Map<String, dynamic>? selectedHospital;

      for (final item in hospitals) {
        if (item is! Map) continue;

        final hospital = Map<String, dynamic>.from(item);

        final id = (hospital['hospital_id'] ?? hospital['id'] ?? '').toString();

        if (id == selectedId) {
          selectedHospital = hospital;
          break;
        }
      }

      if (selectedHospital == null) {
        _openWelcome();
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AmbulanceJourneyScreen(
            requestId: requestId,
            hospital: selectedHospital!,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not restore saved journey: $e');
      _openWelcome();
    }
  }

  void _openWelcome() {
    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const WelcomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking for a saved ambulance journey...'),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// WELCOME SCREEN
// ======================================================

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                // Emergency icon
                Container(
                  width: 120,
                  height: 120,

                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),

                  child: const Icon(
                    Icons.local_hospital,
                    size: 70,
                    color: Colors.blue,
                  ),
                ),

                const SizedBox(height: 30),

                // App name
                const Text(
                  'MediGuide AI',

                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Emergency Assistance System',

                  textAlign: TextAlign.center,

                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),

                const SizedBox(height: 50),

                // Get Started
                SizedBox(
                  width: double.infinity,
                  height: 55,

                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,

                        MaterialPageRoute(
                          builder: (context) => const DemoLoginScreen(),
                        ),
                      );
                    },

                    child: const Text(
                      'GET STARTED',

                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DemoLoginScreen extends StatefulWidget {
  const DemoLoginScreen({super.key});

  @override
  State<DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<DemoLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _hidePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    // Demo only: this is NOT real authentication.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FE),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE1F1FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_hospital,
                    size: 52,
                    color: Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF20242C),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Login to MediGuide AI',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email or Phone Number',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF278CE6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'LOGIN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Demo login only — no account is created.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================
// HOME SCREEN
// ======================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MediGuide AI',

          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              const SizedBox(height: 30),

              // Emergency icon
              Container(
                width: 120,
                height: 120,

                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),

                child: const Icon(Icons.emergency, size: 70, color: Colors.red),
              ),

              const SizedBox(height: 25),

              const Text(
                'Emergency Service',

                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                'Need an ambulance?',

                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),

              const SizedBox(height: 45),

              // REQUEST AMBULANCE
              SizedBox(
                width: double.infinity,
                height: 60,

                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) => const EmergencyRequestScreen(),
                      ),
                    );
                  },

                  icon: const Icon(Icons.local_shipping, size: 28),

                  label: const Text(
                    'REQUEST AMBULANCE',

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // CALL 108
              SizedBox(
                width: double.infinity,
                height: 60,

                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '108 Call Service will be connected here.',
                        ),
                      ),
                    );
                  },

                  icon: const Icon(Icons.phone, size: 26),

                  label: const Text(
                    'CALL 108',

                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const Spacer(),

              const Text(
                'For emergency assistance',

                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================
// EMERGENCY REQUEST SCREEN
// ======================================================

class EmergencyRequestScreen extends StatefulWidget {
  const EmergencyRequestScreen({super.key});

  static Map<String, dynamic>? findAvailableAmbulanceInList(
    List<dynamic> ambulances,
  ) {
    for (final ambulance in ambulances) {
      final map = ambulance is Map<String, dynamic>
          ? ambulance
          : (ambulance is Map ? Map<String, dynamic>.from(ambulance) : null);

      if (map != null && map['status'] == 'Available') {
        return map;
      }
    }

    return null;
  }

  @override
  State<EmergencyRequestScreen> createState() => _EmergencyRequestScreenState();
}

class _EmergencyRequestScreenState extends State<EmergencyRequestScreen> {
  // --------------------------------------------------
  // TEXT CONTROLLERS
  // --------------------------------------------------

  final TextEditingController nameController = TextEditingController();

  final TextEditingController ageController = TextEditingController();

  final TextEditingController phoneController = TextEditingController();

  final TextEditingController notesController = TextEditingController();

  // --------------------------------------------------
  // DROPDOWN VALUES
  // --------------------------------------------------

  String? selectedGender;
  String? selectedCondition;

  // --------------------------------------------------
  // LOCATION UI STATE
  // --------------------------------------------------

  bool locationEnabled = false;
  double latitude = 0.0;
  double longitude = 0.0;

  // Controller for the real map
  final MapController mapController = MapController();

  // --------------------------------------------------
  // DISPOSE
  // --------------------------------------------------

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    phoneController.dispose();
    notesController.dispose();

    super.dispose();
  }

  Future<void> registerEmergency() async {
    const String apiUrl = "http://10.0.2.2:8000/emergency";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"latitude": latitude, "longitude": longitude}),
      );

      debugPrint("================================");
      debugPrint("EMERGENCY API");
      debugPrint("Status Code: ${response.statusCode}");
      debugPrint("Response Body: ${response.body}");
      debugPrint("================================");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint("Emergency registered successfully");

        debugPrint("Request ID: ${data["request_id"]}");

        await findAvailableAmbulance(data["request_id"]);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Emergency Registered! ID: ${data["request_id"]}"),
          ),
        );
      } else {
        debugPrint("Emergency API failed: ${response.statusCode}");

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Server Error: ${response.statusCode}")),
        );
      }
    } catch (e) {
      debugPrint("Connection Error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Connection Error: $e")));
    }
  }

  Future<void> findAvailableAmbulance(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('http://10.0.2.2:8000/ambulances'),
      );

      debugPrint("Ambulance API Status: ${response.statusCode}");
      debugPrint("Ambulance API Response: ${response.body}");

      if (response.statusCode == 200) {
        final List<dynamic> ambulances = jsonDecode(response.body);

        Map<String, dynamic>? availableAmbulance;

        for (final item in ambulances) {
          if (item is Map<String, dynamic> && item['status'] == 'Available') {
            availableAmbulance = item;
            break;
          }
        }

        if (availableAmbulance != null) {
          final ambulanceId = availableAmbulance['ambulance_id'].toString();

          debugPrint("Ambulance Assigned: $ambulanceId");

          if (!mounted) return;

          // Open Patient Assessment Screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AmbulanceAssessmentScreen(
                requestId: requestId,
                ambulanceId: ambulanceId,
              ),
            ),
          );
        } else {
          debugPrint("No ambulance available");

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No ambulance available')),
          );
        }
      } else {
        debugPrint("Ambulance API failed");

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to find ambulance')),
        );
      }
    } catch (e) {
      debugPrint("Ambulance Error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ambulance Error: $e')));
    }
  }

  Future<List<dynamic>> getEmergencyRequests() async {
    const String apiUrl = "http://10.0.2.2:8000/emergencies";

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Failed to load emergency requests");
      }
    } catch (e) {
      debugPrint("Error retrieving requests: $e");
      throw Exception("Could not connect to server");
    }
  }

  Future<void> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please turn on GPS')));

      return;
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );

        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission permanently denied')),
      );

      return;
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    setState(() {
      latitude = position.latitude;
      longitude = position.longitude;
      locationEnabled = true;
    });

    debugPrint("Latitude: $latitude");
    debugPrint("Longitude: $longitude");

    // Move the map to the current GPS location.
    mapController.move(LatLng(latitude, longitude), 15);
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // =================================================
      // APP BAR
      // =================================================

      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back),

          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'New Emergency Case',

          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
      ),

      // =================================================
      // BODY
      // =================================================
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =================================================
              // EMERGENCY REQUEST
              // =================================================
              sectionTitle(Icons.emergency, 'Emergency Request'),
              const SizedBox(height: 10),
              const Text(
                'Request an ambulance for the emergency.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // =================================================
              // PATIENT LOCATION
              // =================================================
              sectionTitle(Icons.location_on, 'Patient Location'),
              const SizedBox(height: 10),
              // LOCATION BUTTON ROW
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          locationEnabled
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: locationEnabled ? Colors.blue : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'Use Current GPS Location',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // GET LOCATION BUTTON
                  SizedBox(
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: getCurrentLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.gps_fixed, size: 17),
                      label: const Text(
                        'Get My Location',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // =================================================
              // REAL OPENSTREETMAP
              // =================================================
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: locationEnabled
                        ? LatLng(latitude, longitude)
                        : const LatLng(11.0168, 76.9558),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mediguide_emergency',
                    ),
                    if (locationEnabled)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(latitude, longitude),
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 42,
                            ),
                          ),
                        ],
                      ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(blurRadius: 4, color: Colors.black12),
                          ],
                        ),
                        child: Text(
                          locationEnabled
                              ? 'Current Location'
                              : 'Set GPS Location',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              // =================================================
              // REQUEST AMBULANCE BUTTON
              // =================================================
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    // GPS validation
                    if (!locationEnabled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please get your current location first',
                          ),
                        ),
                      );
                      return;
                    }

                    // Register emergency request
                    registerEmergency();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.local_hospital, size: 21),
                      SizedBox(width: 8),
                      Text(
                        'Request Ambulance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ======================================================
  // SECTION TITLE
  // ======================================================

  Widget sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 21),

        const SizedBox(width: 8),

        Text(
          title,

          style: const TextStyle(
            color: Color(0xFF174A8B),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ======================================================
  // FIELD LABEL
  // ======================================================

  Widget fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),

      child: Text(
        text,

        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
    );
  }

  // ======================================================
  // TEXT FIELD
  // ======================================================

  Widget textField({
    required TextEditingController controller,

    required String hint,

    required IconData icon,

    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,

      keyboardType: keyboardType,

      decoration: inputDecoration(hint, icon),
    );
  }

  // ======================================================
  // INPUT DECORATION
  // ======================================================

  InputDecoration inputDecoration(String hint, IconData? icon) {
    return InputDecoration(
      hintText: hint,

      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),

      prefixIcon: icon != null
          ? Icon(icon, size: 18, color: Colors.grey)
          : null,

      suffixIcon: hint == 'Select'
          ? const Icon(Icons.keyboard_arrow_down, size: 20)
          : null,

      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),

      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),

        borderSide: BorderSide(color: Colors.grey.shade300),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),

        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
    );
  }
}

class AmbulanceAssessmentScreen extends StatefulWidget {
  final int requestId;
  final String ambulanceId;

  const AmbulanceAssessmentScreen({
    super.key,
    required this.requestId,
    required this.ambulanceId,
  });

  @override
  State<AmbulanceAssessmentScreen> createState() =>
      _AmbulanceAssessmentScreenState();
}

class _AmbulanceAssessmentScreenState extends State<AmbulanceAssessmentScreen> {
  final TextEditingController patientNameController = TextEditingController();

  final TextEditingController ageController = TextEditingController();

  final TextEditingController phoneController = TextEditingController();

  final TextEditingController notesController = TextEditingController();

  String? selectedGender;
  String? selectedCondition;

  bool icuRequired = false;
  bool normalBedRequired = false;
  bool oxygenRequired = false;
  bool ventilatorRequired = false;
  bool specialistRequired = false;

  final TextEditingController otherFacilityController = TextEditingController();

  bool isSavingAssessment = false;

  @override
  void dispose() {
    patientNameController.dispose();
    ageController.dispose();
    phoneController.dispose();
    notesController.dispose();
    otherFacilityController.dispose();

    super.dispose();
  }

  Future<bool> saveAssessment() async {
    const String baseUrl = "http://10.0.2.2:8000";

    try {
      debugPrint("========== ASSESSMENT DATA ==========");
      debugPrint("Request ID: ${widget.requestId}");
      debugPrint("Patient Name: ${patientNameController.text.trim()}");
      debugPrint("Age: ${ageController.text.trim()}");
      debugPrint("Gender: $selectedGender");
      debugPrint("Condition: $selectedCondition");
      debugPrint("ICU Required: $icuRequired");
      debugPrint("Normal Bed Required: $normalBedRequired");
      debugPrint("Oxygen Required: $oxygenRequired");
      debugPrint("Ventilator Required: $ventilatorRequired");
      debugPrint("Specialist Required: $specialistRequired");
      debugPrint("Other Facility: ${otherFacilityController.text.trim()}");
      debugPrint("====================================");

      final response = await http.put(
        Uri.parse("$baseUrl/emergencies/${widget.requestId}/assessment"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "patient_name": patientNameController.text.trim(),
          "age": int.tryParse(ageController.text.trim()) ?? 0,
          "gender": selectedGender,
          "phone": phoneController.text.trim(),
          "emergency_condition": selectedCondition,
          "additional_notes": notesController.text.trim(),
          "icu_required": icuRequired,
          "normal_bed_required": normalBedRequired,
          "oxygen_required": oxygenRequired,
          "ventilator_required": ventilatorRequired,
          "specialist_required": specialistRequired,
          "other_facility": otherFacilityController.text.trim(),
        }),
      );

      debugPrint("Assessment API Status: ${response.statusCode}");
      debugPrint("Assessment API Response: ${response.body}");

      if (response.statusCode == 200) {
        debugPrint("Assessment saved for Request ID: ${widget.requestId}");
        return true;
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to save assessment: ${response.statusCode}"),
        ),
      );
      return false;
    } catch (e) {
      debugPrint("Assessment API Error: $e");
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Assessment Error: $e")));
      return false;
    }
  }

  Future<void> continueAssessment() async {
    if (isSavingAssessment) return;

    if (patientNameController.text.trim().isEmpty ||
        ageController.text.trim().isEmpty ||
        selectedGender == null ||
        selectedCondition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all required patient details'),
        ),
      );
      return;
    }

    final age = int.tryParse(ageController.text.trim());
    if (age == null || age < 0 || age > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid patient age')),
      );
      return;
    }

    if (!icuRequired &&
        !normalBedRequired &&
        !oxygenRequired &&
        !ventilatorRequired &&
        !specialistRequired &&
        otherFacilityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one emergency requirement'),
        ),
      );
      return;
    }

    setState(() => isSavingAssessment = true);
    final saved = await saveAssessment();
    if (!mounted) return;
    setState(() => isSavingAssessment = false);

    if (saved) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              HospitalResultsScreen(requestId: widget.requestId),
        ),
      );
    }
  }

  Widget buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
        ),
      ),
    );
  }

  Widget buildRequirementTile({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        secondary: icon != null ? Icon(icon, color: Colors.blue) : null,
        activeColor: Colors.blue,
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambulance Assessment'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_hospital,
                      color: Colors.blue,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Ambulance',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.ambulanceId,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                'Patient Details',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter the patient details after assessing the patient.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 18),
              buildTextField(
                label: 'Patient Name *',
                controller: patientNameController,
                keyboardType: TextInputType.name,
              ),
              buildTextField(
                label: 'Age *',
                controller: ageController,
                keyboardType: TextInputType.number,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: selectedGender,
                  decoration: InputDecoration(
                    labelText: 'Gender *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedGender = value;
                    });
                  },
                ),
              ),
              buildTextField(
                label: 'Phone Number',
                controller: phoneController,
                keyboardType: TextInputType.phone,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: selectedCondition,
                  decoration: InputDecoration(
                    labelText: 'Emergency Condition *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Accident',
                      child: Text('Accident'),
                    ),
                    DropdownMenuItem(
                      value: 'Chest Pain',
                      child: Text('Chest Pain'),
                    ),
                    DropdownMenuItem(
                      value: 'Breathing Difficulty',
                      child: Text('Breathing Difficulty'),
                    ),
                    DropdownMenuItem(
                      value: 'Unconscious',
                      child: Text('Unconscious'),
                    ),
                    DropdownMenuItem(
                      value: 'Severe Bleeding',
                      child: Text('Severe Bleeding'),
                    ),
                    DropdownMenuItem(
                      value: 'Burn Injury',
                      child: Text('Burn Injury'),
                    ),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedCondition = value;
                    });
                  },
                ),
              ),
              buildTextField(
                label: 'Additional Notes',
                controller: notesController,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              const Text(
                'Emergency Requirements',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select the resources required for the patient.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 18),
              buildRequirementTile(
                title: 'ICU Bed Required',
                value: icuRequired,
                icon: Icons.local_hospital,
                onChanged: (value) {
                  setState(() {
                    icuRequired = value ?? false;
                  });
                },
              ),
              buildRequirementTile(
                title: 'Normal Bed Required',
                value: normalBedRequired,
                icon: Icons.bed,
                onChanged: (value) {
                  setState(() {
                    normalBedRequired = value ?? false;
                  });
                },
              ),
              buildRequirementTile(
                title: 'Oxygen Required',
                value: oxygenRequired,
                icon: Icons.air,
                onChanged: (value) {
                  setState(() {
                    oxygenRequired = value ?? false;
                  });
                },
              ),
              buildRequirementTile(
                title: 'Ventilator Required',
                value: ventilatorRequired,
                icon: Icons.medical_services,
                onChanged: (value) {
                  setState(() {
                    ventilatorRequired = value ?? false;
                  });
                },
              ),
              buildRequirementTile(
                title: 'Specialist Required',
                value: specialistRequired,
                icon: Icons.person_search,
                onChanged: (value) {
                  setState(() {
                    specialistRequired = value ?? false;
                  });
                },
              ),
              const SizedBox(height: 6),
              buildTextField(
                label: 'Other Emergency Facility',
                controller: otherFacilityController,
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: isSavingAssessment ? null : continueAssessment,
                  icon: isSavingAssessment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    isSavingAssessment
                        ? 'Saving and finding hospitals...'
                        : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================
// STEP 11: HOSPITAL MATCHING RESULTS SCREEN
// ======================================================

class HospitalResultsScreen extends StatefulWidget {
  final int requestId;

  const HospitalResultsScreen({super.key, required this.requestId});

  @override
  State<HospitalResultsScreen> createState() => _HospitalResultsScreenState();
}

class _HospitalResultsScreenState extends State<HospitalResultsScreen> {
  bool isSelectingHospital = false;
  late Future<Map<String, dynamic>> hospitalsFuture;

  @override
  void initState() {
    super.initState();
    hospitalsFuture = fetchMatchedHospitals();
  }

  Future<Map<String, dynamic>> fetchMatchedHospitals() async {
    final url = Uri.parse(
      'http://10.0.2.2:8000/match-hospitals/${widget.requestId}',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 20));

    debugPrint('Hospital matching status: ${response.statusCode}');
    debugPrint('Hospital matching response: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from hospital matching API');
    }
    return decoded;
  }

  void retryLoading() {
    setState(() {
      hospitalsFuture = fetchMatchedHospitals();
    });
  }

  Future<void> selectHospital(Map<String, dynamic> hospital) async {
    final hospitalId = hospital['hospital_id'] ?? hospital['id'];

    if (hospitalId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hospital ID is missing')));
      return;
    }

    setState(() {
      isSelectingHospital = true;
    });

    try {
      final response = await http.put(
        Uri.parse(
          'http://10.0.2.2:8000/emergencies/${widget.requestId}/select-hospital',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'hospital_id': hospitalId}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HospitalConfirmationScreen(
              requestId: widget.requestId,
              hospital: hospital,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hospital selection failed: ${response.body}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error selecting hospital: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isSelectingHospital = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matched Hospitals'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: hospitalsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Finding hospitals for patient requirements...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 52, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load hospital results',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: retryLoading,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? <String, dynamic>{};
          final rawHospitals = data['hospitals'];
          final List<dynamic> hospitals = rawHospitals is List
              ? rawHospitals
              : [];
          final requested = (data['requested_facilities'] as List? ?? [])
              .map((item) => item.toString())
              .toList();
          final matchedCount = data['matched_hospital_count'] ?? 0;

          if (hospitals.isEmpty) {
            return const Center(child: Text('No hospital results found.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Request #${widget.requestId}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$matchedCount hospital(s) match all selected requirements.',
                    ),
                    if (requested.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Required facilities:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(requested.join(' • ')),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recommended order',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hospitals with all required facilities appear first. Partial matches are shown separately.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ...hospitals.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : <String, dynamic>{};
                return _hospitalCard(item, index + 1);
              }),
              const SizedBox(height: 12),
              const Text(
                'Prototype notice: hospital details and availability are sample data. Confirm actual availability before transferring a patient. Distance shown is straight-line distance, not road distance.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hospitalCard(Map<String, dynamic> hospital, int rank) {
    final bool fullMatch = hospital['all_requirements_match'] == true;
    final String name =
        hospital['hospital_name']?.toString() ?? 'Unknown Hospital';
    final String address =
        hospital['address']?.toString() ?? 'Address unavailable';
    final double distance =
        (hospital['distance_km'] as num?)?.toDouble() ?? 0.0;
    final int matchedCount = (hospital['matched_count'] as num?)?.toInt() ?? 0;
    final List<String> matched = (hospital['matched_facilities'] as List? ?? [])
        .map((value) => value.toString())
        .toList();
    final List<String> missing = (hospital['missing_facilities'] as List? ?? [])
        .map((value) => value.toString())
        .toList();

    final facilities = <Map<String, dynamic>>[
      {
        'name': 'ICU bed',
        'available': ((hospital['icu_beds'] as num?)?.toInt() ?? 0) > 0,
      },
      {
        'name': 'Normal bed',
        'available': ((hospital['normal_beds'] as num?)?.toInt() ?? 0) > 0,
      },
      {'name': 'Oxygen', 'available': hospital['oxygen_available'] == true},
      {
        'name': 'Ventilator',
        'available': hospital['ventilator_available'] == true,
      },
      {
        'name': 'Specialist',
        'available': hospital['specialist_available'] == true,
      },
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: fullMatch ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: fullMatch
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: fullMatch
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.near_me, size: 18, color: Colors.blue),
                const SizedBox(width: 5),
                Text(
                  '${distance.toStringAsFixed(2)} km away',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '$matchedCount matched',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: fullMatch ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    fullMatch
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: fullMatch
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      fullMatch
                          ? 'All required facilities matched'
                          : 'Partial match — missing facilities below',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: fullMatch
                            ? Colors.green.shade800
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Facility status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: facilities.map((facility) {
                final bool available = facility['available'] == true;
                return Chip(
                  avatar: Icon(
                    available ? Icons.check_circle : Icons.cancel,
                    size: 17,
                    color: available ? Colors.green : Colors.red,
                  ),
                  label: Text(facility['name'] as String),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            if (matched.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Matched: ${matched.join(', ')}',
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Missing: ${missing.join(', ')}',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final hospitalId = hospital['hospital_id'] ?? hospital['id'];
                  if (hospitalId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Hospital ID is missing in the API response',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HospitalRouteScreen(
                        requestId: widget.requestId,
                        hospitalId: hospitalId.toString(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.directions),
                label: const Text('View Road Route'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSelectingHospital
                    ? null
                    : () {
                        selectHospital(hospital);
                      },
                icon: isSelectingHospital
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.local_hospital),
                label: Text(
                  isSelectingHospital
                      ? 'Selecting Hospital...'
                      : 'Select Hospital',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HospitalConfirmationScreen extends StatelessWidget {
  final int requestId;
  final Map<String, dynamic> hospital;

  const HospitalConfirmationScreen({
    super.key,
    required this.requestId,
    required this.hospital,
  });

  @override
  Widget build(BuildContext context) {
    final hospitalName =
        hospital['hospital_name']?.toString() ??
        hospital['name']?.toString() ??
        'Selected Hospital';
    final address = hospital['address']?.toString() ?? 'Address not available';
    final distance = hospital['distance_km']?.toString() ?? '--';
    final matchedCount = hospital['matched_count']?.toString() ?? '--';

    return Scaffold(
      appBar: AppBar(title: const Text('Hospital Confirmed')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(Icons.check_circle, size: 80, color: Colors.green),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Hospital Selected Successfully',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospitalName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on),
                        const SizedBox(width: 8),
                        Expanded(child: Text(address)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.route),
                        const SizedBox(width: 8),
                        Text('Distance: $distance km'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.medical_services),
                        const SizedBox(width: 8),
                        Text('Facilities matched: $matchedCount'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AmbulanceJourneyScreen(
                        requestId: requestId,
                        hospital: hospital,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Start Journey'),
              ),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }
}

class AmbulanceJourneyScreen extends StatefulWidget {
  final int requestId;
  final Map<String, dynamic> hospital;

  const AmbulanceJourneyScreen({
    super.key,
    required this.requestId,
    required this.hospital,
  });

  @override
  State<AmbulanceJourneyScreen> createState() => _AmbulanceJourneyScreenState();
}

class _AmbulanceJourneyScreenState extends State<AmbulanceJourneyScreen> {
  int currentStep = 0;

  final List<String> statuses = [
    'AMBULANCE_STARTED',
    'ON_THE_WAY',
    'REACHED_HOSPITAL',
    'PATIENT_HANDED_OVER',
  ];

  final List<String> statusTitles = [
    'Ambulance Started',
    'On the Way to Hospital',
    'Reached Hospital',
    'Patient Handed Over',
  ];

  final List<IconData> statusIcons = [
    Icons.local_shipping,
    Icons.navigation,
    Icons.local_hospital,
    Icons.check_circle,
  ];

  Future<void> updateStatus() async {
    if (currentStep >= statuses.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient handover already completed.')),
      );
      return;
    }

    final nextStep = currentStep + 1;
    final nextStatus = statuses[nextStep];

    try {
      final response = await http.put(
        Uri.parse(
          'http://10.0.2.2:8000/emergencies/${widget.requestId}/journey-status',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': nextStatus}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          currentStep = nextStep;
        });

        if (nextStatus == 'PATIENT_HANDED_OVER') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${statusTitles[nextStep]} updated successfully'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to connect to server: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadSavedJourneyStatus();
  }

  Future<void> loadSavedJourneyStatus() async {
    try {
      final response = await http.get(
        Uri.parse(
          'http://10.0.2.2:8000/emergencies/${widget.requestId}/journey-status',
        ),
      );

      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body);
      final savedStatus = data['journey_status'];

      if (savedStatus == null) {
        return;
      }

      final savedStep = statuses.indexOf(savedStatus);

      if (!mounted || savedStep == -1) {
        return;
      }

      setState(() {
        currentStep = savedStep;
      });
    } catch (e) {
      debugPrint('Could not load saved journey status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitalName =
        widget.hospital['hospital_name']?.toString() ??
        widget.hospital['name']?.toString() ??
        'Selected Hospital';

    return Scaffold(
      appBar: AppBar(title: const Text('Ambulance Journey')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.local_hospital, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Destination Hospital',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            hospitalName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Journey Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: statuses.length,
                itemBuilder: (context, index) {
                  final completed = index <= currentStep;
                  final active = index == currentStep;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Icon(
                            statusIcons[index],
                            size: 32,
                            color: completed ? Colors.green : Colors.grey,
                          ),
                          if (index < statuses.length - 1)
                            Container(
                              width: 3,
                              height: 55,
                              color: index < currentStep
                                  ? Colors.green
                                  : Colors.grey.shade300,
                            ),
                        ],
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusTitles[index],
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: completed ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                completed ? 'Completed' : 'Pending',
                                style: TextStyle(
                                  color: completed ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 25),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: updateStatus,
                icon: Icon(
                  currentStep == statuses.length - 1
                      ? Icons.check
                      : Icons.arrow_forward,
                ),
                label: Text(
                  currentStep == statuses.length - 1
                      ? 'Journey Completed'
                      : 'Update Status',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the OSRM road route for the selected hospital.
/// Note: OSRM duration is an estimate, not live traffic-aware ETA.
class HospitalRouteScreen extends StatefulWidget {
  final int requestId;
  final String hospitalId;

  const HospitalRouteScreen({
    super.key,
    required this.requestId,
    required this.hospitalId,
  });

  @override
  State<HospitalRouteScreen> createState() => _HospitalRouteScreenState();
}

class _HospitalRouteScreenState extends State<HospitalRouteScreen> {
  late Future<Map<String, dynamic>> routeFuture;

  @override
  void initState() {
    super.initState();
    routeFuture = fetchRoute();
  }

  Future<Map<String, dynamic>> fetchRoute() async {
    final uri = Uri.parse(
      'http://10.0.2.2:8000/route/${widget.requestId}/${widget.hospitalId}',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 25));

    debugPrint('Route API status: ${response.statusCode}');
    debugPrint('Route API response: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Route server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected route API response');
    }
    return decoded;
  }

  void retryRoute() {
    setState(() {
      routeFuture = fetchRoute();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital Road Route'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: routeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading road route...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load road route',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: retryRoute,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final patient = Map<String, dynamic>.from(
            data['patient_location'] as Map,
          );
          final hospital = Map<String, dynamic>.from(
            data['hospital_location'] as Map,
          );

          final patientPoint = LatLng(
            (patient['latitude'] as num).toDouble(),
            (patient['longitude'] as num).toDouble(),
          );
          final hospitalPoint = LatLng(
            (hospital['latitude'] as num).toDouble(),
            (hospital['longitude'] as num).toDouble(),
          );

          final geometry = Map<String, dynamic>.from(
            data['route_geometry'] as Map,
          );
          final rawCoordinates = geometry['coordinates'] as List? ?? [];
          final routePoints = rawCoordinates.map((coordinate) {
            final pair = coordinate as List;
            // GeoJSON coordinates are [longitude, latitude].
            return LatLng(
              (pair[1] as num).toDouble(),
              (pair[0] as num).toDouble(),
            );
          }).toList();

          final distanceKm = (data['distance_km'] as num).toDouble();
          final durationMinutes = (data['estimated_duration_minutes'] as num)
              .round();
          final hospitalName =
              data['hospital_name']?.toString() ?? 'Selected Hospital';

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hospitalName,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.route, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              '${distanceKm.toStringAsFixed(2)} km road distance',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Estimated travel time: $durationMinutes min',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Estimated road time only — not live traffic-aware. '
                          'Hospital coordinates are sample data in this prototype.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: patientPoint,
                    initialZoom: 14,
                    onMapReady: () {},
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.mediguide_emergency',
                    ),
                    if (routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            strokeWidth: 5,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: patientPoint,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.red,
                            size: 42,
                          ),
                        ),
                        Marker(
                          point: hospitalPoint,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.local_hospital,
                            color: Colors.green,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
