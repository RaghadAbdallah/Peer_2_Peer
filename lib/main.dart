import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';
import 'package:device_info/device_info.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  runApp(MyApp());
}

Route<dynamic> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/':
      return MaterialPageRoute(builder: (_) => Home());
    case 'browser':
      return MaterialPageRoute(
          builder: (_) => DevicesListScreen(deviceType: DeviceType.browser));
    case 'advertiser':
      return MaterialPageRoute(
          builder: (_) => DevicesListScreen(deviceType: DeviceType.advertiser));
    default:
      return MaterialPageRoute(
          builder: (_) => Scaffold(
                body: Center(
                    child: Text('No route defined for ${settings.name}')),
              ));
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateRoute: generateRoute,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
    );
  }
}

class Home extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, 'browser');
              },
              child: Container(
                child: Center(
                    child: Text(
                  'BROWSER',
                  style: TextStyle(color: Colors.black, fontSize: 40),
                )),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, 'advertiser');
              },
              child: Container(
                child: Center(
                    child: Text(
                  'ADVERTISER',
                  style: TextStyle(color: Colors.black, fontSize: 40),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum DeviceType { advertiser, browser }

class DevicesListScreen extends StatefulWidget {
  const DevicesListScreen({required this.deviceType});

  final DeviceType deviceType;

  @override
  State<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends State<DevicesListScreen> {
  SharedPreferences? _prefs;
  late NearbyService nearbyService;
  String _fileName = '';
  late StreamSubscription subscription;
  late StreamSubscription receivedDataSubscription;
  List<Device> devices = [];
  List<Device> connectedDevices = [];
  File? _image;
  String? filePath;

  @override
  void initState() {
    _initSharedPreferences();
    super.initState();
    _getValue();
    init();
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _getValue() async {
    setState(() {
      _fileName = _prefs?.getString('myValue') ?? '';
    });
  }

  int getItemCount() {
    if (widget.deviceType == DeviceType.advertiser) {
      return connectedDevices.length;
    } else {
      return devices.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.deviceType.toString().substring(11).toUpperCase()),
        ),
        backgroundColor: Colors.white,
        body: ListView.builder(
            itemCount: getItemCount(),
            itemBuilder: (context, index) {
              final device = widget.deviceType == DeviceType.advertiser
                  ? connectedDevices[index]
                  : devices[index];
              return Container(
                margin: EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: GestureDetector(
                          onTap: () => _onTabItemListener(device),
                          child: Column(
                            children: [
                              Text(device.deviceName),
                              Text(
                                getStateName(device.state),
                                style: TextStyle(
                                    color: getStateColor(device.state)),
                              ),
                            ],
                            crossAxisAlignment: CrossAxisAlignment.start,
                          ),
                        )),
                        // Request connect
                        GestureDetector(
                          onTap: () => _onButtonClicked(device),
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: 8.0),
                            padding: EdgeInsets.all(8.0),
                            height: 35,
                            width: 100,
                            color: getButtonColor(device.state),
                            child: Center(
                              child: Text(
                                getButtonStateName(device.state),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                    SizedBox(
                      height: 8.0,
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey,
                    )
                  ],
                ),
              );
            }));
  }

  void init() async {
    nearbyService = NearbyService();
    String devInfo = '';
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      devInfo = androidInfo.model;
    }
    if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      devInfo = iosInfo.localizedModel;
    }
    await nearbyService.init(
        serviceType: 'mpconn',
        deviceName: devInfo,
        strategy: Strategy.P2P_STAR,
        callback: (isRunning) async {
          if (isRunning) {
            if (widget.deviceType == DeviceType.browser) {
              await nearbyService.stopBrowsingForPeers();
              await Future.delayed(Duration(microseconds: 200));
              await nearbyService.startBrowsingForPeers();
            } else {
              await nearbyService.stopAdvertisingPeer();
              await nearbyService.stopBrowsingForPeers();
              await Future.delayed(Duration(microseconds: 200));
              await nearbyService.startAdvertisingPeer();
              await nearbyService.startBrowsingForPeers();
            }
          }
        });
    subscription =
        nearbyService.stateChangedSubscription(callback: (devicesList) {
      devicesList.forEach((element) {
        print(
            " deviceId: ${element.deviceId} | deviceName: ${element.deviceName} | state: ${element.state}");

        if (Platform.isAndroid) {
          if (element.state == SessionState.connected) {
            nearbyService.stopBrowsingForPeers();
          } else {
            nearbyService.startBrowsingForPeers();
          }
        }
      });

      setState(() {
        devices.clear();
        devices.addAll(devicesList);
        connectedDevices.clear();
        connectedDevices.addAll(devicesList
            .where((d) => d.state == SessionState.connected)
            .toList());
      });
    });

    receivedDataSubscription =
        nearbyService.dataReceivedSubscription(callback: (data) async {
      print("dataReceivedSubscription: ${jsonEncode(data)}");
      String data2 = data['message'];
      Uint8List bytes = base64Decode(data2.split(' ')[1]);
      log('kkkkkkkkkkkkkkkkkkkkkk');
      log('${data2.split(' ')[1]}');
      log('$bytes');
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Container(
              color: Colors.red,
              width: double.infinity,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  saveImage(bytes, data2.split(' ')[0]);
                },
                child: Text('Close'),
              ),
            ],
          );
        },
      );
      saveImage(bytes, data2.split(' ')[0]);
    });
  }

  void saveImage(Uint8List bytes, String fileName) async {
    try {
      Directory? appDir = await getExternalStorageDirectory();
      String filePath = '${appDir?.path}/$fileName';

      await File(filePath).writeAsBytes(bytes);
      print('Image saved to $filePath');
    } catch (e) {
      print('Error saving image: $e');
    }
  }

  String getStateName(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return "disconnected";
      case SessionState.connecting:
        return "waiting";
      default:
        return "connected";
    }
  }

  Color getButtonColor(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
      case SessionState.connecting:
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  String getButtonStateName(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
      case SessionState.connecting:
        return "Connect";
      default:
        return "Disconnect";
    }
  }

  _onButtonClicked(Device device) {
    switch (device.state) {
      case SessionState.notConnected:
        nearbyService.invitePeer(
          deviceID: device.deviceId,
          deviceName: device.deviceName,
        );
        break;
      case SessionState.connected:
        nearbyService.disconnectPeer(deviceID: device.deviceId);
        break;
      case SessionState.connecting:
        break;
    }
  }

  Color getStateColor(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return Colors.black;
      case SessionState.connecting:
        return Colors.grey;
      default:
        return Colors.green;
    }
  }

  _onTabItemListener(Device device) async {
    if (device.state == SessionState.connected) {
      await _getFile(fileType: 'image'); // Select an image
      if (_image != null) {
        Uint8List resizedImageBytes = await _resizeImage(_image!);

        String base64Image = base64Encode(resizedImageBytes);
        log('base64Imageyyyyyyyyyyyyyyyyyyyy');
        log(base64Image.length.toString());
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Send image"),
              content: Text("Sending image..."),
              actions: [
                TextButton(
                  child: Text("Cancel"),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
        nearbyService.sendMessage(device.deviceId, '$_fileName $base64Image');
      }
    }
  }

  Future<void> _getFile({required String fileType}) async {
    switch (fileType) {
      case 'video':
        setState(() {
          filePath =
              '/data/data/com.example.p2p/files/facebook_1715581311783.mp4';
          _image = File(filePath ?? '');
        });
        break;
      case 'image':
        setState(() {
          filePath =
              '/data/data/com.example.p2p/files/screenshot-1715083964151.png';
          _image = File(filePath ?? '');
        });
        break;
      case 'pdf':
        setState(() {
          filePath =
              '/data/data/com.example.p2p/files/Flutter Requirements and Installation Guide.pdf';

          _image = File(filePath ?? '');
        });
        break;
    }
    await _saveValue(path.basename(filePath ?? ''));
  }

  Future<Uint8List> _resizeImage(File fileInfo) async {
    final file = img.decodeImage(await fileInfo.readAsBytes());
    final resizedImage =
        img.copyResize(file!, width: 300); // Adjust width as needed
    return Uint8List.fromList(img.encodePng(resizedImage));
  }

  Future<void> _saveValue(String value) async {
    await _prefs?.setString('myValue', value);
    setState(() {
      _fileName = value;
    });
  }
}
