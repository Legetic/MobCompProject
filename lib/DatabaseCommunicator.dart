import 'dart:async';

import 'package:artmap/groups.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'model/Model.dart';

class BlueprintChangeNotifier extends ChangeNotifier {
  DatabaseCommunicator dbCom;
  BlueprintChangeNotifier(this.dbCom);
  late StreamSubscription<DatabaseEvent> databaseSubscription;

  void listenToActiveBlueprintChange(String blueprintID) {
    unsubscribe();
    databaseSubscription = dbCom.listenToUserBlueprintsChange(blueprintID,
        uiCallback: notifyListeners);
  }

  Future<void> initialize() async {
    await dbCom.initFirebase();
    //listenToActiveBlueprintChange();
  }

  void addBlueprint() {
    //
  }

  void unsubscribe() {
    databaseSubscription.cancel();
  }

//Adds a tile to the active blueprint's database
  void addTileToActive(Color color, String geohash) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(dbCom.blueprintsPath);
    print("HERE");

    //reference blueprint ID.
    String? activeBlueprintID =
        dbCom.model.getActiveBlueprint()?.getBlueprintID();
    print("HERE2: $activeBlueprintID");
    print("HERE3: ${dbCom.model.getCurrentUser().getAvailableBlueprints()}");

    if (activeBlueprintID != null)
      print("The active blueprint ID: $activeBlueprintID");

    //Add tile to database if we have a valid active blueprint
    if (activeBlueprintID != null) {
      DatabaseReference activeBlueprintRef = ref.child(activeBlueprintID);

      DatabaseReference newTileRef =
          activeBlueprintRef.child("tiles").child(geohash);
      //print("newtile: " + newTileRef.path);

      await newTileRef.set({"r": color.red, "g": color.green, "b": color.blue});
    }

    //notifyListeners();
  }
}

//Notifies the consumer of changes to the map database as well
class MapChangeNotifier extends ChangeNotifier {
  DatabaseCommunicator dbCom;
  MapChangeNotifier(this.dbCom);
  late StreamSubscription<DatabaseEvent> databaseSubscription;

  Future<void> initialize() async {
    await dbCom.initFirebase();
    _listenToTilesChange();
  }

  void _listenToTilesChange() {
    databaseSubscription =
        dbCom.listenToMapTilesChange(uiCallback: notifyListeners);
  }

  void unsubscribe() {
    databaseSubscription.cancel();
  }

  //Uses transactions to change data that might get corrupted due to concurrent changes.
  //SUCH AS: editing a blot on the map.
  //It seems that a transaction can both get and post data in one go which should be CHEAPER $$$$$$ and also handles concurrency issues.
  void addTile(Color color, String geohash) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(dbCom.tilesPath);
    DatabaseReference newTileRef = ref.child(geohash);
    //print("newtile: " + newTileRef.path);

    await newTileRef.set({"r": color.red, "g": color.green, "b": color.blue});

    //notifyListeners();
  }
}

//https://firebase.google.com/docs/flutter/setup?platform=android
//https://firebase.google.com/docs/database/flutter/start
//https://firebase.google.com/docs/database/flutter/structure-data
//This is the base communicator which has all functionality needed to communicate with the firebase database.
class DatabaseCommunicator {
  late final secureLocalStorage;
  //We instantiate the model here.
  late final Model model;

  final String tilesPath = "Tiles";
  final String usersPath = "Users";
  final String groupsPath = "Groups";
  final String blueprintsPath = "Blueprints";

  bool _hasBeenInitialized = false;

  final String _personalBlueprintName = "Personal Blueprint";

  //TODO USE THIS.
  //List<StreamSubscription<DatabaseEvent>> databaseSubscriptions = [];

  DatabaseCommunicator(this.model) {
    secureLocalStorage = FlutterSecureStorage();

    //initFirebase();
  }

  Future<void> initFirebase() async {
    if (_hasBeenInitialized) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print("Inititializing database.");
    await _initUser();
    _hasBeenInitialized = true;

    //_listenToTilesChange();
  }

  //You can use the DatabaseEvent to read the data at a given path, as it exists at the time of the event. This event is triggered once when the listener is attached and again every time the data, including any children, changes.
  //Important: A DatabaseEvent is fired every time data is changed at the specified database reference, including changes to children. To limit the size of your snapshots, attach only at the highest level needed for watching changes. For example, attaching a listener to the root of your database is not recommended.
  //PREFER USING THIS OVER GET BECAUSE ITS CHEAPER (IN MONEY IT DOESN'T COST AS MUCH)
  //This is called once when the listener is attached and then everytime it changes.
  StreamSubscription<DatabaseEvent> listenToDataChange(String databasePath,
      Function(String?, Map<String, dynamic>) customCallback,
      {String? key}) {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference databaseRef = database.ref(databasePath);
    if (key != null) databaseRef = databaseRef.child(key);

    var subscription = databaseRef.onValue.listen((DatabaseEvent event) {
      //Do something when the data at this path changes.
      final data = event.snapshot.value;

      //print(data.runtimeType.toString());
      if (data != null) {
        Map<String, dynamic> dataMap = Map<String, dynamic>.from(data as Map);
        //Do something with the data
        customCallback(key, dataMap);
      }
    });

    return subscription;
  }

  //Generate events when anything in the user database changes, such as the number of blueprints changes
  StreamSubscription<DatabaseEvent> listenToUserChanges(String userID,
      {Function? uiCallback}) {
    StreamSubscription<DatabaseEvent> newSub =
        listenToDataChange(usersPath, _updateUserModel, key: userID);
    //databaseSubscriptions.add(newSub);
    return newSub;
  }

  StreamSubscription<DatabaseEvent> listenToUserBlueprintsChange(
      String blueprintID,
      {Function? uiCallback}) {
    StreamSubscription<DatabaseEvent> newSub = listenToDataChange(
        blueprintsPath, _updateUserBlueprintsModel,
        key: blueprintID);
    //databaseSubscriptions.add(newSub);
    return newSub;
  }

  StreamSubscription<DatabaseEvent> listenToMapTilesChange(
      {Function? uiCallback}) {
    StreamSubscription<DatabaseEvent> newSub =
        listenToDataChange(tilesPath, _updateTilesModel);
    //databaseSubscriptions.add(newSub);
    return newSub;
  }

// FUNCTIONS THAT POPULATE THE MODEL WITH DATA ----------------------------------------------------
/* void _saveBlueprintTileToModel(String? _, Map<String?, dynamic> data) {
    List<ColoredTile> newBlueprintTilesList = [];
    print(data.toString());
    data.forEach((key, value) {
      if (value != null && key != null) {
        Map<String, dynamic> tile = Map<String, dynamic>.from(value);
        //The assumption here is that "value" is another map.
        newBlueprintTilesList.add(ColoredTile.fromMap(key, tile));
      }
    });

    //Update active blueprint in model
    dbCom.model.getActiveBlueprint()?.setTiles(newBlueprintTilesList);
  } */

  Future<void> _initUserModel(String userID) async {
    DatabaseReference ref =
        FirebaseDatabase.instance.ref(usersPath + "/" + userID);
    // Get the data once
    DatabaseEvent event = await ref.once();
    final data = event.snapshot.value;
    if (data != null) {
      Map<String, dynamic> dataMap = Map<String, dynamic>.from(data as Map);
      //Do something with the data
      _updateUserModel(userID, dataMap);
    }
  }

  void _updateUserModel(String? userID, Map<String, dynamic> data,
      {Function? uiCallback}) async {
    //print("What is this:" + data.keys.toString());
    if (data != null) {
      Map<String, dynamic> dataMap = Map<String, dynamic>.from(data);

      //GROUPS
      Map<String, dynamic> groups = {};
      if (dataMap["groups"] != null && dataMap["groups"] != false) {
        groups = Map<String, dynamic>.from(dataMap["groups"]);
      }

      //SAVING TO MODEL
      //Look in other places of the database to gather data and save to model.
      await _updateUserGroups(userID, groups, uiCallback: uiCallback);
      await _updateUserBlueprintsModel(userID, groups, uiCallback: uiCallback);

      if (dataMap["activeBlueprintID"] != null &&
          dataMap["activeBlueprintID"] != false) {
        print("TJAAAAAA ${model.getCurrentUser().getAvailableBlueprints()}");
        model.setActiveBlueprint(dataMap["activeBlueprintID"]);
      } else if (userID != null) {
        //changeActiveBlueprint(userID, _personalBlueprintName);
        model.setActiveBlueprint(userID);
      }
    }
  }

  Future<void> _updateUserBlueprintsModel(
      String? userID, Map<String, dynamic> groups,
      {Function? uiCallback}) async {
    final ref = FirebaseDatabase.instance.ref().child(blueprintsPath);

    //BLUEPRINTS
    //The userID is NOT a group however it is a blueprint, so add it here.
    List<String> groupIDs = groups.keys.toList();
    //List<String> blueprintIDs = List.from(groupIDs);
    if (userID != null) groupIDs.add(userID);

    List<Blueprint> newBlueprintsList = [];

    for (var iD in groupIDs) {
      //print(iD.toString());
      DatabaseReference groupRef = ref.child(iD);
      var snapshot = await groupRef.get();

      if (snapshot.exists) {
        //Do something when the data at this path changes.
        final data = snapshot.value;

        if (data != null) {
          //print("The data: " + data.toString());

          Map<String, dynamic> blueprintData =
              Map<String, dynamic>.from(data as Map);

          //Add the blueprint to the model
          Blueprint blueprint = Blueprint.fromMap(iD, blueprintData);
          print("DA FOOKIN BLUEPRINT ${blueprint.getBlueprintID()}");
          newBlueprintsList.add(blueprint);
        }
      } else {
        print('No data available.');
      }
    }

    //Set users blueprint list to these blueprints
    model.setUserBlueprints(newBlueprintsList);

    print("TJOOOOO ${newBlueprintsList}");
    //print(data.runtimeType.toString());
    if (uiCallback != null) uiCallback();
  }

  Future<void> _updateUserGroups(String? userID, Map<String, dynamic> groups,
      {Function? uiCallback}) async {
    final ref = FirebaseDatabase.instance.ref().child(groupsPath);

    List<String> groupIDs = groups.keys.toList();
    List<Group> newGroupsList = [];

    for (var iD in groupIDs) {
      //print(iD.toString());
      DatabaseReference groupRef = ref.child(iD);
      var snapshot = await groupRef.get();

      if (snapshot.exists) {
        //Do something when the data at this path changes.
        final data = snapshot.value;
        if (data != null) {
          //print("The data: " + data.toString());

          Map<String, dynamic> dataMap = Map<String, dynamic>.from(data as Map);

          //Add the blueprint to the model
          Group group = Group.fromMap(iD, dataMap);
          newGroupsList.add(group);
        }
      } else {
        print('No data available.');
      }
    }

    //Set users blueprint list to these blueprints
    model.setUserGroups(newGroupsList);

    //print(data.runtimeType.toString());
    if (uiCallback != null) uiCallback();
  }

  void _updateTilesModel(String? _, Map<String, dynamic> data,
      {Function? uiCallback}) {
    List<ColoredTile> newTilesList = [];

    data.forEach((key, value) {
      if (value != null && key != null) {
        Map<String, dynamic> tile = Map<String, dynamic>.from(value);
        //The assumption here is that "value" is another map.
        newTilesList.add(ColoredTile.fromMap(key, tile));
      }
    });

    model.setTiles(newTilesList);
    //Notify the ui that the database has changed.
    if (uiCallback != null) uiCallback();
  }

//SAFE STORAGE FUNCTIONS --------------------------------------------------------------------------
  void _saveSecureStringLocally(String key, String? userID) async {
    // Write value
    if (userID != null) {
      await secureLocalStorage.write(key: key, value: userID);
    } else {
      print("Could not save since returned key is null");
    }
  }

  Future<String?> _getLocalSecureString(String key) async {
    // Read value
    String? value = await secureLocalStorage.read(key: key);

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
    //TODO REMOVE
    leaveAllGroups();
    removeAllGroups();
    removeAllBlueprints();
    clearLocalSafeStorage();
    removeAllUsers();
    //----------

    _getAndroidOptions();
    String? userID = await _getLocalSecureString("uID");
    User currentUser;

    if (userID == null) {
      //Get new user ID
      userID = await _createNewUser();
      if (userID != null) {
        currentUser = User(userID);
        model.setCurrentUser(currentUser);

        _saveSecureStringLocally("uID", userID);

        //Retrieve saved data on database and populate model.
        await _initUserModel(userID);
      }
    } else {
      //We have the ID locally, meaning user exists
      currentUser = User(userID);
      model.setCurrentUser(currentUser);
      //TODO make sure userID exists in the database as well?

      //Retrieve saved data on database and populate model.
      await _initUserModel(userID);

      /* //Try to retrieve old active blueprint
      String? blueprintID = await _getLocalSecureString("activeBlueprintID");
      String? blueprintName =
          await _getLocalSecureString("activeBlueprintName");
      if (blueprintID != null && blueprintName != null) {
        //We found old active blueprint, try to retrieve it
        print(blueprintID + " " + blueprintName);
        changeActiveBlueprint(blueprintID, blueprintName);
      } else {
        //We did not find old active blueprint set to personal
        changeActiveBlueprint(userID, _personalBlueprintName);
      } */
    }

    // listen to changes in the current user's subdatabase
    //Needed to set the listener here and use initUserModel so we could wait on it,
    //Although they do the same thing ones triggered since the listener is triggered directly.

    if (userID != null) {
      listenToUserChanges(userID);
    }
  }

  void _initPersonalBlueprint(String userID) async {
    //Blueprint newBlueprint = Blueprint(userID, _personalBlueprintName);
    print("INIT PERSONAL");

    await _createNewBlueprintOnDatabase(userID, _personalBlueprintName);

    //Set this as the active one as we dont have any active blueprint in the beginning
    changeActiveBlueprint(userID, userID, _personalBlueprintName);
  }

  void changeActiveBlueprint(
      String userID, String blueprintID, String blueprintName) {
    print("CHANGING ACTIVE BLUEPRINT");

    _pushEntryWithExistingKey(usersPath, userID,
        postData: {"activeBlueprintID": blueprintID});
  }

  Future<void> _createNewBlueprintOnDatabase(String key, String name) async {
    //FirebaseDatabase database = FirebaseDatabase.instance;
    //DatabaseReference ref = database.ref().child(blueprintsPath);
    print("CREATING NEW");
    _pushEntryWithExistingKey(blueprintsPath, key,
        postData: {"blueprintName": name, "tiles": false});
  }

//Create a new group on the database
  void addGroup(String groupName, String description) async {
    Map<String, dynamic> newGroupData = {
      "name": groupName,
      "description": description,
      "membercount": 0,
    };

    String? gID = await _pushEntryWithUniqeGeneratedKey(groupsPath,
        postData: newGroupData);

    //Also create a matching blueprint for the group
    if (gID != null) {
      _createNewBlueprintOnDatabase(gID, groupName);
    }
  }

  void joinGroup(String groupID) {
    String? currentUserID = model.getCurrentUser().getUserID();
    if (currentUserID != null) {
      //TODO only join the group if it actually exists.

      _pushEntryWithExistingKey(usersPath + "/" + currentUserID + "/groups", "",
          postData: {groupID: true});
      //print(usersPath + "/" + currentUserID + "/groups");
    }
  }

  void leaveAllGroups() {
    String? uID = model.getCurrentUser().getUserID();
    if (uID != null) {
      _removeData(usersPath + "/" + uID + "/groups");
    }
  }

  void removeAllGroups() {
    _removeData(groupsPath);
  }

  void removeAllBlueprints() {
    _removeData(blueprintsPath);
  }

  void removeAllUsers() {
    _removeData(usersPath);
  }

  Future<String?> _createNewUser() async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(usersPath);

    //TODO generate a new ID.
    // A post entry.

    // Get a key for a new user.
    final newPostKey = ref.push().key;

    final postData = {"groups": null};
    final Map<String, dynamic> updates = {};
    updates['groups'] = false;
    updates['activeBlueprintID'] = false;

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
/*     final Map<String, Map> updates = {};
    updates['/$newPostKey'] = postData;
    //updates['/user-posts/$uid/$newPostKey'] = postData;
    //print("Här");

    ref.update(updates).then((_) {
      // Data saved successfully!
      print("Data saved Successfully");
    }).catchError((error) {
      // The write failed...
      print("Data write failed");
    }); */

    //Also create a matching blueprint for the group
    if (newPostKey != null) {
      DatabaseReference newEntryRef = ref.child(newPostKey);

      await newEntryRef.update(updates).then((_) {
        // Data saved successfully!
        print("Data saved Successfully");
      }).catchError((error) {
        // The write failed...
        print("Data write failed");
      });

      _initPersonalBlueprint(newPostKey);
    }

    //return FirebaseDatabase.instance.ref().update(updates);
    return newPostKey;
  }

  //Returns the key
  Future<String?> _pushEntryWithUniqeGeneratedKey(String databasePath,
      {Map<String, dynamic> postData = const {}}) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(databasePath);

    //generate a new ID.
    final newPostKey = ref.push().key;

    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    final Map<String, Map> updates = {};
    updates['$newPostKey'] = postData;
    //updates['$newPostKey'] = postData;

    ref.update(updates).then((_) {
      // Data saved successfully!
      print("Data saved Successfully");
    }).catchError((error) {
      // The write failed...
      print("Data write failed");
    });

    return newPostKey;
  }

  Future<void> _pushEntryWithExistingKey(String databasePath, String key,
      {Map<String, dynamic> postData = const {}}) async {
    FirebaseDatabase database = FirebaseDatabase.instance;
    DatabaseReference ref = database.ref().child(databasePath);
    DatabaseReference newEntryRef = ref.child(key);
    // Write the new post's data simultaneously in the posts list and the
    // user's post list.
    //final Map<String, Map> updates = {};
    //updates['$key'] = postData;
    //updates['$newPostKey'] = postData;
    //print(databasePath + "/" + key);

    await newEntryRef.update(postData).then((_) {
      // Data saved successfully!
      print("Data saved Successfully");
    }).catchError((error) {
      // The write failed...
      print("Data write failed");
    });
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
