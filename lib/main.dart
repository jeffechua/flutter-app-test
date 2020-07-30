import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'interface.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:flutter/services.dart';

Session get session => Session.current;
List<Future<void> Function()> resumeActions = [];

void main() async {
  WidgetsFlutterBinding
      .ensureInitialized(); // prevents weird race condition things?
  await Session().loadPreferences();
  runApp(MyApp());

  SystemChannels.lifecycle.setMessageHandler((msg) async {
    if(msg==AppLifecycleState.resumed.toString()){
      for(var action in resumeActions){
        await action();
      }
      resumeActions.clear();
    }
    return null;
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        routes: {
          '/': (context) => LaunchPage(),
          '/login': (context) => LoginPage(),
          '/confirmlogin': (context) => ConfirmLoginPage(),
          '/interface': (context) => InterfacePage(),
        });
  }

  @override
  dispose() {
    session.close();
    super.dispose();
  }
}

enum LoginMethod { NotLoggedIn, Google }

class Session {
  static http.Client client = http.Client();
  static Session current;
  LoginMethod loginMethod;
  SharedPreferences prefs;
  String _deviceKey;
  Map<String, String> profile;

  String get deviceKey => _deviceKey;

  Session() {
    if (current != null)
      throw Exception("Attempted to init session when one already existed");
    current = this;
    loginMethod = LoginMethod.NotLoggedIn;
  }

  Future<void> loadPreferences() async {
    prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('deviceKey')) {
      _deviceKey = prefs.getString('deviceKey');
    } else {
      generateAndSaveDeviceKey();
    }
  }

  Future<bool> isAuthentic() async => (await get('auth/key')).body == 'valid';

  Future<void> loadProfileData() async => profile =
      Map<String, String>.from(jsonDecode((await get('profile')).body));

  static const String _authority = 'jec226.user.srcf.net';
  static const String _prepath = 'servertest';

  Uri uri(String path, [Map<String, String> parameters]) {
    var params = parameters ?? {};
    if (deviceKey != null) params['device_key'] = deviceKey;
    return Uri.https(_authority, '$_prepath/$path', params);
  }

  Future<http.Response> post(String path, [Map<String, String> parameters]) {
    return client.post(uri(path, parameters)).then((response) {
      if (response.statusCode != HttpStatus.ok)
        throw Exception('\'$path\' POST request with query \'$parameters\' '
            'returned status ${response.statusCode} with body ${response.body}.');
      return response;
    });
  }

  Future<http.Response> get(String path, [Map<String, String> parameters]) {
    var u = uri(path, parameters);
    print(u);
    return client.get(u).then((response) {
      if (response.statusCode != HttpStatus.ok)
        throw Exception('\'$path\' GET request with query \'$parameters\' '
            'returned status ${response.statusCode} with body ${response.body}.');
      return response;
    });
  }

  void generateAndSaveDeviceKey() {
    var r = Random.secure();
    var c = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890";
    _deviceKey =
        List<String>.generate(32, (i) => c[r.nextInt(c.length)]).join();
    prefs.setString('deviceKey', _deviceKey);
  }

  void resetDeviceKey() => generateAndSaveDeviceKey();

  void close() => client.close();
}

class LaunchPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RaisedButton(
                child: Text('Proceed'),
                onPressed: () async {
                  tryAuthenticateWithDeviceKey(context);
                }),
            FlatButton(
                child: Text('Reset device key'),
                onPressed: () => session.resetDeviceKey())
          ],
        ),
      ),
    );
  }

  Future<void> tryAuthenticateWithDeviceKey(BuildContext context) async {
    if(await session.isAuthentic()){
      await session.loadProfileData();
      Navigator.of(context).pushReplacementNamed('/confirmlogin');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }
}

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RaisedButton(
              child: Text('Log in with Google'),
              onPressed: () => tryAuthGoogle(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> tryAuthGoogle(BuildContext context) async {
    if (session.loginMethod != LoginMethod.NotLoggedIn) return;
    session.loginMethod = LoginMethod.Google;
    var authUrl = (await session.get('auth/google/authreq')).body;
    webAuthByUrl(context, authUrl);
    // The query below is held by the server until authorization completes
    var authCompleteQuery = await session.get('auth/wait');
    resumeActions.add(() async {
      if (authCompleteQuery.statusCode == HttpStatus.ok) {
        assert(await session.isAuthentic());
        await session.loadProfileData();
        Navigator.popAndPushNamed(context, '/confirmlogin');
      } else {
        session.loginMethod = LoginMethod.NotLoggedIn;
        authenticationFailed(context);
      }
    });
  }

  void webAuthByUrl(BuildContext context, String authUrl) {
    launch(authUrl, enableJavaScript: true);
  }

  void authenticationFailed(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => SimpleDialog(
              title: const Text('Authentication failed'),
              children: [SimpleDialogOption(child: Text('Ok'))],
            ));
  }
}

class ConfirmLoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authentication successful')),
      body: Column(
        children: [
          Expanded(
              child: Table(
                  children: session.profile.entries
                      .map((entry) => TableRow(
                          children: [Text(entry.key), Text(entry.value)]))
                      .toList())),
          RaisedButton(
            child: Text('Ok'),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed("/interface");
            },
          ),
          FlatButton(
            child: Text('Cancel'),
            onPressed: () {
              session.loginMethod = LoginMethod.NotLoggedIn;
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
    );
  }
}
