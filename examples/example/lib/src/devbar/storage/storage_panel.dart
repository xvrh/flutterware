import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutterware/devbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoragePlugin extends DevbarPlugin {
  final DevbarState devbar;

  StoragePlugin(this.devbar) {
    devbar.ui.addTab(Tab(text: 'Storage'), StoragePanel());
  }

  @override
  void dispose() {}
}

class StoragePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var devbar = DevbarState.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: TabBar(
          tabs: [
            Tab(child: Text('Preferences')),
            Tab(child: Text('Secure')),
            //Tab(child: Text('Variables')),
          ],
          isScrollable: true,
        ),
        body: TabBarView(
          children: [
            _SharedPreferencesList(),
            _SecureStorageList(),
            //_VariablesStorageList(devbar.variables.savedData),
          ],
        ),
      ),
    );
  }
}

class _SharedPreferencesList extends StatefulWidget {
  @override
  __SharedPreferencesListState createState() => __SharedPreferencesListState();
}

class __SharedPreferencesListState extends State<_SharedPreferencesList> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        }
        var preferences = snapshot.data;
        if (preferences != null) {
          return ListView(
            children: [
              for (var key in preferences.getKeys())
                ListTile(
                  title: Text(key),
                  subtitle: Text(preferences.get(key).toString()),
                  trailing: IconButton(
                    onPressed: () {
                      setState(() {
                        preferences.remove(key);
                      });
                    },
                    icon: Icon(Icons.delete),
                  ),
                ),
            ],
          );
        } else {
          return Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}

final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class _SecureStorageList extends StatefulWidget {
  @override
  __SecureStorageListState createState() => __SecureStorageListState();
}

class __SecureStorageListState extends State<_SecureStorageList> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _secureStorage.readAll(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        }

        var allValues = snapshot.data;
        if (allValues != null) {
          return ListView(
            children: [
              for (var key in allValues.keys)
                ListTile(
                  title: Text(key),
                  subtitle: Text(allValues[key].toString()),
                  trailing: IconButton(
                    onPressed: () {
                      setState(() {
                        _secureStorage.delete(key: key);
                      });
                    },
                    icon: Icon(Icons.delete),
                  ),
                ),
            ],
          );
        } else {
          return Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}

// class _VariablesStorageList extends StatefulWidget {
//
//   const _VariablesStorageList({Key? key}) : super(key: key);
//
//   @override
//   __VariablesStorageListState createState() => __VariablesStorageListState();
// }
//
// class __VariablesStorageListState extends State<_VariablesStorageList> {
//   @override
//   Widget build(BuildContext context) {
//     var devbar = DevbarState.of(context);
//     return ListView(
//       children: [
//         for (var entry in devbar.variables.savedData.values.entries)
//           ListTile(
//             title: Text(entry.key),
//             subtitle: Text(entry.value.toString()),
//             trailing: IconButton(
//               onPressed: () {
//                 setState(() {
//                   widget.data.values.remove(entry.key);
//                   widget.data.saveValues(widget.data.values);
//                 });
//               },
//               icon: Icon(Icons.delete),
//             ),
//           ),
//       ],
//     );
//   }
// }
