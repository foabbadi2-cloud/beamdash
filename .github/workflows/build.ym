import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// ---- Telemetry (BeamNG OutGauge / LFS format, 92 bytes, little endian) ----
class Telemetry {
  double speedMs = 0, rpm = 0, turbo = 0, temp = 0, fuel = 0, oilP = 0, oilT = 0, thr = 0, brk = 0, clu = 0;
  int gear = 1; // 0=R 1=N 2=1st ...
  String car = '';
  String get gearLabel => gear == 0 ? 'R' : gear == 1 ? 'N' : '${gear - 1}';
}

Telemetry? parseOutGauge(Uint8List d) {
  if (d.length < 92) return null;
  final b = ByteData.sublistView(d);
  double f(int o) => b.getFloat32(o, Endian.little);
  return Telemetry()
    ..car = String.fromCharCodes(d.sublist(4, 8)).replaceAll('\u0000', '')
    ..gear = d[10]
    ..speedMs = f(12) ..rpm = f(16) ..turbo = f(20) ..temp = f(24) ..fuel = f(28)
    ..oilP = f(32) ..oilT = f(36) ..thr = f(48) ..brk = f(52) ..clu = f(56);
}

class Feed {
  final data = ValueNotifier<Telemetry>(Telemetry());
  final status = ValueNotifier<String>('Idle');
  RawDatagramSocket? _sock; Timer? _demo, _watchdog; DateTime _last = DateTime(2000);
  Future<void> listen({int port = 4444}) async {
    _demo?.cancel(); _sock?.close();
    try {
      _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      status.value = 'Listening on UDP $port';
      _sock!.listen((e) {
        if (e == RawSocketEvent.read) {
          final p = _sock!.receive(); if (p == null) return;
          final t = parseOutGauge(p.data); if (t == null) return;
          _last = DateTime.now(); data.value = t; status.value = 'Live';
        }
      });
    } catch (e) { status.value = 'Socket error: $e'; }
  }
  void demo() {
    _sock?.close(); status.value = 'Demo mode';
    final sw = Stopwatch()..start();
    _demo = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final t = sw.elapsedMilliseconds / 1000.0;
      final s = (sin(t / 3) + 1) / 2;
      data.value = Telemetry()
        ..speedMs = s * 45 ..rpm = 900 + (s * 5500) ..gear = 2 + (s * 5).floor()
        ..temp = 90 ..fuel = 0.62 ..thr = s ..brk = 1 - s ..car = 'sbr';
    });
  }
}

/// ---- Car profiles (assets/cars.json; edit/extend freely) ----
class CarProfile {
  final String code, name, real; final double maxRpm, red, maxKmh; final Color accent;
  CarProfile(Map j)
      : code = j['code'], name = j['name'], real = j['real'],
        maxRpm = (j['maxRpm'] as num).toDouble(), red = (j['red'] as num).toDouble(),
        maxKmh = (j['maxKmh'] as num).toDouble(),
        accent = Color(int.parse('FF${(j['accent'] as String).substring(1)}', radix: 16));
}
CarProfile fallback = CarProfile({'code': '', 'name': 'Generic', 'real': '-', 'maxRpm': 7000, 'red': 6200, 'maxKmh': 240, 'accent': '#4FC3F7'});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  WakelockPlus.enable();
  final cars = (jsonDecode(await rootBundle.loadString('assets/cars.json')) as List).map((e) => CarProfile(e)).toList();
  final feed = Feed()..listen();
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(useMaterial3: true), home: Home(feed, cars)));
}

class Home extends StatefulWidget {
  final Feed feed; final List<CarProfile> cars;
  const Home(this.feed, this.cars, {super.key});
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0; CarProfile? manual; String ip = '...'; bool mph = false;
  @override void initState() {
    super.initState();
    NetworkInterface.list(type: InternetAddressType.IPv4).then((l) {
      if (l.isNotEmpty && l.first.addresses.isNotEmpty) setState(() => ip = l.first.addresses.first.address);
    });
  }
  CarProfile profile(String code) => manual ?? widget.cars.firstWhere((c) => code.toLowerCase().startsWith(c.code), orElse: () => fallback);

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Row(children: [
        NavigationRail(
          backgroundColor: const Color(0xFF0B0B0F), selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.speed), label: Text('Dash')),
            NavigationRailDestination(icon: Icon(Icons.directions_car), label: Text('Car')),
            NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Setup')),
          ]),
        Expanded(child: ValueListenableBuilder<Telemetry>(valueListenable: widget.feed.data, builder: (_, t, __) {
          final p = profile(t.car);
          return [dash(t, p), carMode(t, p), setup()][tab];
        })),
      ])));
  }

  Widget dash(Telemetry t, CarProfile p) {
    final kmh = t.speedMs * 3.6; final v = mph ? kmh * 0.621371 : kmh;
    return Stack(alignment: Alignment.center, children: [
      CustomPaint(size: Size.infinite, painter: Arc(t.rpm / p.maxRpm, p.red / p.maxRpm, p.accent)),
      Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(onTap: () => setState(() => mph = !mph),
          child: Text(v.round().toString(), style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w800))),
        Text(mph ? 'MPH' : 'KM/H', style: const TextStyle(color: Colors.white54)),
        Text(t.gearLabel, style: TextStyle(fontSize: 64, color: p.accent, fontWeight: FontWeight.bold)),
        Text('${t.rpm.round()} rpm', style: const TextStyle(color: Colors.white70)),
      ]),
      Positioned(left: 16, bottom: 16, child: Text('${p.name}  •  ${p.real}', style: const TextStyle(color: Colors.white38))),
      Positioned(right: 16, bottom: 16, child: SizedBox(width: 220, child: Column(children: [
        bar('Fuel', t.fuel, Colors.amber), bar('Throttle', t.thr, Colors.green), bar('Brake', t.brk, Colors.red),
        Text('Coolant ${t.temp.round()}°C', style: const TextStyle(color: Colors.white54)),
      ]))),
    ]);
  }
  Widget bar(String l, double v, Color c) => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [SizedBox(width: 64, child: Text(l, style: const TextStyle(fontSize: 12))),
        Expanded(child: LinearProgressIndicator(value: v.clamp(0.0, 1.0).toDouble(), color: c, backgroundColor: Colors.white12))]));

  /// CarPlay-style launcher. (Not Apple CarPlay itself, that needs Apple's entitlement.)
  Widget carMode(Telemetry t, CarProfile p) {
    final tiles = <(IconData, String, String)>[
      (Icons.phone, 'Phone', 'tel:'), (Icons.music_note, 'Spotify', 'spotify:'),
      (Icons.map, 'Maps', 'https://maps.google.com'), (Icons.message, 'Messages', 'sms:'),
      (Icons.podcasts, 'Podcasts', 'https://podcasts.apple.com'), (Icons.cloud, 'Weather', 'https://weather.com'),
    ];
    return Row(children: [
      SizedBox(width: 240, child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(t.gearLabel, style: TextStyle(fontSize: 80, color: p.accent, fontWeight: FontWeight.bold)),
        Text('${(t.speedMs * 3.6).round()} km/h', style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 12), Text(p.name, style: const TextStyle(color: Colors.white54)),
      ]))),
      Expanded(child: GridView.count(crossAxisCount: 3, padding: const EdgeInsets.all(16), mainAxisSpacing: 16, crossAxisSpacing: 16,
        children: [for (final x in tiles) InkWell(borderRadius: BorderRadius.circular(24),
          onTap: () => launchUrl(Uri.parse(x.$3), mode: LaunchMode.externalApplication),
          child: Container(decoration: BoxDecoration(color: const Color(0xFF1B1B22), borderRadius: BorderRadius.circular(24)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(x.$1, size: 48, color: p.accent), const SizedBox(height: 8), Text(x.$2)])))])),
    ]);
  }

  Widget setup() => ListView(padding: const EdgeInsets.all(24), children: [
    Text('Status: ${widget.feed.status.value}'),
    const SizedBox(height: 8),
    Text('In BeamNG: Options > Other > OutGauge support ON, IP = $ip, Port = 4444.'),
    const SizedBox(height: 16),
    Wrap(spacing: 12, children: [
      FilledButton(onPressed: () { widget.feed.listen(); setState(() {}); }, child: const Text('Listen (live)')),
      OutlinedButton(onPressed: () { widget.feed.demo(); setState(() {}); }, child: const Text('Demo mode')),
    ]),
    const SizedBox(height: 24), const Text('Car profile'),
    DropdownButton<CarProfile?>(value: manual, isExpanded: true, hint: const Text('Auto-detect'),
      items: [const DropdownMenuItem(value: null, child: Text('Auto-detect')),
        for (final c in widget.cars) DropdownMenuItem(value: c, child: Text('${c.name}  →  ${c.real}'))],
      onChanged: (v) => setState(() => manual = v)),
  ]);
}

class Arc extends CustomPainter {
  final double v, red; final Color c; Arc(this.v, this.red, this.c);
  @override void paint(Canvas cv, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: min(s.width, s.height) * 0.42);
    const start = pi * 0.75, sweep = pi * 1.5;
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 22..strokeCap = StrokeCap.round;
    cv.drawArc(r, start, sweep, false, base..color = Colors.white12);
    cv.drawArc(r, start + sweep * red, sweep * (1 - red), false, base..color = const Color(0x59F44336));
    cv.drawArc(r, start, sweep * v.clamp(0.0, 1.0).toDouble(), false, base..color = v > red ? Colors.red : c);
  }
  @override bool shouldRepaint(Arc o) => true;
}
