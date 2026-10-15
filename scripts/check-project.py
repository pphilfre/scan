"""Fast preflight checks; no Apple SDK required. PyYAML is a dev tool only."""
import json
import plistlib
from pathlib import Path
import subprocess
import yaml

root = Path(__file__).resolve().parent.parent
project = yaml.safe_load((root / 'project.yml').read_text())
workflow = yaml.load((root / '.github/workflows/ios.yml').read_text(), Loader=yaml.BaseLoader)
assert project['options']['deploymentTarget']['iOS'] == '26.0'
assert 'packages' not in project, 'App should have no package dependencies'
assert project['targets']['FolioTests']['dependencies'] == [{'target': 'Folio'}]
assert project['targets']['Folio']['dependencies'] == [{'target': 'FolioWidgets', 'embed': True}]
assert project['targets']['FolioWidgets']['type'] == 'app-extension'
assert project['targets']['FolioWidgets']['info']['properties']['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
assert project['targets']['Folio']['info']['properties']['CFBundleURLTypes'][0]['CFBundleURLSchemes'] == ['folio']
assert 'INFOPLIST_KEY_NSFaceIDUsageDescription' in project['targets']['Folio']['settings']['base']
assert set(workflow['jobs']) == {'device', 'tests'}
assert set(workflow['on']['push']['branches']) == {'main', 'work'}
for job in workflow['jobs'].values():
    assert job['runs-on'] == 'macos-26'
    assert int(job['timeout-minutes']) <= 15
for path in (root / 'scripts').glob('*.sh'):
    subprocess.run(['bash', '-n', str(path)], check=True)
for path in (root / 'Scan').rglob('*.json'):
    json.loads(path.read_text())
with (root / 'Configuration/Folio.entitlements').open('rb') as f:
    entitlements = plistlib.load(f)
container = entitlements['com.apple.developer.icloud-container-identifiers'][0]
for path in ['Scan/App/FolioApp.swift', 'Scan/Views/SettingsView.swift']:
    assert container in (root / path).read_text(), f'Cloud container mismatch in {path}'
assert (root / 'Scan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png').is_file()
subprocess.run(['git', 'diff', '--check', 'HEAD'], cwd=root, check=True)
print('Project, workflow, entitlements, asset JSON and shell checks passed.')
