import 'dart:convert';

import 'package:open_dex_api/open_dex_api.dart';

/// One Android task as `am stack list` reports it: which display it is on
/// and how big that display's bounds are.
class AndroidTask {
  const AndroidTask({
    required this.taskId,
    required this.displayId,
    required this.pixelSize,
  });

  final int taskId;
  final int displayId;
  final WindowPixelSize pixelSize;
}

/// The first task in [stackList] that holds an activity of [packageName], on
/// whichever display it sits. Null when the package has no task.
AndroidTask? taskForPackage(String stackList, String packageName) {
  AndroidTask? current;
  for (final line in const LineSplitter().convert(stackList)) {
    final root = _rootTaskLine.firstMatch(line);
    if (root != null) {
      current = AndroidTask(
        taskId: int.parse(root.group(1)!),
        pixelSize: WindowPixelSize(
          width: int.parse(root.group(2)!),
          height: int.parse(root.group(3)!),
        ),
        displayId: int.parse(root.group(4)!),
      );
    }
    if (current != null && line.contains('$packageName/')) return current;
  }
  return null;
}

final _rootTaskLine = RegExp(
  r'RootTask id=(\d+) bounds=\[[^\]]+\]\[(\d+),(\d+)\] displayId=(\d+)',
);
