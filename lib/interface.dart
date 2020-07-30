import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'main.dart';

enum DatabaseAPIStatus { Inactive, Complete, Pending }

// Static/singleton would probably be equivalently satisfactory
class DatabaseAPI extends ChangeNotifier {
  DatabaseAPIStatus state = DatabaseAPIStatus.Inactive;
  String _query = "";
  List<List<String>> result = [];

  Future<void> queryOwner(String owner) async {
    _query = owner;
    print(_query);
    await refresh();
  }

  Future<void> insertRow(String owner, String content) async => await refresh(
      byaction: session.post('insert', {'owner': owner, 'content': content}));

  Future<void> deleteRow(String owner, String content) async => await refresh(
      byaction: session.post('delete', {'owner': owner, 'content': content}));

  Future<void> refresh({Future<void> byaction, bool sneaky = false}) async {
    state = DatabaseAPIStatus.Pending;
    if (!sneaky) notifyListeners();
    if (byaction != null) await byaction;
    var path = _query == "" ? "all" : 'owner';
    var params = _query == "" ? <String, String>{} : {'owner': _query};
    var text = (await session.get(path, params)).body;
    result = jsonDecode(text)
        .map<List<String>>((e) => e.cast<String>().toList() as List<String>)
        .toList();
    state = DatabaseAPIStatus.Complete;
    notifyListeners();
  }
}

class InterfacePage extends StatelessWidget {
  DatabaseAPI dbApi = DatabaseAPI();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DatabaseAPI>(
      create: (context) => DatabaseAPI(),
      child: Scaffold(
        appBar: AppBar(title: const Text("Test interface to SRCF database")),
        body: Column(
          children: <Widget>[
            IntrinsicHeight(
                child: Padding(
                    padding: EdgeInsets.all(5.0),
                    child: TextField(
                        onSubmitted: (value) => dbApi.queryOwner(value)))),
            Expanded(child: DataViewTable(dbApi)),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => showDialog(
            context: context,
            builder: (__) {
              return SimpleDialog(
                title: const Text('Add new row'),
                children: [AddRowForm(api: dbApi)],
              );
            },
          ),
          child: Icon(Icons.add),
        ),
      ),
    );
  }
}

class DataViewTable extends StatefulWidget {
  final DatabaseAPI api;

  DataViewTable(this.api, {Key key}) : super(key: key);

  @override
  _DataViewTableState createState() => _DataViewTableState();
}

class _DataViewTableState extends State<DataViewTable> {
  final GlobalKey<RefreshIndicatorState> refreshKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    widget.api.addListener(() => setState(() {}));
    var refresh = RefreshIndicator(
        key: refreshKey,
        onRefresh: () => widget.api.refresh(sneaky: true),
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: widget.api.result
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
                        widget.api.result.remove(row);
                        widget.api.deleteRow(row[0], row[1]);
                      },
                    ),
                  ),
                )
                .toList()));
    if (widget.api.state == DatabaseAPIStatus.Pending)
      refreshKey.currentState.show();
    return refresh;
  }
}

// better way of doing this? possible to reduce AddRowForm to stateless?
class AddRowForm extends StatefulWidget {
  final DatabaseAPI api;

  AddRowForm({Key key, this.api}) : super(key: key);

  @override
  _AddRowFormState createState() => _AddRowFormState();
}

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
          pad(TextFormField(
            decoration: const InputDecoration(
                icon: Icon(Icons.person), labelText: 'Owner'),
            validator: (v) => v.length <= 10 && v.isNotEmpty
                ? null
                : "Owner must be 1–10 chars.",
            onSaved: (String value) => owner = value,
          )),
          pad(TextFormField(
            decoration: const InputDecoration(labelText: 'Content'),
            validator: (v) => v.isNotEmpty ? null : "Content cannot be empty.",
            onSaved: (String value) => content = value,
          )),
          pad(
            RaisedButton(
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

  // Standard dialog content padding as per guidelines outlined in
  // https://api.flutter.dev/flutter/material/SimpleDialog/contentPadding.html
  Widget pad(Widget widget) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: widget,
    );
  }
}
