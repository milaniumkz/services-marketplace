import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Original JOBA prototype icon paths, rendered with the original stroke settings.
const _paths = <String, String>{
  "home": "M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z",
  "search": "M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
  "chat":
      "M21 11a8 8 0 0 1-8 8H7l-5 3V7a5 5 0 0 1 5-5h9a5 5 0 0 1 5 5zM7 8h9M7 12h6",
  "bell": "M5 9a7 7 0 0 1 14 0v7l2 3H3l2-3zM9 22h6",
  "user":
      "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M3 21v-2a7 7 0 0 1 7-7h4a7 7 0 0 1 7 7v2",
  "back": "m14 5-7 7 7 7",
  "right": "m9 5 7 7-7 7",
  "down": "m6 9 6 6 6-6",
  "plus": "M12 4v16M4 12h16",
  "check": "m4 12 5 5L20 6",
  "close": "m5 5 14 14M19 5 5 19",
  "pin":
      "M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
  "filter": "M4 6h16M4 12h16M4 18h16M8 3v6M16 9v6M10 15v6",
  "star":
      "m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21 7 14.2l-5-4.9 6.9-1z",
  "shield": "M12 2 3 6v6c0 6 9 10 9 10s9-4 9-10V6zM8 12l3 3 5-6",
  "tool": "M14 5a6 6 0 0 0-7 7L2 17l5 5 5-5a6 6 0 0 0 7-7l-4 4-5-5z",
  "brush": "M8 14 18 2l4 4-12 10M7 14c-4 0-5 4-5 7 4 0 8-1 8-5z",
  "spark": "m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z",
  "truck":
      "M2 6h12v12H2zM14 10h4l4 4v4h-8M8 19a2 2 0 1 1-4 0 2 2 0 0 1 4 0M20 19a2 2 0 1 1-4 0 2 2 0 0 1 4 0",
  "book": "M3 3h6l3 3 3-3h6v17h-6l-3 2-3-2H3zM12 6v16",
  "grid": "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z",
  "brief": "M3 7h18v14H3zM8 7V3h8v4M3 12c5 3 13 3 18 0M10 13h4v4h-4z",
  "heart": "M20 4c-3-3-8 0-8 2 0-2-5-5-8-2-5 5 1 11 8 17 7-6 13-12 8-17z",
  "share": "M12 16V2m-5 5 5-5 5 5M5 12H3v10h18V12h-2",
  "clock": "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0M12 6v6l4 2",
  "attach": "m8 12 7-7a4 4 0 0 1 6 6L10 22a6 6 0 0 1-8-8L13 3M6 14l9-9",
  "send": "m2 2 20 10L2 22l3-10zM5 12h17",
  "dots": "M5 12h.1M12 12h.1M19 12h.1",
  "eye":
      "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
  "lock": "M5 10h14v12H5zM8 10V6a4 4 0 0 1 8 0v4M12 15v3",
  "info": "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0M12 11v6M12 7v.1",
  "phone":
      "M7 2H4a2 2 0 0 0-2 2c0 10 8 18 18 18a2 2 0 0 0 2-2v-3l-6-2-2 3c-4-1-7-4-8-8l3-2z",
  "camera": "M3 6h4l2-3h6l2 3h4v15H3zM16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
  "image": "M2 3h20v18H2zM2 16l6-6 5 5 3-3 6 6M16 7h.1",
  "file": "M5 2h9l5 5v15H5zM14 2v6h5M8 13h8M8 17h6",
  "logout": "M10 3H3v18h7M9 12h13m-5-5 5 5-5 5",
  "globe":
      "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0M2 12h20M12 2c-5 6-5 14 0 20 5-6 5-14 0-20",
  "help":
      "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0M8 8a4 4 0 1 1 5 4v3M13 18v.1",
  "gift":
      "M2 8h20v5H2zM4 13v9h16v-9M12 8v14M12 8C2 8 4 0 8 3l4 5c10 0 8-8 4-5z",
  "crown": "m2 6 6 5 4-9 4 9 6-5-3 14H5z",
  "thumb": "M9 10l4-8c4 0 1 8 1 8h6l2 2-3 10H9zM2 10h4v12H2z",
  "flag": "M4 22V2m0 1c6-5 10 5 17 0v11c-7 5-11-5-17 0",
  "trash": "M3 6h18M5 6l1 16h12l1-16M9 6V2h6v4M10 10v8M14 10v8",
  "wifi":
      "M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0M12 20h.1",
  "retry": "M20 7V2l-4 4a9 9 0 1 0 5 10M20 7h-6",
  "card": "M2 4h20v16H2zM2 9h20M5 16h5",
  "play": "m8 4 12 8-12 8z",
  "edit": "m3 16 13-13 5 5L8 21H3zM13 6l5 5",
  "download": "M12 2v14m-6-6 6 6 6-6M3 17v5h18v-5",
  "face":
      "M2 8V2h6M16 2h6v6M22 16v6h-6M8 22H2v-6M8 8v3M16 8v3M12 10v4h-2M8 17c2 2 6 2 8 0",
};

class JobaIcon extends StatelessWidget {
  final String name;
  final double size, strokeWidth;
  final Color color;
  final Color? fill;
  const JobaIcon(this.name,
      {this.size = 22,
      this.strokeWidth = 1.8,
      this.color = const Color(0xFF172B4D),
      this.fill,
      super.key});
  @override
  Widget build(BuildContext context) => SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${fill == null ? 'none' : '#' + fill!.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}" stroke="#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}" stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round"><path d="${_paths[name] ?? _paths['info']}"/></svg>',
      width: size,
      height: size,
      excludeFromSemantics: true);
}
