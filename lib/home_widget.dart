import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:brethap/utils.dart';
import 'package:brethap/constants.dart';
import 'package:brethap/preferences_widget.dart';
import 'package:brethap/sessions_widget.dart';
import 'package:brethap/hive_storage.dart';
import 'package:brethap/sessions_calendar_widget.dart';

class HomeWidget extends StatefulWidget {
  HomeWidget(
      {Key? key,
      required this.appName,
      required this.version,
      required this.preferences,
      required this.sessions})
      : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String appName, version;
  final Box preferences, sessions;

  @override
  _HomeWidgetState createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  bool _isRunning = false,
      _hasVibrator = false,
      _hasCustomVibrate = false,
      _hasWakelock = false,
      _hasSpeak = false;
  late Duration _duration;
  late String _status, _appName;
  late FlutterTts _tts;
  double _scale = 0.0;

  @override
  initState() {
    debugPrint("${this.widget}.initState");
    _initVibrator();
    _initWakeLock();
    _initSpeak();
    _init();
    super.initState();
  }

  @override
  void dispose() {
    debugPrint("${this.widget}.dispose");
    super.dispose();
  }

  void _init() {
    if (kDebugMode) {
      createRandomSessions(widget.sessions, 200, DateTime(2021, 1),
          DateTime.now().subtract(Duration(days: 1)));
    }
    _status = "";
    if (widget.preferences.isEmpty) {
      createDefaultPref(widget.preferences);
    }

    _update();
  }

  Future<void> _initVibrator() async {
    try {
      _hasVibrator = await Vibration.hasVibrator() ?? false;
      _hasCustomVibrate = await Vibration.hasCustomVibrationsSupport() ?? false;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _initSpeak() async {
    try {
      _tts = FlutterTts();
      await _tts.awaitSpeakCompletion(false);
      _hasSpeak = true;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future _speak(String text) async {
    if (_hasSpeak) {
      await _tts.speak(text);
      debugPrint("spoke: $text");
    }
  }

  Future<void> _initWakeLock() async {
    try {
      await Wakelock.enabled;
      _hasWakelock = true;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _wakeLock(bool enable) {
    if (_hasWakelock) {
      Wakelock.toggle(enable: enable);
      debugPrint("wakelock: $enable");
    }
  }

  void _update() {
    Preference preference = widget.preferences.get(0);
    _duration = Duration(seconds: preference.duration);
    _appName = preference.name.isEmpty ? APP_NAME : preference.name;
    debugPrint("session preference:$preference");
  }

  Future<void> _vibrate(int ms) async {
    if (_hasVibrator && ms > 0) {
      if (_hasCustomVibrate) {
        await Vibration.vibrate(duration: ms);
      } else {
        await Vibration.vibrate();
      }
      debugPrint("vibrated: $ms");
    }
  }

  Future<void> _onDuration(Session session) async {
    Preference preference = widget.preferences.get(0);

    _vibrate(preference.vibrateDuration);

    Duration diff = roundDuration(session.end.difference(session.start));
    String duration = getDurationString(diff);
    int breaths = session.breaths;
    String text = "$duration ${AppLocalizations.of(context)!.session}";
    if (breaths == 1) {
      text += ", $breaths ${AppLocalizations.of(context)!.breath}";
    } else {
      text += ", $breaths ${AppLocalizations.of(context)!.breaths}";
    }

    if (preference.durationTts) {
      await _speak(text);
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
    ));
  }

  Future<void> _onBreath(String text) async {
    Preference preference = widget.preferences.get(0);

    _vibrate(preference.vibrateBreath);

    if (preference.breathTts) {
      await _speak(text);
    }
  }

  void _addSession(Session session) {
    widget.sessions.add(session).then((value) {
      debugPrint("added session:$session");
    });
  }

  void _buttonPressed(context) {
    debugPrint("${this.widget}._buttonPressed");

    if (_isRunning) {
      _isRunning = false;
    } else {
      Preference preference = widget.preferences.get(0);
      _update();
      _isRunning = true;
      Session session = Session(start: DateTime.now());
      _wakeLock(true);

      Duration timerSpan = Duration(milliseconds: 100);
      int inhale =
          preference.inhale[0] + preference.inhale[1] + preference.inhale[2];
      int exhale =
          preference.exhale[0] + preference.exhale[1] + preference.exhale[2];
      int breath = inhale + exhale;
      int cycle = 0;
      double inhaleScale = timerSpan.inMilliseconds /
          (preference.inhale[0] + preference.inhale[2]);
      double exhaleScale = timerSpan.inMilliseconds /
          (preference.exhale[0] + preference.exhale[2]);
      bool inhaling = true, exhaling = false;

      Timer.periodic(timerSpan, (Timer timer) {
        if (!_isRunning || (_duration.inSeconds <= 0 && cycle <= 0)) {
          setState(() {
            _status = AppLocalizations.of(context)!.pressStart;
            _isRunning = false;
            session.end = DateTime.now();
            session.breaths = (preference.duration - _duration.inSeconds) ~/
                (breath / Duration.millisecondsPerSecond);
            _addSession(session);
            _onDuration(session);
            _wakeLock(false);
            _duration = Duration(seconds: preference.duration);
            _scale = 0.0;
            timer.cancel();
          });
        } else {
          setState(() {
            String text;
            if (cycle == 0) {
              inhaling = true;
              exhaling = false;
              text = AppLocalizations.of(context)!.inhale;
              _scale = 0.0;
              _onBreath(text);
              _status = text;
            } else if (preference.inhale[1] > 0 &&
                cycle == preference.inhale[0]) {
              inhaling = false;
              exhaling = false;
              text = AppLocalizations.of(context)!.hold;
              _onBreath(text);
              _status = text;
            } else if (preference.inhale[2] > 0 &&
                cycle == preference.inhale[0] + preference.inhale[1]) {
              inhaling = true;
              exhaling = false;
              text = AppLocalizations.of(context)!.inhale;
              _onBreath(text);
              _status = text;
            } else if (cycle == inhale) {
              inhaling = false;
              exhaling = true;
              text = AppLocalizations.of(context)!.exhale;
              _scale = 1.0;
              _onBreath(text);
              _status = text;
            } else if (preference.exhale[1] > 0 &&
                cycle == inhale + preference.exhale[0]) {
              inhaling = false;
              exhaling = false;
              text = AppLocalizations.of(context)!.hold;
              _onBreath(text);
              _status = text;
            } else if (preference.exhale[2] > 0 &&
                cycle == inhale + preference.exhale[0] + preference.exhale[1]) {
              inhaling = false;
              exhaling = true;
              text = AppLocalizations.of(context)!.exhale;
              _onBreath(text);
              _status = text;
            }

            cycle += timerSpan.inMilliseconds;
            if (cycle >= breath) {
              cycle = 0;
            }

            if (inhaling) {
              _scale += inhaleScale;
              if (_scale > 1.0) {
                _scale = 1.0;
              }
            } else if (exhaling) {
              _scale -= exhaleScale;
              if (_scale < 0.0) {
                _scale = 0.0;
              }
            }

            if (!_duration.isNegative) {
              _duration -= timerSpan;
            }
          });
        }

        debugPrint("_duration: $_duration _scale: $_scale cycle: $cycle");
      });
    }
  }

  void _showWebDialog(String url) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.couldNotLaunch),
          content: Text('''
${AppLocalizations.of(context)!.openBrowser}: 

$url'''),
        );
      },
    );
  }

  void _launchURL(String url) {
    canLaunch(url).then((value) {
      if (value) {
        launch(url);
      } else {
        _showWebDialog(url);
        debugPrint("Could not launch url");
      }
    });
  }

  // Callback for variables needed in HomeWidget when PreferenceWidget closes
  void _preferenceUpdated() {
    debugPrint("HomeWidget.preferenceUpdated()");
    Preference preference = widget.preferences.get(0);
    setState(() {
      _duration = Duration(seconds: preference.duration);
      _appName = preference.name.isEmpty ? APP_NAME : preference.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    if (_status.isEmpty) {
      _status = AppLocalizations.of(context)!.pressStart;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_appName),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.

        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _status,
              style: Theme.of(context).textTheme.headline5,
              semanticsLabel: _status,
            ),
            Center(
                child: Transform.scale(
                    scale: _scale,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Container(
                        width: 150.0,
                        height: 150.0,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ))),
            Text(
              getDurationString(_duration),
              style: Theme.of(context).textTheme.headline5,
              semanticsLabel: getDurationString(_duration),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        // Add a ListView to the drawer. This ensures the user can scroll
        // through the options in the drawer if there isn't enough vertical
        // space to fit everything.
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                image:
                    DecorationImage(image: AssetImage("images/launcher.png")),
              ),
              child: Text(widget.appName),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.preferences),
              leading: Icon(Icons.settings),
              onTap: () {
                _isRunning = false;
                Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PreferencesWidget(
                          preferences: widget.preferences,
                          callback: _preferenceUpdated),
                    ));
              },
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.sessions),
              leading: Icon(Icons.format_list_numbered_outlined),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          SessionsWidget(sessions: widget.sessions)),
                );
              },
            ),
            ListTile(
                title: Text(AppLocalizations.of(context)!.calendar),
                leading: Icon(Icons.calendar_today),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            SessionsCalendarWidget(sessions: widget.sessions)),
                  );
                }),
            SafeArea(
              child: AboutListTile(
                icon: Icon(Icons.info_outline),
                applicationIcon: Image.asset('images/animated.webp'),
                applicationName: widget.appName,
                applicationVersion: widget.version,
                applicationLegalese: COPYRIGHT,
                aboutBoxChildren: [
                  ListTile(
                    title: Text(AppLocalizations.of(context)!.help),
                    leading: Icon(Icons.help),
                    onTap: () {
                      _launchURL(HELP_URL);
                    },
                  ),
                  ListTile(
                    title: Text(AppLocalizations.of(context)!.reportIssue),
                    leading: Icon(Icons.bug_report),
                    onTap: () {
                      _launchURL(BUGS_URL);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _buttonPressed(context);
        },
        tooltip: _isRunning
            ? AppLocalizations.of(context)!.stop
            : AppLocalizations.of(context)!.start,
        child:
            _isRunning ? Icon(Icons.stop_sharp) : Icon(Icons.not_started_sharp),
      ),
    );
  }
}
