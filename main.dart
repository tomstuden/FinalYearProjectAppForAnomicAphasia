import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
//import 'package:just_audio/just_audio.dart';
import 'package:audioplayers/audioplayers.dart';
//import 'package:assets_audio_player/assets_audio_player.dart';

void main() {
  runApp(MyApp());
}

class DrawingArea {
  Offset point;
  Paint areaPaint;

  DrawingArea({required this.point, required this.areaPaint});
}

class MyCustomPainter extends CustomPainter {
  List<DrawingArea> points;

  MyCustomPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i].point, points[i + 1].point, points[i].areaPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: DrawingBoard(),
        backgroundColor: Colors.blueGrey[50],
      ),
    );
  }
}

class DrawingBoard extends StatefulWidget {
  @override
  _DrawingBoardState createState() => _DrawingBoardState();
}

class _DrawingBoardState extends State<DrawingBoard> {
  List<DrawingArea> points = [];
  late Paint areaPaint;
  bool isDrawing = false;
  String message = '';
  //late AudioPlayer audioPlayer;

  @override
  void initState() {
    super.initState();
    //audioPlayer = AudioPlayer();
    areaPaint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..strokeWidth = 3.0;
  }

  void clearPoints() {
    setState(() {
      points.clear();
      showMessage('Drawing area cleared!');
    });
  }

  void submitDrawing() {
    displayDrawingDialog();
  }

  void showMessage(String msg) {
    setState(() {
      message = msg;
    });
    Future.delayed(Duration(seconds: 2), () {
      setState(() {
        message = '';
      });
    });
  }

  bool isWithinDrawingArea(Offset offset, Size size) {
    return offset.dx >= 0 &&
        offset.dx <= size.width &&
        offset.dy >= 0 &&
        offset.dy <= size.height;
  }

  void displayDrawingDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        List<DrawingArea> resizedPoints = [];
        double scaleFactorX = 64 / 400;
        double scaleFactorY = 64 / 400;
        double scaledStrokeWidth = areaPaint.strokeWidth * scaleFactorX;
        Paint resizedPaint = Paint()
          ..color = areaPaint.color
          ..strokeCap = areaPaint.strokeCap
          ..isAntiAlias = areaPaint.isAntiAlias
          ..strokeWidth = scaledStrokeWidth;
        for (var point in points) {
          resizedPoints.add(DrawingArea(
            point: Offset(point.point.dx * scaleFactorX, point.point.dy * scaleFactorY),
            areaPaint: resizedPaint,
          ));
        }

        return AlertDialog(
          title: Text('Drawing'),
          content: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              size: Size.infinite,
              painter: MyCustomPainter(points: resizedPoints),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Confirmation'),
                      content: Text('Are you sure you want to submit?'),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                            await sendDrawingToAPI(resizedPoints);
                          },
                          child: Text('Yes'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text('No'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Text('Submit'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> sendDrawingToAPI(List<DrawingArea> drawing) async {
    List<Map<String, dynamic>> jsonDrawing = [];
    for (var area in drawing) {
      if (area.point != Offset.infinite) {
        jsonDrawing.add({
          'x': area.point.dx,
          'y': area.point.dy,
        });
      }
    }

    try {
      var response = await http.post(
        Uri.parse('http://127.0.0.1:5000/api/drawings'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(jsonDrawing),
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(response.body);
        String label = data['top_prediction_label'];
        String imageUrl = data['top_prediction_image_url'];
        String audioAssetPath = data[r'audio_file_path']; // Fetch audio asset path from response

        print('Audio Asset Path: $audioAssetPath');

        if (audioAssetPath.isNotEmpty) {
          // Play audio
          //playAudioFromAsset(audioAssetPath);
        }

        // Show prediction dialog
        if (imageUrl.isNotEmpty) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Prediction'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(
                      imageUrl,
                      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        } else {
                          return CircularProgressIndicator();
                        }
                      },
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                    SizedBox(height: 10),
                    Text(
                      label,
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                       try {
                             await playAudioFromFile(label);
                           } catch (e) {
                               print('Error playing audio: $e');
                              }
                      },
                      child: Text('Play Audio'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text('Close'),
                  ),
                ],
              );
            },
          );
        }

        showMessage('Drawing submitted successfully!');
      } else {
        showMessage('Failed to submit drawing. Please try again later.');
      }
    } catch (e) {
      showMessage('Error: $e');
    }
  }

  //Future<void> _loadAudio(String filePath) async {
  //  try {
      // Load audio file
  //    final audioFile = File(r'D:\FinalYearProject\AudioFiles\onion.wav');
  //    await audioFile.readAsBytes();
  //    if (!await audioFile.exists()) {
  //      throw Exception('File not found: $filePath');
  //   }

 //     playAudioFromFile(audioFile);
  //  } catch (e) {
  //    print('Error loading audio: $e');
  //    // Handle error
  //  }
  //}

  Future<void> playAudioFromFile(String prediction) async {
  try {
    // Print the audio URL
    print('Attempting to play audio from URL: $prediction');


    String audio = "assets/AudioFiles/$prediction.wav";
    print("Audio - " + audio);
    //String audio = "assets/AudioFiles/stairs.wav";
//    String audio = "file:///D:/FinalYearProject/AudioFiles/rain.mp3";

  
    final player = AudioPlayer();

    await player.play(UrlSource(audio));
    print("playing audio from " + audio);


    //await player.play('assets/AudioFiles/stairs.wav');


    // Fetch the audio file as a byte stream
    //final response = await http.get(Uri.parse(audioUrl));
    //final bytes = Uint8List.fromList(response.bodyBytes);

    // Get the temporary directory for storing the audio file
    //Directory tempDir = await getTemporaryDirectory();
    //String tempPath = tempDir.path;

    // Save the audio file to the temporary directory
    //File tempFile = File('$tempPath/.wav');
    //await tempFile.writeAsBytes(bytes);
   // final player = AudioPlayer();

    //AssetsAudioPlayer.newPlayer().open(
    //  Audio("assets/AudioFiles/stairs.wav"),
    //  autoStart: true,
    //  showNotification: true,
    //);
     //player.onPlayerStateChanged.listen((PlayerState state) {
    //if (state == PlayerState.playing) {
      //print("Audio is playing.");
    //} else if (state == PlayerState.stopped) {
      //print("Audio stopped.");
    //} 
    //});//await player.setUrl('D:\FinalYearProject\AudioFiles\onion.wav');
    //player.pause();
    //player.seek(Duration(seconds: 143));
  } catch (e) {
    // Print the error
    print('Error playing audio: $e');
    // Show an alert dialog with the error message
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text('Failed to play audio. Error: $e'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black),
              color: Colors.grey[200],
            ),
            child: GestureDetector(
              onPanDown: (details) {
                setState(() {
                  isDrawing = isWithinDrawingArea(details.localPosition, Size(400, 400));
                  if (isDrawing) {
                    points.add(DrawingArea(
                      point: details.localPosition,
                      areaPaint: areaPaint,
                    ));
                  }
                });
              },
              onPanUpdate: (details) {
                if (isDrawing) {
                  setState(() {
                    if (isWithinDrawingArea(details.localPosition, Size(400, 400))) {
                      points.add(DrawingArea(
                        point: details.localPosition,
                        areaPaint: areaPaint,
                      ));
                    } else {
                      isDrawing = false;
                    }
                  });
                }
              },
              onPanEnd: (details) {
                setState(() {
                  isDrawing = false;
                  points.add(DrawingArea(
                    point: Offset.infinite,
                    areaPaint: areaPaint,
                  ));
                });
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: MyCustomPainter(points: points),
              ),
            ),
          ),
        ),
        if (message.isNotEmpty)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(10),
              color: Colors.grey[300],
              child: Text(
                message,
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'App For Anomic Aphasia',
              style: TextStyle(color: Colors.black),
            ),
            centerTitle: true,
          ),
        ),
        Positioned(
          bottom: 20,
          left: 20,
          child: Row(
            children: [
              ElevatedButton(
                onPressed: clearPoints,
                child: Text('Clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrangeAccent,
                ),
              ),
              SizedBox(width: 20),
              ElevatedButton(
                onPressed: submitDrawing,
                child: Text('Submit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
