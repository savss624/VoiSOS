import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:background_sms/background_sms.dart';
import 'package:hexcolor/hexcolor.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:awesome_dropdown/awesome_dropdown.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Based SOS System',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Voice Based SOS System'),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _appStatus = 'Normal';
  bool _listeningStatus = false;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  late NoiseMeter _noiseMeter;
  double meanDbs = 0.0;

  Map<String, Map<String, List<double>>> screamLoudness = {
    'Infants': {
      'Male': [100.0, 110.0],
      'Female': [100.0, 110.0],
    },
    'Children': {
      'Male': [105.0, 115.0],
      'Female': [105.0, 115.0],
    },
    'Teenagers': {
      'Male': [110.0, 120.0],
      'Female': [110.0, 120.0],
    },
    'Adults': {
      'Male': [110.0, 120.0],
      'Female': [110.0, 120.0],
    },
    'Elderly': {
      'Male': [80.0, 100.0],
      'Female': [80.0, 100.0],
    },
    'None': {
      'Male': [0.0, 120.0],
      'Female': [0.0, 120.0],
    }
  };
  String selectedAgeGroup = "Adults";
  String selectedGender = "Male";

  final TextEditingController _contactController = TextEditingController();

  void showToast(msg) {
    Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 3,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
        fontSize: 13.0);
  }

  Future<bool> _checkAudioPermission() async {
    bool permissionGranted = await Permission.microphone.isGranted;
    if (!permissionGranted) {
      await Permission.microphone.request();
    }
    permissionGranted = await Permission.microphone.isGranted;
    return permissionGranted;
  }

  Future<bool> _checkSmsPermission() async {
    bool permissionGranted = await Permission.sms.isGranted;
    if (!permissionGranted) {
      await Permission.sms.request();
    }
    permissionGranted = await Permission.sms.isGranted;
    return permissionGranted;
  }

  Future<bool> _checkLocationPermission() async {
    bool permissionGranted = await Permission.locationAlways.isGranted;
    if (!permissionGranted) {
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();
    }
    permissionGranted = await Permission.locationAlways.isGranted;
    return permissionGranted;
  }

  Future<bool> _checkLocationAccess() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.getCurrentPosition();
    }
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    return serviceEnabled;
  }

  void _sendCurrentLocation() async {
    setState(() {
      _appStatus = 'Sending Message...';
    });

    Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    SmsStatus result = await BackgroundSms.sendMessage(
        phoneNumber: '+91${_contactController.text}',
        message:
            "https://www.google.com/maps/search/?api=1&query=${currentPosition.latitude.toString()},${currentPosition.longitude.toString()}");
    if (result == SmsStatus.sent) {
      showToast("Location Sent.");
    }

    setState(() {
      _appStatus = 'Normal';
    });
  }

  void _checkRequiredPermission() async {
    await _checkAudioPermission();
    await _checkSmsPermission();
    await _checkLocationPermission();
    await _checkLocationAccess();
  }

  late SharedPreferences prefs;
  void _populateContact() async {
    prefs = await SharedPreferences.getInstance();
    String? sosContact = prefs.getString('sos_contact');
    _contactController.text = sosContact ?? '';
    setState(() {});
  }

  void _alertContacts() async {
    if (await _checkAudioPermission()) {
      if (_contactController.text == '') {
        showToast("Please Add Your Emergency Contact");
      } else {
        _sendCurrentLocation();
      }
    }
  }

  void _changeListeningState() {
    if (!_listeningStatus) {
      _porcupineManager.start();
      _noiseSubscription = _noiseMeter.noiseStream.listen(onData);
    } else {
      _porcupineManager.stop();
      _noiseSubscription!.cancel();
    }
    setState(() {
      _listeningStatus = !_listeningStatus;
    });
  }

  late PorcupineManager _porcupineManager;

  void _wakeWordCallback(int keywordIndex) {
    if ((keywordIndex == 0 || keywordIndex == 1) &&
        _appStatus == 'Normal' &&
        meanDbs >= screamLoudness[selectedAgeGroup]![selectedGender]![0] &&
        meanDbs <= screamLoudness[selectedAgeGroup]![selectedGender]![1]) {
      _alertContacts();
      if (kDebugMode) {
        print('HELP ME detected');
      }
    }
  }

  static const accessKey =
      "0JBPX0lrBAU+3q+HBKtL/qk9YGYLqTa5VpVBP+FljbVhfeHcQ/BvFg==";
  String keywordAsset = "assets/HelpMe.ppn";
  void _createPorcupineManager() async {
    _porcupineManager = await PorcupineManager.fromKeywordPaths(accessKey,
        ["assets/HelpMe.ppn", "assets/Emergency.ppn"], _wakeWordCallback);
  }

  void _createNoiceMeterManager() {
    _noiseMeter = NoiseMeter(onError);
  }

  void onData(NoiseReading noiseReading) {
    meanDbs = noiseReading.meanDecibel;
  }

  void onError(Object error) {
    if (kDebugMode) {
      print(error.toString());
    }
  }

  @override
  void initState() {
    _checkRequiredPermission();
    _populateContact();
    _createPorcupineManager();
    _createNoiceMeterManager();
    super.initState();
  }

  @override
  void dispose() {
    _porcupineManager.delete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: Text(widget.title)),
        backgroundColor: HexColor('#2C3639'),
      ),
      backgroundColor: HexColor('#DCD7C9'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: HexColor('#2C3639'),
        onPressed: () => {_changeListeningState()},
        label: !_listeningStatus
            ? const Text('Activate')
            : const Text('Deactivate'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            AwesomeDropDown(
              dropDownList: screamLoudness.keys.toList(),
              dropDownIcon: const Icon(
                Icons.arrow_drop_down,
                color: Colors.grey,
                size: 23,
              ),
              selectedItem: selectedAgeGroup,
              onDropDownItemClick: (selectedItem) {
                selectedAgeGroup = selectedItem;
              },
              dropStateChanged: (isOpened) {},
            ),
            const SizedBox(
              height: 20,
            ),
            AwesomeDropDown(
              dropDownList: const ["Male", "Female"],
              dropDownIcon: const Icon(
                Icons.arrow_drop_down,
                color: Colors.grey,
                size: 23,
              ),
              selectedItem: selectedGender,
              onDropDownItemClick: (selectedItem) {
                selectedGender = selectedItem;
                if (kDebugMode) {
                  print(selectedGender);
                  print(screamLoudness[selectedAgeGroup]![selectedGender]!);
                }
              },
              dropStateChanged: (isOpened) {},
            ),
            const SizedBox(
              height: 20.0,
            ),
            SizedBox(
              width: 180,
              child: TextFormField(
                controller: _contactController,
                cursorColor: HexColor('#2C3639'),
                decoration: InputDecoration(
                    contentPadding: const EdgeInsets.only(left: 24),
                    labelText: 'Emergency Contact',
                    labelStyle: TextStyle(color: HexColor('#2C3639')),
                    border: InputBorder.none),
              ),
            ),
            TextButton(
                onPressed: () {
                  if (kDebugMode) {
                    print(_contactController.text);
                  }
                  prefs.setString('sos_contact', _contactController.text);
                  setState(() {});
                },
                child: _contactController.text == ''
                    ? Text(
                        'Add',
                        style: TextStyle(color: HexColor('#2C3639')),
                      )
                    : Text(
                        'Update',
                        style: TextStyle(color: HexColor('#2C3639')),
                      )),
            const SizedBox(
              height: 200,
            ),
            const Text('Status'),
            Text(
              _appStatus,
              style: TextStyle(
                color: HexColor('#2C3639'),
                fontSize: 36,
              ),
            ),
            const SizedBox(
              height: 100,
            ),
          ],
        ),
      ),
    );
  }
}
