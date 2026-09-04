import 'package:flutter/widgets.dart';

/// The product's icon vocabulary, named by what a glyph *means* here.
///
/// One place, for two reasons.
///
/// The first is consistency. `Icons` carries several drawings of the same
/// thing — filled, `_outlined`, `_rounded` — and the desk had been picking
/// between them per call site, so a filled battery sat beside an outlined
/// settings gear in the same tray. Naming the role instead of the picture
/// makes that impossible.
///
/// The second is weight. Material's default glyphs are filled shapes; Lucide
/// draws a consistent 2px stroke. Against hairline panel edges, mono readouts
/// and 1px rules, an outline set reads as instrumentation and a filled set
/// reads as a phone launcher, which is the thing this product is explicitly
/// not.
abstract final class DexIcons {
  /// The bundled Lucide face. Declared as a plain [IconData] against a font
  /// family rather than through the `lucide_icons` package: that package
  /// subclasses [IconData], which Flutter has since made `final`, so it no
  /// longer compiles. The font itself is the whole of what it offered.
  static const String _family = 'Lucide';

  // Transport and link.
  static const IconData wifi = IconData(0xf596, fontFamily: _family);
  static const IconData wifiTethering = IconData(0xf472, fontFamily: _family);
  static const IconData bluetooth = IconData(0xf1a8, fontFamily: _family);
  static const IconData usb = IconData(0xf563, fontFamily: _family);
  static const IconData cellular = IconData(0xf4d0, fontFamily: _family);
  static const IconData airplane = IconData(0xf454, fontFamily: _family);
  static const IconData location = IconData(0xf3c0, fontFamily: _family);
  static const IconData torch = IconData(0xf2ea, fontFamily: _family);
  static const IconData charging = IconData(0xf5a3, fontFamily: _family);

  // Battery.
  static const IconData battery = IconData(0xf18e, fontFamily: _family);
  static const IconData batteryFull = IconData(0xf190, fontFamily: _family);
  static const IconData batteryCharging = IconData(0xf18f, fontFamily: _family);

  // Media transport.
  static const IconData play = IconData(0xf457, fontFamily: _family);
  static const IconData pause = IconData(0xf438, fontFamily: _family);
  static const IconData previous = IconData(0xf4d6, fontFamily: _family);
  static const IconData next = IconData(0xf4d7, fontFamily: _family);
  static const IconData music = IconData(0xf403, fontFamily: _family);

  // Window chrome and navigation.
  static const IconData close = IconData(0xf59e, fontFamily: _family);
  static const IconData minimise = IconData(0xf3dc, fontFamily: _family);
  static const IconData maximise = IconData(0xf3c3, fontFamily: _family);
  static const IconData fullscreen = IconData(0xf3c4, fontFamily: _family);
  static const IconData fullscreenExit = IconData(0xf3da, fontFamily: _family);
  static const IconData back = IconData(0xf1f9, fontFamily: _family);
  static const IconData forward = IconData(0xf1fb, fontFamily: _family);
  static const IconData recents = IconData(0xf4f2, fontFamily: _family);
  static const IconData home = IconData(0xf20b, fontFamily: _family);
  static const IconData menu = IconData(0xf3ca, fontFamily: _family);
  static const IconData appsGrid = IconData(0xf38a, fontFamily: _family);
  static const IconData portrait = IconData(0xf4dd, fontFamily: _family);
  static const IconData landscape = IconData(0xf492, fontFamily: _family);
  static const IconData rotationLock = IconData(0xf3ae, fontFamily: _family);

  // Desk furniture and surfaces.
  static const IconData search = IconData(0xf4ad, fontFamily: _family);
  static const IconData microphone = IconData(0xf3d2, fontFamily: _family);
  static const IconData notifications = IconData(0xf19c, fontFamily: _family);
  static const IconData settings = IconData(0xf4b9, fontFamily: _family);
  static const IconData keyboard = IconData(0xf379, fontFamily: _family);
  static const IconData pin = IconData(0xf450, fontFamily: _family);
  static const IconData pinOff = IconData(0xf451, fontFamily: _family);
  static const IconData copy = IconData(0xf252, fontFamily: _family);
  static const IconData check = IconData(0xf1ee, fontFamily: _family);
  static const IconData unchecked = IconData(0xf20b, fontFamily: _family);
  static const IconData lightMode = IconData(0xf50f, fontFamily: _family);
  static const IconData darkMode = IconData(0xf3eb, fontFamily: _family);

  // Pairing.
  static const IconData qrCode = IconData(0xf46e, fontFamily: _family);
  static const IconData qrScan = IconData(0xf4a4, fontFamily: _family);

  // States. Fault and caution are the two the design reserves a colour for, so
  // they get distinct shapes as well: colour alone is not a signal.
  static const IconData info = IconData(0xf36e, fontFamily: _family);
  static const IconData fault = IconData(0xf10b, fontFamily: _family);
  static const IconData privacy = IconData(0xf4c0, fontFamily: _family);
  static const IconData locked = IconData(0xf3ae, fontFamily: _family);

  // Added for the parity pass: the glyphs the reference's remaining
  // surfaces use, with codepoints from the bundled face's table.
  static const IconData activity = IconData(0xF101, fontFamily: 'Lucide');
  static const IconData shield = IconData(0xF4BF, fontFamily: 'Lucide');
  static const IconData clock = IconData(0xF221, fontFamily: 'Lucide');
  static const IconData layers = IconData(0xF387, fontFamily: 'Lucide');
  static const IconData terminal = IconData(0xF52A, fontFamily: 'Lucide');
  static const IconData cpu = IconData(0xF262, fontFamily: 'Lucide');
  static const IconData zap = IconData(0xF5A3, fontFamily: 'Lucide');
  static const IconData lock = IconData(0xF3AE, fontFamily: 'Lucide');
  static const IconData monitor = IconData(0xF3DF, fontFamily: 'Lucide');
  static const IconData palette = IconData(0xF41F, fontFamily: 'Lucide');
  static const IconData image = IconData(0xF365, fontFamily: 'Lucide');
  static const IconData sun = IconData(0xF50F, fontFamily: 'Lucide');
  static const IconData moon = IconData(0xF3EB, fontFamily: 'Lucide');
  static const IconData gauge = IconData(0xF328, fontFamily: 'Lucide');
  static const IconData radio = IconData(0xF472, fontFamily: 'Lucide');
  static const IconData folder = IconData(0xF2F8, fontFamily: 'Lucide');
  static const IconData eye = IconData(0xF29C, fontFamily: 'Lucide');
  static const IconData plus = IconData(0xF45E, fontFamily: 'Lucide');
  static const IconData minus = IconData(0xF3DC, fontFamily: 'Lucide');
  static const IconData sparkles = IconData(0xF4E8, fontFamily: 'Lucide');
  static const IconData command = IconData(0xF248, fontFamily: 'Lucide');
  static const IconData hash = IconData(0xF34A, fontFamily: 'Lucide');
  static const IconData users = IconData(0xF574, fontFamily: 'Lucide');
  static const IconData camera = IconData(0xF1DF, fontFamily: 'Lucide');
  static const IconData globe = IconData(0xF33A, fontFamily: 'Lucide');
  static const IconData star = IconData(0xF500, fontFamily: 'Lucide');
  static const IconData link = IconData(0xF397, fontFamily: 'Lucide');
  static const IconData power = IconData(0xF468, fontFamily: 'Lucide');
  static const IconData database = IconData(0xF26C, fontFamily: 'Lucide');
  static const IconData server = IconData(0xF4B5, fontFamily: 'Lucide');
  static const IconData box = IconData(0xF1C1, fontFamily: 'Lucide');
  static const IconData plug = IconData(0xF45A, fontFamily: 'Lucide');
  static const IconData smartphone = IconData(0xF4DD, fontFamily: 'Lucide');
  static const IconData laptop = IconData(0xF382, fontFamily: 'Lucide');
  static const IconData lightbulb = IconData(0xF394, fontFamily: 'Lucide');
  static const IconData contrast = IconData(0xF250, fontFamily: 'Lucide');
  static const IconData type = IconData(0xF554, fontFamily: 'Lucide');
  static const IconData ruler = IconData(0xF496, fontFamily: 'Lucide');
  static const IconData scan = IconData(0xF4A2, fontFamily: 'Lucide');
  static const IconData target = IconData(0xF528, fontFamily: 'Lucide');
  static const IconData timer = IconData(0xF53A, fontFamily: 'Lucide');
  static const IconData history = IconData(0xF35D, fontFamily: 'Lucide');
  static const IconData mic = IconData(0xF3D2, fontFamily: 'Lucide');
  static const IconData square = IconData(0xF4F2, fontFamily: 'Lucide');
  static const IconData list = IconData(0xF39B, fontFamily: 'Lucide');
  static const IconData signal = IconData(0xF4D0, fontFamily: 'Lucide');
  static const IconData airplay = IconData(0xF104, fontFamily: 'Lucide');
  static const IconData cast = IconData(0xF1EB, fontFamily: 'Lucide');
  static const IconData download = IconData(0xF287, fontFamily: 'Lucide');
  static const IconData upload = IconData(0xF561, fontFamily: 'Lucide');
  static const IconData calendar = IconData(0xF1D2, fontFamily: 'Lucide');
  static const IconData mail = IconData(0xF3B4, fontFamily: 'Lucide');
  static const IconData phone = IconData(0xF440, fontFamily: 'Lucide');
  static const IconData map = IconData(0xF3BF, fontFamily: 'Lucide');
  static const IconData navigation = IconData(0xF407, fontFamily: 'Lucide');
  static const IconData compass = IconData(0xF249, fontFamily: 'Lucide');
  static const IconData bookmark = IconData(0xF1BD, fontFamily: 'Lucide');
  static const IconData heart = IconData(0xF354, fontFamily: 'Lucide');
  static const IconData flag = IconData(0xF2E5, fontFamily: 'Lucide');
  static const IconData tag = IconData(0xF521, fontFamily: 'Lucide');
  static const IconData filter = IconData(0xF2E0, fontFamily: 'Lucide');
  static const IconData rotate = IconData(0xF492, fontFamily: 'Lucide'); // rotateCw
  static const IconData trash = IconData(0xF546, fontFamily: 'Lucide'); // trash2
  static const IconData volume = IconData(0xF585, fontFamily: 'Lucide'); // volume2
  static const IconData chevronRight = IconData(0xF1FB, fontFamily: 'Lucide'); // chevronRight
  static const IconData chevronDown = IconData(0xF1F5, fontFamily: 'Lucide'); // chevronDown
  static const IconData externalLink = IconData(0xF29B, fontFamily: 'Lucide'); // externalLink
  static const IconData shieldCheck = IconData(0xF4C1, fontFamily: 'Lucide'); // shieldCheck
  static const IconData circleCheck = IconData(0xF1F1, fontFamily: 'Lucide'); // checkCircle2
  static const IconData triangleAlert = IconData(0xF10D, fontFamily: 'Lucide'); // alertTriangle
  static const IconData circleAlert = IconData(0xF10B, fontFamily: 'Lucide'); // alertCircle
  static const IconData circleHelp = IconData(0xF359, fontFamily: 'Lucide'); // helpCircle
  static const IconData house = IconData(0xF35E, fontFamily: 'Lucide'); // home
  static const IconData ellipsis = IconData(0xF3ED, fontFamily: 'Lucide'); // moreHorizontal
  static const IconData circleX = IconData(0xF59F, fontFamily: 'Lucide'); // xCircle
  static const IconData badgeCheck = IconData(0xF179, fontFamily: 'Lucide'); // badgeCheck
  static const IconData layoutDashboard = IconData(0xF389, fontFamily: 'Lucide'); // layoutDashboard
  static const IconData panelLeft = IconData(0xF425, fontFamily: 'Lucide'); // panelLeft
  static const IconData bellRing = IconData(0xF1A1, fontFamily: 'Lucide'); // bellRing
  static const IconData circleDot = IconData(0xF20E, fontFamily: 'Lucide'); // circleDot
  static const IconData layoutGrid = IconData(0xF38A, fontFamily: 'Lucide'); // layoutGrid
  static const IconData share = IconData(0xF4BD, fontFamily: 'Lucide'); // share2
  static const IconData fileText = IconData(0xF2D3, fontFamily: 'Lucide'); // fileText
  static const IconData wifiOff = IconData(0xF597, fontFamily: 'Lucide'); // wifiOff
  static const IconData refresh = IconData(0xF480, fontFamily: 'Lucide'); // refreshCw
  static const IconData arrowUpDown = IconData(0xF160, fontFamily: 'Lucide'); // arrowUpDown
  static const IconData hardDrive = IconData(0xF348, fontFamily: 'Lucide'); // hardDrive
  static const IconData eyeOff = IconData(0xF29D, fontFamily: 'Lucide'); // eyeOff
  static const IconData mapPin = IconData(0xF3C0, fontFamily: 'Lucide'); // mapPin
  static const IconData messageSquare = IconData(0xF3CE, fontFamily: 'Lucide'); // messageSquare
  static const IconData slidersHorizontal = IconData(0xF4DC, fontFamily: 'Lucide'); // slidersHorizontal
  static const IconData rotateCcw = IconData(0xF491, fontFamily: 'Lucide');
}
