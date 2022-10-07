import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final MapController _mapController = MapController();
  late Stream<MapEvent> _mapStream;
  late GeoMap geomap;
  Color selectedColor = Colors.blue;

  initMap(){
    _mapStream = _mapController.mapEventStream;
    geomap = GeoMap(_mapController);

    //geomap.populateGrid();

    //Checks for user taps
    _mapStream.listen((event) {
      if(event.source == MapEventSource.tap) {
        MapEventTap tap = event as MapEventTap;
        setState(() {
          geomap.addPolygon(tap.tapPosition, selectedColor);
        });
      } else {
        setState(() {
          geomap.populateGrid();
        });
      }
    });
  }

  @override
  void initState() {
    initMap();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("map"),
      ),
      body: Center(
        child: Container(
          height: 800,
          child: geomap.showMap(),
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(icon: Icon(Icons.palette),
              onPressed: () {
              }),
            IconButton(icon: Icon(Icons.architecture), onPressed: () {}),
            IconButton(icon: Icon(Icons.opacity), onPressed: () {}),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButtoncd(
        backgroundColor: selectedColor,
        onPressed: () {
          setState(() {
            if(selectedColor == Colors.black){
              selectedColor = Colors.blue;
            } else {
              selectedColor = Colors.black;
            }
          });
        },
        child: const Icon(Icons.palette),
      ),
    );
  }
}

//void OpenBottomSheet(){
//}

class ColorSelector extends StatefulWidget {
  const ColorSelector({Key? key}) : super(key: key);

  @override
  State<ColorSelector> createState() => _ColorSelectorState();
}

class _ColorSelectorState extends State<ColorSelector> {
  @override
  Widget build(BuildContext context) {
    return Container(

    );
  }
}
