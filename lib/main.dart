import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = openDatabase(
    // join paths using the path package await getDatabasesPath(), 'dictation_database.db'

    path.join(await getDatabasesPath(), 'dictation_database.db'),
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE dictations(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, audioPath TEXT)',
      );
    },
    version: 1,
  );
  runApp(DictationApp(database));
}

class DictationApp extends StatelessWidget {
  final Future<Database> database;

  DictationApp(this.database);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hindi Dictation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DictationScreen(database),
    );
  }
}

class DictationScreen extends StatefulWidget {
  final Future<Database> database;

  DictationScreen(this.database);
  @override
  _DictationScreenState createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  int _selectedIndex = 0;
  late Future<Database> _database;
  late List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _database = widget.database;

    _widgetOptions = <Widget>[
      TeacherTab(_database),
      StudentTab(),
    ];
  }

  void _onTabItemSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Help'),
          content: Text(
            'Madam/Sir, please record a lesson for the student so that they can listen, write on paper, and submit a photo using the camera. You can review it later.',
          ),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hindi Dictation'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.help),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Teacher',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'Student',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onTabItemSelected,
      ),
    );
  }
}

class TeacherTab extends StatefulWidget {
  final Future<Database> database;
  const TeacherTab(this.database);

  @override
  _TeacherTabState createState() => _TeacherTabState();
}

class _TeacherTabState extends State<TeacherTab> {
  late AudioPlayer audioPlayer;
  final _audioRecorder = Record();
  bool isRecording = false;
  bool isPlaying = false;
  String filePath = '';
  List<Dictation> dictations = [];
  String? permanentFilePath;

  @override
  void initState() {
    super.initState();
    audioPlayer = AudioPlayer();
    _getDictations();
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  // Future<String> _getFilePath() async {
  //   final directory = await getApplicationDocumentsDirectory();
  //   return directory.path;
  // }

  Future<String> _getFilePath() async {
    final directory = await getApplicationSupportDirectory();
    final uuid = Uuid();
    final fileName = 'recording_${uuid.v4()}.aac';
    return path.join(directory.path, fileName);
  }

  Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // We don't do anything with this but printing
        final isSupported = await _audioRecorder.isEncoderSupported(
          AudioEncoder.aacLc,
        );
        print('${AudioEncoder.aacLc.name} supported: $isSupported');

        permanentFilePath = await _getFilePath();

        // final devs = await _audioRecorder.listInputDevices();
        // final isRecording = await _audioRecorder.isRecording();

        await _audioRecorder.start(path: permanentFilePath);
        setState(() {
          isRecording = true;
        });
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> stopRecording() async {
    setState(() {
      isRecording = false;
    });

    final path = await _audioRecorder.stop();
    this.filePath = path!;

    // TODO record audio changes for file path

    // Move the recorded audio file to a permanent location
    final File audioFile = File(filePath);
    final File permanentFile = File(permanentFilePath!);
    await audioFile.rename(permanentFile.path);

    final dictation = Dictation(
      id: 0,
      title: 'New Title ${DateTime.now().toString()}',
      audioPath: permanentFilePath!,
    );

    await _saveDictation(dictation);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recorded: ${dictation.title}'),
      ),
    );

    _getDictations();
  }

  Future<void> _saveDictation(Dictation dictation) async {
    final db = await widget.database;
    await db.insert(
      'dictations',
      dictation.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _getDictations() async {
    final db = await widget.database;
    final List<Map<String, dynamic>> maps = await db.query('dictations');
    setState(() {
      dictations = List.generate(
        maps.length,
        (i) => Dictation.fromMap(maps[i]),
      );
    });
  }

  Future<void> playPauseAudio() async {
    if (isPlaying) {
      await audioPlayer.pause();
      setState(() {
        isPlaying = false;
      });
    } else {
      // await audioPlayer.play(filePath, isLocal: true);
      DeviceFileSource source = DeviceFileSource(filePath);
      audioPlayer.play(source);
      setState(() {
        isPlaying = true;
      });
    }
  }

  Future<void> playAudio(String audioPath) async {
    if (audioPath.isNotEmpty) {
      DeviceFileSource source = DeviceFileSource(filePath);
      await audioPlayer.play(source);
      setState(() {
        isPlaying = true;
      });
    }
  }

  Future<void> deleteDictation(Dictation dictation) async {
    final db = await widget.database;
    await db.delete(
      'dictations',
      where: 'id = ?',
      whereArgs: [dictation.id],
    );
    // Delete the associated audio file
    if (dictation.audioPath.isNotEmpty) {
      final audioFile = File(dictation.audioPath);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
    }
    // Refresh the dictations list
    _getDictations();
  }

  Future<void> editDictationTitle(Dictation dictation) async {
    final TextEditingController textEditingController =
        TextEditingController(text: dictation.title);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Dictation Title'),
          content: TextField(
            controller: textEditingController,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Save'),
              onPressed: () async {
                final newTitle = textEditingController.text;
                final db = await widget.database;
                await db.update(
                  'dictations',
                  {'title': newTitle},
                  where: 'id = ?',
                  whereArgs: [dictation.id],
                );
                // Refresh the dictations list
                _getDictations();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: dictations.length,
        itemBuilder: (BuildContext context, int index) {
          final dictation = dictations[index];
          return ListTile(
            title: Text(dictation.title),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () {
                    // TODO: Handle edit button tap
                    editDictationTitle(dictation);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.play_arrow),
                  onPressed: () {
                    // TODO: Handle play button tap
                    playAudio(dictation.audioPath);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () {
                    // TODO: Handle delete button tap
                    deleteDictation(dictation);
                  },
                ),
              ],
            ),
            // Other ListTile properties...
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: isRecording ? stopRecording : startRecording,
            child: isRecording ? Icon(Icons.stop) : Icon(Icons.mic),
            backgroundColor: isRecording ? Colors.red : null,
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            onPressed: playPauseAudio,
            child: isPlaying ? Icon(Icons.pause) : Icon(Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}

class Dictation {
  final int id;
  final String title;
  final String audioPath;

  Dictation({
    required this.id,
    required this.title,
    required this.audioPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'audioPath': audioPath,
    };
  }

  factory Dictation.fromMap(Map<String, dynamic> map) {
    return Dictation(
      id: map['id'],
      title: map['title'],
      audioPath: map['audioPath'],
    );
  }
}

class StudentTab extends StatelessWidget {
  const StudentTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'This is the Student tab.',
        style: TextStyle(fontSize: 18),
      ),
    );
  }
}
