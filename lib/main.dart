import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double pageW = 1200;
const double pageH = 1600;
const Rect pageRect = Rect.fromLTWH(0, 0, pageW, pageH);

const Color kBg = Color(0xFF2B2D31);
const Color kPanel = Color(0xFF1E1F22);
const Color kAccent = Color(0xFF7C9CFF);
const Color kAccentSoft = Color(0x337C9CFF);

enum Tool { pen, blend, eraser }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SketchyApp());
}

class SketchyApp extends StatelessWidget {
  const SketchyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sketchy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kAccent),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
      ),
      home: const EditorPage(),
    );
  }
}

class Stroke {
  final Tool tool;
  final Color color;
  final double size;
  final double hardness;
  final List<Offset> pts = [];

  Stroke(this.tool, this.color, this.size, this.hardness);

  Path smoothPath() {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }

  Path areaPath() {
    final path = Path();
    final r = size / 2;
    Offset? prev;
    for (final p in pts) {
      if (prev == null) {
        path.addOval(Rect.fromCircle(center: p, radius: r));
      } else {
        final d = (p - prev).distance;
        final n = (d / (r * 0.5)).ceil().clamp(1, 400);
        for (int k = 1; k <= n; k++) {
          final q = Offset.lerp(prev, p, k / n)!;
          path.addOval(Rect.fromCircle(center: q, radius: r));
        }
      }
      prev = p;
    }
    return path;
  }
}

class Layer {
  String name;
  ui.Image? image;
  bool visible = true;
  double opacity = 1;
  final List<ui.Image?> undo = [];
  final List<ui.Image?> redo = [];

  Layer(this.name);
}

void drawLayerWithStroke(Canvas c, ui.Image? base, Stroke? s) {
  c.saveLayer(pageRect, Paint());
  if (base != null) c.drawImage(base, Offset.zero, Paint());

  if (s != null && s.pts.isNotEmpty) {
    if (s.tool == Tool.blend) {
      if (base != null) {
        final sigma = 6 + (1 - s.hardness) * 14;
        c.save();
        c.clipPath(s.areaPath());
        c.saveLayer(
          pageRect,
          Paint()
            ..blendMode = BlendMode.src
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        );
        c.drawImage(base, Offset.zero, Paint());
        c.restore();
        c.restore();
      }
    } else {
      final p = Paint()
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size;
      if (s.tool == Tool.eraser) {
        p.blendMode = BlendMode.clear;
        p.color = Colors.black;
      } else {
        p.color = s.color;
      }
      if (s.hardness < 1) {
        p.maskFilter =
            MaskFilter.blur(BlurStyle.normal, s.size * (1 - s.hardness) * 0.5);
      }
      if (s.pts.length == 1) {
        p.style = PaintingStyle.fill;
        c.drawCircle(s.pts.first, s.size / 2, p);
      } else {
        p.style = PaintingStyle.stroke;
        c.drawPath(s.smoothPath(), p);
      }
    }
  }
  c.restore();
}

void drawPaper(Canvas c) {
  c.drawRect(pageRect, Paint()..color = const Color(0xFFF7F0DC));

  final line = Paint()
    ..color = const Color(0xFFAFC4D9)
    ..strokeWidth = 3.5;
  for (double y = 230; y < pageH - 40; y += 64) {
    c.drawLine(Offset(0, y), Offset(pageW, y), line);
  }

  c.drawLine(
    const Offset(190, 0),
    const Offset(190, pageH),
    Paint()
      ..color = const Color(0xFFE08E8E)
      ..strokeWidth = 4,
  );

  final rim = Paint()..color = const Color(0x33000000);
  final hole = Paint()..color = kBg;
  for (final y in [300.0, 800.0, 1300.0]) {
    c.drawCircle(Offset(80, y), 26, rim);
    c.drawCircle(Offset(80, y), 21, hole);
  }

  c.drawRect(
    pageRect,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(pageW / 2, pageH / 2),
        1100,
        const [Color(0x00000000), Color(0x40A0782A)],
        const [0.55, 1.0],
      ),
  );
}

class PagePainter extends CustomPainter {
  final _EditorPageState s;
  PagePainter(this.s) : super(repaint: s.tick);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / pageW);
    canvas.clipRect(pageRect);
    drawPaper(canvas);
    for (final l in s.layers) {
      if (!l.visible) continue;
      final stroke = identical(l, s.curLayer) ? s.cur : null;
      final faded = l.opacity < 1;
      if (faded) {
        canvas.saveLayer(
            pageRect, Paint()..color = Color.fromRGBO(255, 255, 255, l.opacity));
      }
      drawLayerWithStroke(canvas, l.image, stroke);
      if (faded) canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PagePainter old) => true;
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  final List<Layer> layers = [Layer('Layer 1')];
  int active = 0;
  int _layerCounter = 1;

  Tool tool = Tool.pen;
  Color color = const Color(0xFF1B1B1F);
  double size = 12;
  double hardness = 1.0;

  Stroke? cur;
  Layer? curLayer;
  int? _pointer;

  static const List<Color> palette = [
    Color(0xFF1B1B1F),
    Color(0xFF3F51B5),
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF8E24AA),
    Color(0xFFEC407A),
    Color(0xFF795548),
    Color(0xFF9E9E9E),
    Color(0xFFFFFFFF),
  ];

  Offset _map(Offset p, double w) => p * (pageW / w);

  void _down(PointerDownEvent e, double w) {
    if (_pointer != null) return;
    final layer = layers[active];
    if (!layer.visible) return;
    _pointer = e.pointer;
    curLayer = layer;
    cur = Stroke(tool, color, size, hardness)..pts.add(_map(e.localPosition, w));
    tick.value++;
  }

  void _move(PointerMoveEvent e, double w) {
    if (e.pointer != _pointer || cur == null) return;
    final p = _map(e.localPosition, w);
    if ((p - cur!.pts.last).distance < 1.5) return;
    cur!.pts.add(p);
    tick.value++;
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _commit();
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    cur = null;
    curLayer = null;
    tick.value++;
  }

  void _commit() {
    final s = cur;
    final layer = curLayer;
    if (s == null || layer == null) return;

    final rec = ui.PictureRecorder();
    drawLayerWithStroke(Canvas(rec), layer.image, s);
    final pic = rec.endRecording();
    final img = pic.toImageSync(pageW.toInt(), pageH.toInt());
    pic.dispose();

    layer.undo.add(layer.image);
    if (layer.undo.length > 10) layer.undo.removeAt(0)?.dispose();
    for (final r in layer.redo) {
      r?.dispose();
    }
    layer.redo.clear();
    layer.image = img;

    cur = null;
    curLayer = null;
    tick.value++;
    setState(() {});
  }

  void _undo() {
    final l = layers[active];
    if (l.undo.isEmpty) return;
    l.redo.add(l.image);
    l.image = l.undo.removeLast();
    tick.value++;
    setState(() {});
  }

  void _redo() {
    final l = layers[active];
    if (l.redo.isEmpty) return;
    l.undo.add(l.image);
    l.image = l.redo.removeLast();
    tick.value++;
    setState(() {});
  }

  void _clearLayer() {
    final l = layers[active];
    if (l.image == null) return;
    l.undo.add(l.image);
    l.redo.clear();
    l.image = null;
    tick.value++;
    setState(() {});
  }

  void _addLayer() {
    setState(() {
      layers.insert(active + 1, Layer('Layer ${++_layerCounter}'));
      active += 1;
    });
    tick.value++;
  }

  void _deleteLayer() {
    if (layers.length <= 1) return;
    setState(() {
      layers.removeAt(active);
      if (active > 0) active -= 1;
    });
    tick.value++;
  }

  void _moveUp() {
    if (active >= layers.length - 1) return;
    setState(() {
      final l = layers.removeAt(active);
      layers.insert(active + 1, l);
      active += 1;
    });
    tick.value++;
  }

  void _moveDown() {
    if (active <= 0) return;
    setState(() {
      final l = layers.removeAt(active);
      layers.insert(active - 1, l);
      active -= 1;
    });
    tick.value++;
  }

  Future<void> _pickColor() async {
    var hsv = HSVColor.fromColor(color);
    final res = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: kBg,
          title: const Text('Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: hsv.hue,
                min: 0,
                max: 360,
                onChanged: (v) => set(() => hsv = hsv.withHue(v)),
              ),
              Slider(
                value: hsv.saturation,
                min: 0,
                max: 1,
                onChanged: (v) => set(() => hsv = hsv.withSaturation(v)),
              ),
              Slider(
                value: hsv.value,
                min: 0,
                max: 1,
                onChanged: (v) => set(() => hsv = hsv.withValue(v)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, hsv.toColor()),
                child: const Text('OK')),
          ],
        ),
      ),
    );
    if (res != null) {
      setState(() {
        color = res;
        if (tool == Tool.eraser) tool = Tool.pen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _layersDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _canvasArea()),
            _bottomPanel(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final l = layers[active];
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: kPanel,
      child: Row(
        children: [
          const Icon(Icons.brush_rounded, color: kAccent, size: 22),
          const SizedBox(width: 8),
          const Text('Sketchy',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const Spacer(),
          IconButton(
              tooltip: 'Undo',
              onPressed: l.undo.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_rounded)),
          IconButton(
              tooltip: 'Redo',
              onPressed: l.redo.isEmpty ? null : _redo,
              icon: const Icon(Icons.redo_rounded)),
          IconButton(
              tooltip: 'Clear layer',
              onPressed: l.image == null ? null : _clearLayer,
              icon: const Icon(Icons.layers_clear_outlined)),
          IconButton(
              tooltip: 'Layers',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              icon: const Icon(Icons.layers_rounded)),
        ],
      ),
    );
  }

  Widget _canvasArea() {
    return Container(
      color: kBg,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: pageW / pageH,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                    color: Colors.black54, blurRadius: 18, offset: Offset(0, 6)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LayoutBuilder(
                builder: (ctx, box) {
                  final w = box.maxWidth;
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _down(e, w),
                    onPointerMove: (e) => _move(e, w),
                    onPointerUp: _up,
                    onPointerCancel: _cancel,
                    child: CustomPaint(
                      painter: PagePainter(this),
                      size: Size.infinite,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _toolBtn(Tool.pen, Icons.edit_rounded, 'Pen'),
              _toolBtn(Tool.blend, Icons.blur_on_rounded, 'Blend'),
              _toolBtn(Tool.eraser, Icons.auto_fix_normal_rounded, 'Eraser'),
              const SizedBox(width: 6),
              _preview(),
            ],
          ),
          const SizedBox(height: 6),
          _sliderRow('Size', size, 2, 120, (v) => setState(() => size = v),
              '${size.round()}'),
          _sliderRow('Sharpness', hardness, 0, 1,
              (v) => setState(() => hardness = v), '${(hardness * 100).round()}%'),
          const SizedBox(height: 4),
          _colorRow(),
        ],
      ),
    );
  }

  Widget _toolBtn(Tool t, IconData icon, String label) {
    final sel = tool == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => tool = t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? kAccentSoft : kBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? kAccent : Colors.transparent),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: sel ? kAccent : Colors.white70),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5, color: sel ? kAccent : Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final d = (size * 0.6).clamp(3.0, 40.0).toDouble();
    final soft = (1 - hardness) * d * 0.8;
    final c = tool == Tool.eraser
        ? Colors.white60
        : (tool == Tool.blend ? kAccent : color);
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          boxShadow: soft > 0.5
              ? [BoxShadow(color: c, blurRadius: soft, spreadRadius: soft / 3)]
              : null,
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double v, double min, double max,
      ValueChanged<double> onChanged, String valueText) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
          Expanded(
              child: Slider(value: v, min: min, max: max, onChanged: onChanged)),
          SizedBox(
            width: 44,
            child: Text(valueText,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _colorRow() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in palette)
            GestureDetector(
              onTap: () => setState(() {
                color = c;
                if (tool == Tool.eraser) tool = Tool.pen;
              }),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 10, top: 3, bottom: 3),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == c ? Colors.white : Colors.white24,
                    width: color == c ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: _pickColor,
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(top: 3, bottom: 3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Colors.red,
                  Colors.yellow,
                  Colors.green,
                  Colors.cyan,
                  Colors.blue,
                  Colors.purple,
                  Colors.red,
                ]),
              ),
              child: const Icon(Icons.add, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layersDrawer() {
    return Drawer(
      backgroundColor: kPanel,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                children: [
                  const Text('Layers',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      tooltip: 'Add',
                      onPressed: _addLayer,
                      icon: const Icon(Icons.add_rounded)),
                  IconButton(
                      tooltip: 'Move up',
                      onPressed: _moveUp,
                      icon: const Icon(Icons.arrow_upward_rounded)),
                  IconButton(
                      tooltip: 'Move down',
                      onPressed: _moveDown,
                      icon: const Icon(Icons.arrow_downward_rounded)),
                  IconButton(
                      tooltip: 'Delete',
