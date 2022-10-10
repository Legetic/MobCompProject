import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'model/Model.dart';

//https://firebase.google.com/docs/flutter/setup?platform=android
//https://firebase.google.com/docs/database/flutter/start
//https://firebase.google.com/docs/database/flutter/structure-data
class DatabaseCommunicator extends ChangeNotifier {
  late final secureLocalStorage;
  //We instantiate the model here.
  late final Model model;

  static const String tilesPath = "Tiles";
  static const String usersPath = "Users";

  DatabaseCommunicator(this.model) {
    secureLocalStorage = FlutterSecureStorage();
    //model = Model();
    initFirebase();
  }

  Future<void> initFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print("Inititializing database.");
    await _initUser();

    _listenToTilesChange();
  }

/*
  //Overwrites all data at specified location
  Future<void> setUser(User user) async {
    //String? userID = user.getUserID();
    //DatabaseReference ref = database.ref("users/$userID");
    FirebaseDatabase database = FirebaseDatabase.instance;

    DatabaseReference ref = database.ref().child("Users");
    //DatabaseReference ref = FirebaseDatabase.instance.ref("Users/");

    //Probably needs to specify all data at top location.
    await ref.set({
      "name": "Joel",
    }).then((_) {
      // Data saved successfully!
    }).catchError((error) {
      // The write failed...
    });
    ;
  }
*/

/*
  //Updates specified data of user.
  Future<void> updateUserName(User user, String newUserName) async {
    String userID = user.getUserID();
    DatabaseReference ref = database.ref("users/$userID");

    // Only update the one property!
    await ref.update({
      "name": newUserName,
    }).then((_) {
      // Data saved successfully!
    }).catchError((error) {
      // The write failed...
    });
  } */

  /* The update() method accepts a sub-path to nodes, allowing you to update multiple nodes on the database at once:

  DatabaseReference ref = FirebaseDatabase.instance.ref("users");

  await ref.update({
    "123/age": 19,
    "123/address/line1": "1 Mountain View",
  }); */

  //You can use the DatabaseEvent to read the data at a given path, as it exists at the time of the event. This event is triggered once when the listener is attached and again every time the data, including any children, changes.
  //Important: A DatabaseEvent is fired every time data is changed at the specified database reference, including changes to children. To limit the size of your snapshots, attach only at the highest level needed for watching changes. For example, attaching a listener to the root of your database is not recommended.
  //PREFER USING THIS OVER GET BECAUSE ITS CHEAPER (IN MONEY IT DOESN'T COST AS MUCH)
  //This is called once when the listener is attached and then everytime it changes.
  void _listenToDataChange(
      String databasePath, Function(Map<String, dynamic>) customCallback) {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference databaseRef = database.ref(databasePath);
    databaseRef.onValue.listen((DatabaseEvent event) {
      //Do something when the data at this path changes.
      final data = event.snapshot.value;

      //print(data.runtimeType.toString());
      if (data != null) {
        Map<String, dynamic> dataMap = Map<String, dynamic>.from(data as Map);
        //Do something with the data
        customCallback(dataMap);
      }
      //Map<String, dynamic> dataMap = Map<String, dynamic>.from(data as Map);
      //Do something with the data
      //customCallback(dataMap);
      /* () {
        print("Tjaaasa");
      }(); */

      //Rebuild everything that depends on the database
      notifyListeners();
      //updateStarCount(data);
      //print(data);
    });
  }

  void _listenToTilesChange() {
    _listenToDataChange(tilesPath, _saveTilesToModel);
  }

  void _saveTilesToModel(Map<String, dynamic> data) {
    List<ColoredTile> newTilesList = [];
    //print("AAAAAAAAAAAA");

    //print("Found data in database" + data.toString());

    data.forEach((key, value) {
      if (value != null && key != null) {
        //print("val: " + value.runtimeType.toString());
        Map<String, dynamic> tile = Map<String, dynamic>.from(value);
        //The assumption here is that "value" is another map.
        newTilesList.add(ColoredTile.fromMap(key, tile));
        //print(newTilesList);

        //print("tile gathered" + ColoredTile.fromMap(key, tile).toString());
      }
    });

    model.setTiles(newTilesList);
  }

/*
//WARNING DONT USE THIS, UNLESS ABSOLUTELY NECESSARY.
  void getData(String databasePath) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(databasePath);

    final snapshot = await ref.get();
    if (snapshot.exists) {
      print(snapshot.value);
    } else {
      print('No data available.');
    }
  }

  //For data that changes infrequently, like never, and needs to be fetched once use this
  void getDataOnce(String databasePath) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(databasePath);

    final event = await ref.once(DatabaseEventType.value);
    //final username = event.snapshot.value?.username ?? 'Anonymous';
    //Read the data from the event.
  }
*/

//SAFE STORAGE FUNCTIONS ----------------------------------------------
  void _saveUserIDLocally(String? userID) async {
    // Write value
    if (userID != null) {
      await secureLocalStorage.write(key: "uID", value: userID);
    } else {
      print("Could not save since returned key is null");
    }
  }

  Future<String?> _getLocalUserID() async {
    // Read value
    String? value = await secureLocalStorage.read(key: "uID");

    return value;
  }

  Future<void> clearLocalSafeStorage() async {
    // Read value
    await secureLocalStorage.deleteAll();
  }

//Make it so that android is using EncryptedSharedPreferenses
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

//Initializes a new user if needed.
  Future<void> _initUser() async {
    _getAndroidOptions();
    String? userID = await _getLocalUserID();
    if (userID == null) {
      String? generatedKey = await _createNewUser();
      _saveUserIDLocally(generatedKey);
    } else {
      //We have the ID locally, make sure it exists in the database as well?

    }
  }

  Future<String?> _createNewUser() async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(usersPath);

    //TODO generate a new ID.
    // A post entry.

    // Get a key for a new user.
    final newPostKey = ref.push().key;

    final postData = {
      'groups': "",
    };

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    final Map<String, Map> updates = {};
    updates['/Users/$newPostKey'] = postData;
    //updates['/user-posts/$uid/$newPostKey'] = postData;
    //print("Här");

    FirebaseDatabase.instance.ref().update(updates).then((_) {
      // Data saved successfully!
      print("Data saved Successfully");
    }).catchError((error) {
      // The write failed...
      print("Data write failed");
    });

    //return FirebaseDatabase.instance.ref().update(updates);
    return newPostKey;
  }

//Just use these to see that we can post anything.
  /* Future<void> connectionTest() async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref();
    print("conn test");

    final newPostKey = ref.push().key;
    print(newPostKey);

    final postData = {
      'groups': "",
    };

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    final Map<String, Map> updates = {};
    updates['/Test/$newPostKey'] = postData;
    //updates['/user-posts/$uid/$newPostKey'] = postData;

    FirebaseDatabase.instance.ref().update(updates).then((_) {
      // Data saved successfully!
      print("Data saved Successfully");
    }).catchError((error) {
      // The write failed...
      print("Data write failed");
    });
  } */

  void removeAllTiles() {
    _removeData(tilesPath);
  }

  void _removeData(String databasePath) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref(databasePath);
    await ref.remove().then((_) {
      // Data removed successfully!
    }).catchError((error) {
      // The remove failed...
    });
    //notifyListeners();
  }
/*

  void removeMultiple(String name) async {
    //TODO generate a new ID.
    // A post entry.
    final postData = {null};

    // Get a key for a new user.
    final newPostKey = database.ref('users').push().key;
    User newUser = User(name, newPostKey);

    final Map<String, Map> updates = {};
    updates['/posts/$newPostKey'] = postData;
    updates['/user-posts/$uid/$newPostKey'] = postData;

    return FirebaseDatabase.instance.ref().update(updates);
  }

    */

  //Uses transactions to change data that might get corrupted due to concurrent changes.
  //SUCH AS: editing a blot on the map.
  //It seems that a transaction can both get and post data in one go which should be CHEAPER $$$$$$ and also handles concurrency issues.
  void addTile(Color color, String geohash) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(tilesPath);
    DatabaseReference newTileRef = ref.child(geohash);
    //print("newtile: " + newTileRef.path);

    await newTileRef.set({"r": color.red, "b": color.green, "g": color.blue});
  }

  //Using atomic server-side increments.
  //Doesn't get automatically rerun if conflict but there should not be any conflicts since the increment is run directly on the server.
  /* void addStar(uid, key) async {
    Map<String, Object?> updates = {};
    updates["posts/$key/stars/$uid"] = true;
    updates["posts/$key/starCount"] = ServerValue.increment(1);
    updates["user-posts/$key/stars/$uid"] = true;
    updates["user-posts/$key/starCount"] = ServerValue.increment(1);
    return FirebaseDatabase.instance.ref().update(updates);
  } */
}
