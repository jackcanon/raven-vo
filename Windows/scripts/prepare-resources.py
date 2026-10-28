from pathlib import Path
import importlib.metadata as metadata
import os
import shutil
import subprocess

repo = Path(__file__).resolve().parents[2]
resources = repo / '.build/windows-resources'
engine = repo / '.build/windows-audio.cpp'
resources.mkdir(parents=True, exist_ok=True)
bin_dir = resources / 'engine'
bin_dir.mkdir(exist_ok=True)
for source in (engine / 'build/windows-cpu-release/bin').glob('*'):
    if source.suffix.lower() in {'.exe', '.dll'}:
        shutil.copy2(source, bin_dir / source.name)
shutil.copy2(repo / '.build/windows-raven-denoise.exe', bin_dir / 'raven-denoise.exe')
vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
vs = Path(subprocess.check_output([str(vswhere), '-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).strip())
redist = vs / 'VC/Redist/MSVC'
for name, component in [('MSVCP140.dll','CRT'), ('VCRUNTIME140.dll','CRT'), ('VCRUNTIME140_1.dll','CRT'), ('VCOMP140.DLL','OpenMP')]:
    matches = sorted(redist.glob(f'*/x64/Microsoft.VC*.{component}/{name}'), reverse=True)
    if not matches:
        raise RuntimeError(f'Missing Microsoft redistributable: {name}')
    shutil.copy2(matches[0], bin_dir / name)
shutil.copy2(repo / 'Assets/AppIcon.png', resources / 'AppIcon.png')
third = resources / 'ThirdParty'
for directory, source in [('Ming',repo/'Notices'), ('FrontEnd',None), ('RNNoise',repo/'.build/windows-rnnoise')]:
    target = third / directory; target.mkdir(parents=True,exist_ok=True)
    if directory == 'Ming':
        for file in source.iterdir():
            if file.is_file():shutil.copy2(file,target/file.name)
    elif directory == 'FrontEnd':shutil.copy2(repo/'LICENSE',target/'LICENSE')
    else:
        for name in ['COPYING','AUTHORS']:shutil.copy2(source/name,target/name)
for source in engine.rglob('*'):
    if source.is_file() and source.name.lower().startswith(('license','copying','notice')) and not {'.git','build'} & set(source.parts):
        target=third/'audio.cpp'/source.relative_to(engine);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
for name in ['PySide6','PySide6-Essentials','PySide6-Addons','shiboken6','numpy','scipy','soundfile','Send2Trash','cffi','pycparser','PyInstaller','Pillow']:
    distribution=metadata.distribution(name)
    for file in distribution.files or []:
        if any(token in str(file).lower() for token in ['license','copying','notice','authors']):
            source=Path(distribution.locate_file(file))
            if source.is_file():
                relative=Path(*[part for part in Path(str(file)).parts if part not in ('.','..','/','\\')])
                target=third/'Python'/name/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
shutil.copy2(repo/'THIRD_PARTY.md',third/'README.md')
shutil.copy2(repo/'Linux/LICENSING.md',third/'Qt-Python-LICENSING.md')
(third/'Microsoft-runtime.md').write_text('''# Microsoft runtime components

The unmodified MSVCP140, VCRUNTIME140, VCRUNTIME140_1 and VCOMP140 runtime DLLs accompanying the native engine are Microsoft Visual C++ redistributable components. Copyright Microsoft Corporation. They are not covered by Raven VO's MIT licence.

Redistribution reference: https://learn.microsoft.com/visualstudio/releases/2022/redistribution
Supported runtime information: https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist

The application does not include Visual Studio, an SDK, or developer tools for end users.
''',encoding='utf-8')
print('WINDOWS_RESOURCES_READY', resources)
