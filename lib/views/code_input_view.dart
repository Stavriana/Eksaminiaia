import 'dart:developer'; // For logging

import 'package:eksaminiaia/views/rules.dart';
import 'package:eksaminiaia/views/team_words.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart'; // For GetX state management
import 'package:cloud_firestore/cloud_firestore.dart';
import 'set_it_up_page.dart'; // Import SetItUpPage for room creation
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class CodeInputView extends StatefulWidget {
  const CodeInputView({super.key});

  @override
  State<CodeInputView> createState() => _CodeInputViewState();
}

class _CodeInputViewState extends State<CodeInputView> {
  final TextEditingController _codeController = TextEditingController();
  bool _isCodeValid = true;

  void _joinGame(BuildContext context) async {
    final enteredCode = _codeController.text.trim().toUpperCase();

    if (enteredCode.isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter a valid room code.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    try {
      final docRef =
          FirebaseFirestore.instance.collection('Rooms').doc(enteredCode);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        Get.snackbar(
          'Error',
          'The room code is invalid or does not exist.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final roomData = docSnapshot.data();

      if (roomData == null) {
        Get.snackbar(
          'Error',
          'Failed to load room data.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final int playersIn = roomData['playersin'] ?? 0;
      final int numOfPlayers = roomData['numofplayers'] ?? 0;

      if (playersIn >= numOfPlayers - 1) {
        Get.snackbar(
          'Room Full',
          'The room is already full. Please try another room.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      // Get locationadmin's coordinates
      final locationAdmin = roomData['locationadmin'];
      if (locationAdmin != null) {
        final adminLatitude = locationAdmin['latitude'] as double?;
        final adminLongitude = locationAdmin['longitude'] as double?;

        if (adminLatitude != null && adminLongitude != null) {
          // Get player's current location
          final playerPosition = await _getUserLocation();
          if (playerPosition == null) {
            Get.snackbar(
              'Error',
              'Failed to fetch your location. Please enable location services and try again.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
            return;
          }

          // Calculate distance between player and admin
          final distanceInMeters = Geolocator.distanceBetween(
            playerPosition.latitude,
            playerPosition.longitude,
            adminLatitude,
            adminLongitude,
          );

          if (distanceInMeters > 200) {
            Get.snackbar(
              'Too Far',
              'You are more than 200 meters away from the room admin.',
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Colors.orange,
              colorText: Colors.white,
            );
            return;
          }
        }
      } else {
        log('No locationadmin found. Proceeding without location check.');
      }

      // Increment the playersIn count
      await docRef.update({
        'playersin': FieldValue.increment(1),
      });

      // Navigate to TeamWordsScreen
      Get.to(() => TeamWordsScreen(roomCode: enteredCode));
    } catch (e) {
      log('Error joining game: $e', name: 'GameService');
      Get.snackbar(
        'Error',
        'An error occurred while joining the room. Please try again later.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _createRoom(BuildContext context) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        Get.snackbar(
          'Sign-In Required',
          'You must sign in to create a room.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final userUid = currentUser.uid;
      final roomCode = _generateRandomRoomCode();

      // Get user location
      final position = await _getUserLocation();

      // Create or update room with locationadmin field
      await FirebaseFirestore.instance.collection('Rooms').doc(roomCode).set({
        'adminId': userUid,
        'id': roomCode,
        'ourteams': {},
        'words': [],
        'numofwords': 5,
        'numofplayers': 4,
        'numofteams': 2,
        'playersin': 0,
        'locationadmin': position != null
            ? {
                'latitude': position.latitude,
                'longitude': position.longitude,
              }
            : null, // Set null if position is unavailable
      }, SetOptions(merge: true)); // Use merge: true to ensure no overwrites

      if (mounted) {
        Get.to(() => SetItUpPage(roomCode: roomCode));
      }
    } catch (e) {
      log('Error creating room: $e', name: 'GameService');
      Get.snackbar(
        'Error',
        'Failed to create room. Please try again later.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<Position?> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permissions are permanently denied. Cannot request permissions.',
        );
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
    } catch (e) {
      log('Error fetching location: $e', name: 'LocationService');
      return null;
    }
  }

  String _generateRandomRoomCode() {
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        4,
        (_) => characters.codeUnitAt(
          DateTime.now().millisecondsSinceEpoch % characters.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join/Create Game')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                const Text(
                  'JOIN A GAME',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Insert room code:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: _isCodeValid
                              ? Colors.white
                              : Colors.red.shade900,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(
                            hintText: 'Enter code here...',
                            hintStyle: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                          onChanged: (_) {
                            setState(() {
                              _isCodeValid = true;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _joinGame(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Center(
                  child: GestureDetector(
                    onTap: () => _createRoom(context),
                    child: const CreateRoomButton(),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RulesPageApp()),
                  );
                },
                child: Image.asset(
                  'assets/images/house.png',
                  width: 40,
                  height: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CreateRoomButton extends StatelessWidget {
  const CreateRoomButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/button_image.png',
              fit: BoxFit.cover,
            ),
          ),
          const Positioned(
            top: 55,
            child: Text(
              'CREATE\nROOM',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
