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

/// ---- Car profiles (assets/cars.json; each car has its own dashboard skin) ----
Color hx(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
class CarProfile {
  final String code, name, layout; final double maxRpm, red, maxKmh; final Color bg, face, ring, needle, text, accent;
  CarProfile(Map j)
      : code = j['code'], name = j['name'], layout = j['layout'],
        maxRpm = (j['maxRpm'] as num).toDouble(), red = (j['red'] as num).toDouble(), maxKmh = (j['maxKmh'] as num).toDouble(),
        bg = hx(j['bg']), face = hx(j['face']), ring = hx(j['ring']), needle = hx(j['needle']), text = hx(j['text']), accent = hx(j['accent']);
}
final CarProfile fallback = CarProfile({'code': '', 'name': 'Generic', 'layout': 'sport', 'maxRpm': 7000, 'red': 6200, 'maxKmh': 240,
  'bg': '#000000', 'face': '#000000', 'ring': '#4FC3F7', 'needle': '#4FC3F7', 'text': '#FFFFFF', 'accent': '#4FC3F7'});

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
  CarProfile profile(String code) => manual ?? widget.cars.firstWhere((c) { final k = code.toLowerCase(); return k.length >= 3 && (k.startsWith(c.code) || c.code.startsWith(k)); }, orElse: () => fallback);

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
    final sMax = mph ? (p.maxKmh * 0.621371 / 20).ceil() * 20.0 : p.maxKmh; final u = mph ? 'MPH' : 'KM/H';
    final step = sMax > 220 ? 40.0 : 20.0;
    Widget dial(double val, double mx, double st, double red, String unit, {bool labels = true, int flex = 2}) => Expanded(flex: flex,
      child: Padding(padding: const EdgeInsets.all(6), child: CustomPaint(painter: Dial(val / mx, red, mx, st, p, unit, labels))));
    Widget gearBox() => Text(t.gearLabel, style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: p.accent));
    Widget bars() => SizedBox(width: 260, child: Column(mainAxisSize: MainAxisSize.min, children: [
      bar('Fuel', t.fuel, Colors.amber), bar('Throttle', t.thr, Colors.green), bar('Brake', t.brk, Colors.red)]));
    Widget body;
    if (p.layout == 'classic') {
      body = Column(children: [
        Expanded(child: Row(children: [dial(v, sMax, step, 0.88, u), dial(t.rpm / 1000, p.maxRpm / 1000, 1, p.red / p.maxRpm, 'x1000 RPM')])),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [gearBox(), bars()])),
      ]);
    } else if (p.layout == 'cluster') {
      body = Column(children: [
        Expanded(child: Row(children: [
          dial(t.fuel * 4, 4, 1, 2.0, 'FUEL', labels: false, flex: 1),
          dial(v, sMax, step, 0.88, u), dial(t.rpm / 1000, p.maxRpm / 1000, 1, p.red / p.maxRpm, 'x1000 RPM'),
          dial((t.temp / 130) * 4, 4, 1, 0.8, 'TEMP', labels: false, flex: 1)])),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [gearBox(), bars()])),
      ]);
    } else if (p.layout == 'trio') {
      body = Column(children: [
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 22), child: Row(children: [
          dial(t.fuel * 4, 4, 1, 2.0, 'FUEL', labels: false, flex: 2),
          dial(v, sMax, step, 0.88, u, flex: 4),
          dial((t.temp / 130) * 4, 4, 1, 0.8, 'TEMP', labels: false, flex: 2)]))),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [gearBox(), Text('${t.rpm.round()} rpm', style: TextStyle(color: p.text.withAlpha(200))), bars()])),
      ]);
    } else if (p.layout == 'quad') {
      body = Column(children: [
        Expanded(child: Container(margin: const EdgeInsets.fromLTRB(16, 30, 16, 6),
          decoration: BoxDecoration(color: p.face, borderRadius: BorderRadius.circular(60), border: Border.all(color: p.ring, width: 5)),
          child: Row(children: [
            dial(v, sMax, step, 0.88, u, flex: 2), dial(t.rpm / 1000, p.maxRpm / 1000, 1, p.red / p.maxRpm, 'x1000 RPM', flex: 2),
            dial(t.fuel * 4, 4, 1, 2.0, 'FUEL', labels: false, flex: 1), dial((t.temp / 130) * 4, 4, 1, 0.8, 'TEMP', labels: false, flex: 1)]))),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [gearBox(), bars()])),
      ]);
    } else if (p.layout == 'lcd') {
      body = Center(child: Container(width: 520, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.ring, width: 4)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${v.round()}', style: TextStyle(fontSize: 88, fontFamily: 'monospace', color: p.accent)),
            Text(u, style: TextStyle(color: p.accent)), Text(t.gearLabel, style: TextStyle(fontSize: 64, fontFamily: 'monospace', color: p.accent))]),
          LinearProgressIndicator(value: (t.rpm / p.maxRpm).clamp(0.0, 1.0).toDouble(), minHeight: 14,
            color: t.rpm > p.red ? Colors.red : p.accent, backgroundColor: Colors.white12),
          const SizedBox(height: 4), Text('${t.rpm.round()} RPM', style: TextStyle(color: p.accent, fontFamily: 'monospace')),
          const SizedBox(height: 8), bars()])));
    } else if (p.layout == 'retro') {
      body = Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 26, 16, 4), child: SizedBox(height: 84, child: CustomPaint(size: Size.infinite, painter: HStrip(v / sMax, sMax, step, p)))),
        Text('${v.round()} $u', style: TextStyle(color: p.text.withAlpha(200), fontSize: 14)),
        Expanded(child: Row(children: [
          dial(t.rpm / 1000, p.maxRpm / 1000, 1, p.red / p.maxRpm, 'x1000 RPM'),
          dial(t.fuel * 4, 4, 1, 2.0, 'FUEL', labels: false, flex: 1),
          dial((t.temp / 130) * 4, 4, 1, 0.8, 'TEMP', labels: false, flex: 1),
          Expanded(flex: 1, child: Center(child: gearBox()))])),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: bars()),
      ]);
    } else if (p.layout == 'race') {
      final lit = (t.rpm / p.maxRpm * 16).round();
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 60), child: Row(children: [for (var i = 0; i < 16; i++)
          Expanded(child: Center(child: Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle,
            color: i < lit ? (i / 16 >= p.red / p.maxRpm ? Colors.red : i > 7 ? Colors.amber : Colors.green) : Colors.white12))))])),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [Text(v.round().toString(), style: TextStyle(fontSize: 64, color: p.text)), Text(u, style: TextStyle(color: p.accent))]),
          Text(t.gearLabel, style: TextStyle(fontSize: 160, height: 1, color: p.accent, fontWeight: FontWeight.w900)),
          Column(mainAxisSize: MainAxisSize.min, children: [Text('${t.rpm.round()}', style: TextStyle(fontSize: 48, color: p.text)), const Text('RPM', style: TextStyle(color: Colors.white54))])]),
        const SizedBox(height: 6), bars(),
      ]);
    } else if (p.layout == 'digital') {
      final lit = (t.rpm / p.maxRpm * 32).round();
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [for (var i = 0; i < 32; i++)
          Expanded(child: Container(height: 26, margin: const EdgeInsets.all(1.5),
            color: i < lit ? (i / 32 >= p.red / p.maxRpm ? Colors.red : p.accent) : Colors.white10))])),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(onTap: () => setState(() => mph = !mph), child: Text(v.round().toString(), style: TextStyle(fontSize: 110, fontWeight: FontWeight.w300, color: p.text))),
            Text(u, style: TextStyle(color: p.accent))]),
          Text(t.gearLabel, style: TextStyle(fontSize: 96, color: p.accent, fontWeight: FontWeight.bold)),
          Column(mainAxisSize: MainAxisSize.min, children: [Text('${t.rpm.round()}', style: TextStyle(fontSize: 40, color: p.text)), const Text('RPM', style: TextStyle(color: Colors.white54)), const SizedBox(height: 8), bars()])]),
      ]);
    } else {
      body = Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.infinite, painter: Arc(t.rpm / p.maxRpm, p.red / p.maxRpm, p.accent)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onTap: () => setState(() => mph = !mph), child: Text(v.round().toString(), style: TextStyle(fontSize: 96, fontWeight: FontWeight.w800, color: p.text))),
          Text(u, style: const TextStyle(color: Colors.white54)),
          Text(t.gearLabel, style: TextStyle(fontSize: 64, color: p.accent, fontWeight: FontWeight.bold)),
          Text('${t.rpm.round()} rpm', style: const TextStyle(color: Colors.white70))]),
        Positioned(right: 16, bottom: 16, child: bars()),
      ]);
    }
    return Container(color: p.bg, child: Stack(children: [body, Positioned(left: 12, top: 6, child: Text(p.name, style: const TextStyle(color: Colors.white30, fontSize: 12)))]));
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
        for (final c in widget.cars) DropdownMenuItem(value: c, child: Text(c.name))],
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

class Dial extends CustomPainter {
  final double v, red, maxVal, step; final CarProfile p; final String unit; final bool labels;
  Dial(this.v, this.red, this.maxVal, this.step, this.p, this.unit, this.labels);
  @override void paint(Canvas cv, Size s) {
    final c = s.center(Offset.zero); final r = min(s.width, s.height) / 2 - 4;
    cv.drawCircle(c, r, Paint()..color = p.face);
    cv.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = p.ring);
    const a0 = pi * 0.75, sw = pi * 1.5;
    final n = max(1, (maxVal / step).round());
    for (var i = 0; i <= n; i++) {
      final a = a0 + sw * i / n; final d = Offset(cos(a), sin(a));
      final col = (i * step / maxVal) >= red ? Colors.redAccent : p.text;
      cv.drawLine(c + d * (r * .86), c + d * (r * .96), Paint()..color = col..strokeWidth = 3);
      if (labels) {
        final tp = TextPainter(text: TextSpan(text: '${(i * step).round()}', style: TextStyle(color: col, fontSize: r * .11)), textDirection: TextDirection.ltr)..layout();
        tp.paint(cv, c + d * (r * .72) - Offset(tp.width / 2, tp.height / 2));
      }
    }
    final na = a0 + sw * v.clamp(0.0, 1.0).toDouble();
    cv.drawLine(c, c + Offset(cos(na), sin(na)) * (r * .8), Paint()..color = p.needle..strokeWidth = 4..strokeCap = StrokeCap.round);
    cv.drawCircle(c, r * .07, Paint()..color = p.needle);
    final u = TextPainter(text: TextSpan(text: unit, style: TextStyle(color: p.text.withAlpha(150), fontSize: r * .1)), textDirection: TextDirection.ltr)..layout();
    u.paint(cv, c + Offset(-u.width / 2, r * .4));
  }
  @override bool shouldRepaint(Dial o) => true;
}

class HStrip extends CustomPainter {
  final double v, maxVal, step; final CarProfile p;
  HStrip(this.v, this.maxVal, this.step, this.p);
  @override void paint(Canvas cv, Size s) {
    final rr = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(18));
    cv.drawRRect(rr, Paint()..color = p.face);
    cv.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = p.ring);
    final n = max(1, (maxVal / step).round()); final w = s.width - 60;
    for (var i = 0; i <= n; i++) {
      final x = 30 + w * i / n;
      cv.drawLine(Offset(x, s.height * .3), Offset(x, s.height * .5), Paint()..color = p.text..strokeWidth = 3);
      final tp = TextPainter(text: TextSpan(text: '${(i * step).round()}', style: TextStyle(color: p.text, fontSize: s.height * .22)), textDirection: TextDirection.ltr)..layout();
      tp.paint(cv, Offset(x - tp.width / 2, s.height * .54));
    }
    final nx = 30 + w * v.clamp(0.0, 1.0).toDouble();
    cv.drawLine(Offset(nx, s.height * .12), Offset(nx, s.height * .5), Paint()..color = p.needle..strokeWidth = 5..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(HStrip o) => true;
}
