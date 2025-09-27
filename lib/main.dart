import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:random_string/random_string.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:clipboard/clipboard.dart';

// IMPORTANT: You must generate this file by running `flutterfire configure`
// in your project root. It connects your app to your Firebase project.
import 'firebase_options.dart';


Future<void> main() async {
  // Ensure Flutter is initialized.
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase using the auto-generated options file.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(

      debugShowCheckedModeBanner: false,
      title: 'Real-time Video & Screen Share',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF0F4F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _roomCodeController = TextEditingController();

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }
  void _createRoom() {
    final String roomId = randomAlphaNumeric(8).toUpperCase();
      Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(roomId: roomId, isCreator: true),
      ),
    );
  }
  void _joinRoom() {
      if (_roomCodeController.text.isNotEmpty) {
        Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(roomId: _roomCodeController.text.toUpperCase(), isCreator: false),
        ),
      );
    } else {
        FlutterToastr.show("Please enter a room code", context, duration: FlutterToastr.lengthShort);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-time Video Call'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Create or Join a Room',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _createRoom,
                    icon: const Icon(Icons.video_call_rounded),
                    label: const Text('Create New Room'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('OR')),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _roomCodeController,
                    decoration: InputDecoration(
                      labelText: 'Enter Room Code',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.meeting_room),
                    ),
                    onChanged: (text) {
                      _roomCodeController.value = _roomCodeController.value.copyWith(
                        text: text.toUpperCase(),
                        selection: TextSelection.collapsed(offset: text.length),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _joinRoom,
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Join Room'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class CallScreen extends StatefulWidget {
  final String roomId;
  final bool isCreator;

  const CallScreen({super.key, required this.roomId, required this.isCreator});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _screenShareStream;

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isConnected = false;
  bool _isScreenSharing = false;
 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initRenderersAndConnection();
  }

  Future<void> _initRenderersAndConnection() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    await _createPeerConnection();

    if(widget.isCreator) {
      await _createOffer();
    } else {
      await _listenForOffer();
    }
    // NEW: Set loading to false after all setup is done.
    if(mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createPeerConnection() async {
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': ['stun:stun1.l.google.com:19302', 'stun:stun2.l.google.com:19302']}
      ]
    };
    
    _peerConnection = await createPeerConnection(configuration);

    // FIXED: Wrap media acquisition in a try-catch block for robustness.
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({'video': true, 'audio': true});
      _localRenderer.srcObject = _localStream;
      _localStream?.getTracks().forEach((track) => _peerConnection?.addTrack(track, _localStream!));
    } catch(e) {
      print("Error getting user media: $e");
      // Handle error appropriately, maybe show a dialog to the user.
    }
    
    _peerConnection?.onTrack = (event) {
      if (mounted) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          _isConnected = true;
        });
      }
    };
  }

  // Called by the room creator to initiate the connection.
  Future<void> _createOffer() async {
    if (_peerConnection == null) return;
    DocumentReference roomRef = _firestore.collection('rooms').doc(widget.roomId);
    _peerConnection!.onIceCandidate = (candidate) {
      if(candidate != null) {
        roomRef.collection('callerCandidates').add(candidate.toMap());
      }
    };
    
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _peerConnection?.getRemoteDescription() != null) return;
      final data = snapshot.data() as Map<String, dynamic>;
      if (data.containsKey('answer')) {
        final answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
        await _peerConnection!.setRemoteDescription(answer);
      }
    });

    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  // Called by the room joiner to listen for an offer and respond.
  Future<void> _listenForOffer() async {
    if (_peerConnection == null) return;
    DocumentReference roomRef = _firestore.collection('rooms').doc(widget.roomId);
    
    roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _peerConnection?.getRemoteDescription() != null) return;
      
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null || !data.containsKey('offer')) return;

      final offerData = data['offer'] as Map<String, dynamic>;
      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      await _peerConnection!.setRemoteDescription(offer);
      await _createAnswer();
    });

    roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }
  
  // Creates an answer to the received offer.
 // IN CallScreen CLASS

Future<void> _createAnswer() async {
  if (_peerConnection == null) {
    print("ERROR: _createAnswer called but peer connection is null.");
    return;
  }
  print("Creating answer...");
  DocumentReference roomRef = _firestore.collection('rooms').doc(widget.roomId);

  // Assign onIceCandidate here to send to the correct subcollection
  _peerConnection!.onIceCandidate = (candidate) {
    if (candidate != null) {
      print("-> Sending callee candidate to Firestore."); // Added an arrow for easy spotting
      roomRef.collection('calleeCandidates').add(candidate.toMap());
    } else {
      print("End of callee candidates.");
    }
  };

  try {
    // Step 1: Create the answer
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    print("Answer created successfully in memory.");

    // Step 2: Set the local description. THIS IS THE STEP THAT TRIGGERS onIceCandidate.
    await _peerConnection!.setLocalDescription(answer);
    print("Set local description (answer) successfully. ICE gathering should now start.");

    // Step 3: Write the answer to Firestore
    await roomRef.update({'answer': answer.toMap()});
    print("Answer updated in Firestore.");

  } catch (e) {
    print("FATAL ERROR during _createAnswer: $e");
    // This will tell us if the process itself is failing.
  }
}

  // Toggles between camera and screen sharing.
  Future<void> _toggleScreenShare() async {
    if (!_isScreenSharing) {
      // STARTING screen share
      try {
        // Get the screen sharing stream
        _screenShareStream =
            await navigator.mediaDevices.getDisplayMedia({'video': true});

        // Ensure the stream is not null
        if (_screenShareStream != null) {
          var newTrack = _screenShareStream!.getVideoTracks().first;

          // Replace the camera track with the screen share track in the peer connection
          var senders = await _peerConnection?.getSenders();
          var sender = senders?.firstWhere((s) => s.track?.kind == 'video');
          await sender?.replaceTrack(newTrack);

          // IMPORTANT: Listen for when the user stops sharing from the OS controls
          // This ensures the app state is updated correctly.
          newTrack.onEnded = () {
            if (mounted && _isScreenSharing) {
              _stopScreenShare();
            }
          };

          // Update the UI state
          setState(() {
            _isScreenSharing = true;
            _localRenderer.srcObject = _screenShareStream;
            _isCameraOn = false; // Camera is effectively off
          });
        }
      } catch (e) {
        print("Error starting screen share: $e");
      }
    } else {
      // STOPPING screen share (called from the button press)
      await _stopScreenShare();
    }
  }

  // Private helper to consolidate screen share stopping logic
  Future<void> _stopScreenShare() async {
    try {
      // Get the original camera track to switch back to
      var cameraTrack = _localStream?.getVideoTracks().first;
      if (cameraTrack != null) {
        var senders = await _peerConnection?.getSenders();
        var sender = senders?.firstWhere((s) => s.track?.kind == 'video');
        await sender?.replaceTrack(cameraTrack);

        // CRITICAL: Stop all tracks on the screen share stream to release resources
        // and remove the OS indicator.
        _screenShareStream?.getTracks().forEach((track) => track.stop());
        _screenShareStream = null; // Clear the stream variable

        // Update the UI state if the widget is still mounted
        if (mounted) {
          setState(() {
            _isScreenSharing = false;
            _localRenderer.srcObject = _localStream;
            _isCameraOn = true; // Camera is back on
          });
        }
      }
    } catch (e) {
      print("Error stopping screen share: $e");
    }
  }

  void _toggleCamera() {
    if (_isScreenSharing) return; // Camera is disabled during screen share
    _localStream?.getVideoTracks().forEach((track) => track.enabled = !track.enabled);
    setState(() => _isCameraOn = !_isCameraOn);
  }

  void _toggleMic() {
    _localStream?.getAudioTracks().forEach((track) => track.enabled = !track.enabled);
    setState(() => _isMicOn = !_isMicOn);
  }

  // Cleans up all resources and deletes the room from Firestore.
  Future<void> _hangUp() async {
    try {
      // Stop tracks on streams we control before disposing
      _localStream?.getTracks().forEach((track) => track.stop());
      _screenShareStream?.getTracks().forEach((track) => track.stop());

      // Clean up all media streams
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      await _screenShareStream?.dispose();
      
      await _peerConnection?.close();
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
      
      // Clean up Firestore data
      if (widget.isCreator) {
        DocumentReference roomRef = _firestore.collection('rooms').doc(widget.roomId);
        var calleeCandidates = await roomRef.collection('calleeCandidates').get();
        calleeCandidates.docs.forEach((doc) => doc.reference.delete());
        var callerCandidates = await roomRef.collection('callerCandidates').get();
        callerCandidates.docs.forEach((doc) => doc.reference.delete());
        await roomRef.delete();
      }
    } catch (e) {
      print("Error during hangup: $e");
    } finally {
      if(mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _screenShareStream?.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      // FIXED: Use a simple loader while camera and connection are initializing.
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : SafeArea(
        child: Stack(
          children: [
            // Remote Video (Full Screen)
            Positioned.fill(
              child: RTCVideoView(_remoteRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
            // Local Video (Small view)
            Positioned(
              right: 20,
              top: 20,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(12)
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 120,
                    height: 160,
                    child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              ),
            ),
            // Room ID and Sharing
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Text('Room: ${widget.roomId}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => Share.share('Join my video call: ${widget.roomId}')),
                    IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () {
                        FlutterClipboard.copy(widget.roomId).then((_){
                          FlutterToastr.show("Room code copied!", context);
                        });
                    }),
                  ],
                ),
              ),
            ),
            // Waiting Indicator
            if(!_isConnected)
            Positioned.fill(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text('Waiting for other user to join...', style: TextStyle(color: Colors.white)),
                    ],
                  )
                ),
              )
            ),
            // Controls
            Positioned(
              bottom: 30, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(onPressed: _toggleMic, icon: _isMicOn ? Icons.mic : Icons.mic_off, color: _isMicOn ? Colors.teal : Colors.grey),
                  _buildControlButton(onPressed: _toggleScreenShare, icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share, color: _isScreenSharing ? Colors.green : Colors.teal),
                  _buildControlButton(onPressed: _hangUp, icon: Icons.call_end, color: Colors.red, size: 64),
                  _buildControlButton(onPressed: _toggleCamera, icon: _isCameraOn ? Icons.videocam : Icons.videocam_off, color: _isCameraOn ? Colors.teal : Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({required VoidCallback onPressed, required IconData icon, required Color color, double size = 56.0}) {
    return SizedBox(
      width: size,
      height: size,
      child: FloatingActionButton(
        heroTag: icon.toString(),
        onPressed: onPressed,
        backgroundColor: color,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}