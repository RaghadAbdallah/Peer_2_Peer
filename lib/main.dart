import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_nearby_connections/flutter_nearby_connections.dart';
import 'package:device_info/device_info.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

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
  String? fileType;
  String? base64PDF;
  String? compressedBase64PDF;
  int? originalFileSize;
  int? compressedFileSize;
  int? originalBase64Size;
  int? compressedBase64Size;
  String assemblingPartsBase64 = "";
  String? base64String;

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
  void dispose() {
    subscription.cancel();
    receivedDataSubscription.cancel();
    nearbyService.stopBrowsingForPeers();
    nearbyService.stopAdvertisingPeer();
    super.dispose();
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
      if (data['message'].split('-')[0] == 'end') {
        final file =
            await base64ToFile(assemblingPartsBase64, 'temp_video.mp4');
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => CheckTypeFile(
                      baseFile: assemblingPartsBase64,
                      typeFile: data['message'].split('-')[1],
                      file: file,
                    )));
        await base64ToFile(assemblingPartsBase64, _fileName);
      }
      // تجميع الأجزاء باستخدام Base64Reassembler
      Base64Reassembler reassembler = Base64Reassembler();
      reassembler.addChunk(data2.split(' ')[1]);
      // الحصول على السلسلة المجتمعة
      String reassembledBase64 = reassembler.getReassembledBase64();
      // تهيئة سلسلة لتجميع القيم الجديدة

      // مثال على إضافة سلسلة جديدة إلى السلسلة المجتمعة
      assemblingPartsBase64 = assemblingPartsBase64 + reassembledBase64;
    });
  }

  _onTabItemListener(Device device) async {
    if (device.state == SessionState.connected) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Send File"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Choose File Type..."),
                TextButton(
                  child: Text("Image"),
                  onPressed: () {
                    setState(() {
                      fileType = 'image';
                    });
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text("Video"),
                  onPressed: () {
                    setState(() {
                      fileType = 'video';
                    });
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text("PDF"),
                  onPressed: () {
                    setState(() {
                      fileType = 'pdf';
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
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
      await _getFile(fileType: fileType ?? ''); // Select an image
      final image = _image;
      if (image != null) {
        List<int> pdfBytes = await image.readAsBytes();
        originalFileSize = pdfBytes.length;

        // Convert to Base64
        base64String = base64Encode(pdfBytes);
        splitBase64String(base64String ?? '', 32720, device).then((value) {
          nearbyService.sendMessage(device.deviceId, 'end-$fileType');
          print('All chunks sent, including the end signal');
        });
      }
    }
  }

  Future<void> splitBase64String(
      String base64String, int chunkSize, Device device) async {
    int length = base64String.length;
    List<String> chunks = [];
    for (int i = 0; i < length; i += chunkSize) {
      int end = (i + chunkSize < length) ? i + chunkSize : length;
      chunks.add(base64String.substring(i, end));
    }

    // عرض عدد الأجزاء وطول كل جزء
    for (int i = 0; i < chunks.length; i++) {
      print('Chunk ${i + 1}: ${chunks[i].length}');
      nearbyService.sendMessage(device.deviceId, '$_fileName ${chunks[i]}');
    }
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

  Future<File> base64ToFile(String base64String, String fileName) async {
    final decodedBytes = base64Decode(base64String);
    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/$fileName');
    return file.writeAsBytes(decodedBytes);
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

  Future<void> _getFile({required String fileType}) async {
    switch (fileType) {
      case 'video':
        setState(() {
          filePath = '/data/data/com.example.p2p/files/30seconds.mp4';
          // '/data/data/com.example.p2p/files/facebook_1715581311783.mp4';
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
              '/data/data/com.example.p2p/files/FlutterInstallationGuide.pdf';
          // '/data/data/com.example.p2p/files/Flutter Requirements and Installation Guide.pdf';

          _image = File(filePath ?? '');
        });
        break;
    }
    await _saveValue(path.basename(filePath ?? ''));
  }


  Future<void> _saveValue(String value) async {
    await _prefs?.setString('myValue', value);
    setState(() {
      _fileName = value;
    });
  }
}

class Base64Reassembler {
  StringBuffer _buffer = StringBuffer();

  void addChunk(String chunk) {
    _buffer.write(chunk);
  }

  String getReassembledBase64() {
    return _buffer.toString();
  }
}

class TestPdfFile extends StatelessWidget {
  const TestPdfFile({super.key, required this.pdfFile});

  final String pdfFile;

  @override
  Widget build(BuildContext context) {
    return PDFView(
      pdfData: Uint8List.fromList(base64Decode(pdfFile)),
    );
  }
}

class TestImageFile extends StatelessWidget {
  const TestImageFile({super.key, required this.imageFile});

  final String imageFile;

  @override
  Widget build(BuildContext context) {
    Uint8List bytes = base64Decode(imageFile);
    return SizedBox(
      width: double.infinity,
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
      ),
    );
  }
}

class CheckTypeFile extends StatelessWidget {
  const CheckTypeFile(
      {super.key,
      required this.typeFile,
      required this.baseFile,
      required this.file});

  final String typeFile;
  final String baseFile;
  final File file;

  @override
  Widget build(BuildContext context) {
    return typeFile == 'pdf'
        ? TestPdfFile(
            pdfFile: baseFile,
          )
        : typeFile == 'image'
            ? TestImageFile(
                imageFile: baseFile,
              )
            : VideoPlayerScreen(
                file: file,
              );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final File file;

  VideoPlayerScreen({required this.file});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.file(widget.file);
    _initializeVideoPlayerFuture = _controller.initialize();
    _controller.setLooping(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Player'),
      ),
      body: Center(
        child: FutureBuilder(
          future: _initializeVideoPlayerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              );
            } else {
              return CircularProgressIndicator();
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
