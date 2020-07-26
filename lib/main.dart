import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.green,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: ChangeNotifierProvider<API>(
        create: (context) => API(),
        child: DataViewPage(),
      ),
    );
  }
}

enum APIState { Inactive, Complete, Pending }

class API extends ChangeNotifier {
  final String url = 'https://jec226.user.srcf.net/servertest/';
  APIState state = APIState.Inactive;

  String _query = "";
  List<List<String>> result = [];

  Future<void> queryOwner(String owner) async {
    _query = owner;
    await refreshResults();
  }

  Future<void> insertRow(String owner, String content) async {
    await refreshResults(
        byaction: http
            .post(url + "insert", body: {'owner': owner, 'content': content}));
  }

  Future<void> deleteRow(String owner, String content) async {
    await refreshResults(
        byaction: http
            .post(url + "delete", body: {'owner': owner, 'content': content}));
  }

  Future<void> refreshResults(
      {Future<void> byaction, bool notifyBeforeGetting = true}) async {
    state = APIState.Pending;
    if (notifyBeforeGetting) notifyListeners();
    if (byaction != null) await byaction;
    // getting the data
    var address = url + (_query == "" ? "all" : ("owner/" + _query));
    var text = (await http.get(address)).body;
    result = jsonDecode(text)
        .map<List<String>>(
            (e) => e.map<String>((d) => d as String).toList() as List<String>)
        .toList();
    print(result);
    // finish up
    state = APIState.Complete;
    notifyListeners();
  }
}

class DataViewPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Test interface to SRCF database"),
      ),
      body: Column(
        children: <Widget>[
          IntrinsicHeight(
              child: Padding(
                  padding: EdgeInsets.all(5.0),
                  child: TextField(
                      onSubmitted: (String value) =>
                          Provider.of<API>(context, listen: false)
                              .queryOwner(value)))),
          Expanded(child: DataViewTable()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(
          context: context,
          builder: (__) {
            return SimpleDialog(
              title: const Text('Add new row'),
              children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: AddRowForm(api: Provider.of<API>(context))),
              ],
            );
          },
        ),
        child: Icon(Icons.add),
      ),
    );
  }
}

class AddRowForm extends StatefulWidget {
  final API api;

  AddRowForm({Key key, this.api}) : super(key: key);

  @override
  _AddRowFormState createState() => _AddRowFormState();
}

// better way of doing this? possible to reduce AddRowForm to stateless?
class _AddRowFormState extends State<AddRowForm> {
  final formKey = GlobalKey<FormState>();
  String owner;
  String content;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          TextFormField(
            decoration: const InputDecoration(
                icon: Icon(Icons.person), labelText: 'Owner'),
            validator: (value) => value.length <= 10 && value.isNotEmpty
                ? null
                : "Owner must be between 1–10 characters.",
            onSaved: (String value) => owner = value,
          ),
          TextFormField(
            decoration: const InputDecoration(labelText: 'Content'),
            validator: (value) =>
                value.isNotEmpty ? null : "Content cannot be empty.",
            onSaved: (String value) => content = value,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: RaisedButton(
              onPressed: () {
                if (formKey.currentState.validate()) {
                  formKey.currentState.save();
                  widget.api.insertRow(owner, content);
                  Navigator.pop(context);
                }
              },
              child: Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}

class DataViewTable extends StatefulWidget {
  @override
  _DataViewTableState createState() => _DataViewTableState();
}

class _DataViewTableState extends State<DataViewTable> {
  final GlobalKey<RefreshIndicatorState> refreshKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    var api = Provider.of<API>(context);
    var refresh = RefreshIndicator(
        key: refreshKey,
        onRefresh: () => api.refreshResults(notifyBeforeGetting: false),
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: api.result
                .map<Widget>(
                  (row) => Padding(
                    padding: EdgeInsets.all(5.0),
                    child: Dismissible(
                      key: ObjectKey(row),
                      direction: DismissDirection.startToEnd,
                      child: Row(children: [
                        Text(row[0]),
                        Expanded(child: Text("")),
                        Text(row[1])
                      ]),
                      onDismissed: (dir) {
                        api.result.remove(row);
                        api.deleteRow(row[0], row[1]);
                      },
                    ),
                  ),
                )
                .toList()));
    if (api.state == APIState.Pending) refreshKey.currentState.show();
    return refresh;
  }
}
