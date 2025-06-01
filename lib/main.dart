import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Image Demo'),
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
  Uint8List? _imgBin;
  String? _imgUrl;
  Uint8List? _presetImgBin;

  @override
  void initState() {
    super.initState();
    _loadPresetImage();
  }

  Future<void> _loadPresetImage() async {
    final bytes = await rootBundle.load('wanted.jpg');
    setState(() {
      _presetImgBin = bytes.buffer.asUint8List();
    });
  }

  Future<void> _uploadImages() async {
    if (_imgBin == null) return;

    const srv = "https://wsdcollage.onrender.com";
    final uri = Uri.parse('$srv/v1/photos');
    final req = http.MultipartRequest('POST', uri);
    
    // メイン画像の追加
    final mpf = http.MultipartFile.fromBytes(
      'file', 
      _imgBin!, 
      filename: 'main.jpg', 
      contentType: MediaType('Image', 'jpeg')
    );
    req.files.add(mpf);

    // wantedの処理
    if (_presetImgBin != null) {
      final presetMpf = http.MultipartFile.fromBytes(
        'preset_file', 
        _presetImgBin!, 
        filename: 'preset.jpg', 
        contentType: MediaType('Image', 'jpeg')
      );
      req.files.add(presetMpf);
    }

    final resp = await req.send();
    final respStr = await resp.stream.bytesToString();
    final respMap = jsonDecode(respStr);
    setState(() {
      _imgUrl = "$srv/${respMap['url']}";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('加工前の画像'),
                        Expanded(
                          child: _imgBin != null
                              ? Image.memory(_imgBin!)
                              : const Center(child: Text("画像がありません")),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('加工後の画像'),
                        Expanded(
                          child: _imgUrl != null
                              ? Image.network(_imgUrl!)
                              : const Center(child: Text("画像がありません")),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              ImagePicker()
                .pickImage(source: ImageSource.gallery)
                .then((xfile) async {
                  if (xfile == null) return;
                  Uint8List img = await xfile.readAsBytes();
                  setState(() {
                    _imgBin = img;
                    _imgUrl = null;
                  });
                  await _uploadImages();
                });
            },
            tooltip: '画像を選択',
            child: const Icon(Icons.image),
          ),
        ],
      ),
    );
  }
}