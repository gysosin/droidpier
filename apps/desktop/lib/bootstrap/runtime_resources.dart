import 'dart:io';

File? findRuntimeFile(
  String relativePath, {
  String? resolvedExecutable,
  Directory? workingDirectory,
}) {
  for (final root in _runtimeRoots(
    resolvedExecutable: resolvedExecutable,
    workingDirectory: workingDirectory,
  )) {
    final candidate = File('${root.path}/$relativePath');
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

Directory? findRuntimeDirectory(
  String relativePath, {
  required List<String> requiredFiles,
  String? resolvedExecutable,
  Directory? workingDirectory,
}) {
  for (final root in _runtimeRoots(
    resolvedExecutable: resolvedExecutable,
    workingDirectory: workingDirectory,
  )) {
    final candidate = Directory('${root.path}/$relativePath');
    if (requiredFiles.every(
      (name) => File('${candidate.path}/$name').existsSync(),
    )) {
      return candidate;
    }
  }
  return null;
}

File? findExecutableOnPath(
  String executableName, {
  String? pathEnvironment,
  bool? windows,
}) {
  if (executableName.isEmpty ||
      executableName.contains('/') ||
      executableName.contains(r'\')) {
    return null;
  }
  final separator = (windows ?? Platform.isWindows) ? ';' : ':';
  final path = pathEnvironment ?? Platform.environment['PATH'] ?? '';
  for (final entry in path.split(separator)) {
    if (entry.trim().isEmpty) continue;
    final candidate = File('${Directory(entry).absolute.path}/$executableName');
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

Iterable<Directory> _runtimeRoots({
  String? resolvedExecutable,
  Directory? workingDirectory,
}) sync* {
  final seen = <String>{};
  final executable = File(resolvedExecutable ?? Platform.resolvedExecutable);
  for (final root in [
    executable.parent,
    workingDirectory ?? Directory.current,
  ]) {
    final absolute = root.absolute.path;
    if (seen.add(absolute)) yield Directory(absolute);
  }

  if (resolvedExecutable == null && Platform.isLinux) {
    try {
      final procExecutable = File('/proc/self/exe').resolveSymbolicLinksSync();
      final root = File(procExecutable).parent.absolute.path;
      if (seen.add(root)) yield Directory(root);
    } on FileSystemException {
      // The executable and working-directory roots remain valid fallbacks.
    }
  }
}
