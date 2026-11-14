"""Create a portable source archive without host SDK paths or build caches."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
output = root.parent / 'fintrust_windows_android_source.zip'
excluded = {'.git', '.dart_tool', '.gradle', '.idea', 'build', 'ephemeral', '.plugin_symlinks', 'node_modules', '__pycache__', '.cxx'}
files = set()
for directory in ['lib', 'android', 'windows', 'linux', 'web', '.vscode', 'test', 'scripts', 'tool']:
    for path in (root / directory).rglob('*'):
        relative = path.relative_to(root)
        if not path.is_file() or any(p in excluded for p in relative.parts):
            continue
        if path.name in {'local.properties', 'key.properties'} or path.suffix in {'.jks', '.keystore', '.iml', '.pyc'}:
            continue
        files.add(path)
for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'README.md', '.metadata', '.gitignore', 'assets/design.json']:
    files.add(root / name)
scenes = json.loads((root / 'assets/design.json').read_text())
for scene in scenes.values():
    for layer in scene['layers']:
        files.add(root / layer['asset'])
with ZipFile(output, 'w', compression=ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, 'ilham_app/' + path.relative_to(root).as_posix())
with ZipFile(output) as archive:
    assert archive.testzip() is None
    assert 'ilham_app/windows/runner/main.cpp' in archive.namelist()
    assert 'ilham_app/android/gradlew.bat' in archive.namelist()
    assert 'ilham_app/android/local.properties' not in archive.namelist()
print(f'{output}: {len(files)} files, {output.stat().st_size / 1024 / 1024:.1f} MiB')
