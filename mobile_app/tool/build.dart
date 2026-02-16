import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  Directory projectDir = Directory.current;
  File pubspec = File('${projectDir.path}${Platform.pathSeparator}pubspec.yaml');

  if (!await pubspec.exists()) {
    final nested = Directory(
      '${projectDir.path}${Platform.pathSeparator}mobile_app',
    );
    final nestedPubspec = File(
      '${nested.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (await nestedPubspec.exists()) {
      projectDir = nested;
      pubspec = nestedPubspec;
    } else {
      stderr.writeln(
        'pubspec.yaml not found. Run from mobile_app or project root.',
      );
      exit(1);
    }
  }

  final text = await pubspec.readAsString();
  final lines = LineSplitter.split(text).toList();
  final verIdx = lines.indexWhere((l) => l.trim().startsWith('version:'));
  if (verIdx == -1) {
    stderr.writeln('No version: entry in pubspec.yaml');
    exit(1);
  }

  final verLine = lines[verIdx].trim();
  final verMatch = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?$')
      .firstMatch(verLine);

  if (verMatch == null) {
    stderr.writeln('Unsupported version format in pubspec.yaml: $verLine');
    exit(1);
  }

  final base = verMatch.group(1)!;
  final build = verMatch.group(2);
  final nextBuild = (int.tryParse(build ?? '0') ?? 0) + 1;
  final newVersionLine = 'version: $base+$nextBuild';

  // Replace keeping original indentation
  final indent =
      RegExp(r'^(\s*)version:').firstMatch(lines[verIdx])?.group(1) ?? '';
  lines[verIdx] = '$indent$newVersionLine';

  await pubspec.writeAsString(lines.join('\n'));
  stdout.writeln('Bumped version to $base+$nextBuild');

  final flutterArgs = args.isNotEmpty ? args : ['apk'];
  final proc = await Process.start(
    'flutter',
    [
      'build',
      ...flutterArgs,
      '--dart-define=APP_VERSION_TAG=v$base+$nextBuild',
    ],
    workingDirectory: projectDir.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await proc.exitCode;
  exit(code);
}
