"""Fetch the pinned upstream E203 and an optional local RISC-V C compiler."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def setup(compiler=False, direct=False, verilator=False):
    lock = json.loads((ROOT / 'dependencies.json').read_text())
    dep = lock['e203']
    dest = ROOT / dep['path']
    git = ['git'] + (['-c', 'http.proxy=', '-c', 'https.proxy='] if direct else [])
    if not (dest / '.git').is_dir():
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(git + ['clone', '--depth', '1', dep['url'], str(dest)], check=True)
    head = subprocess.check_output(['git', '-C', str(dest), 'rev-parse', 'HEAD'], text=True).strip()
    if head != dep['commit']:
        subprocess.run(git + ['-C', str(dest), 'fetch', '--depth', '1', 'origin', dep['commit']], check=True)
        subprocess.run(['git', '-C', str(dest), 'checkout', '--detach', dep['commit']], check=True)
    if subprocess.check_output(['git', '-C', str(dest), 'status', '--porcelain'], text=True).strip():
        raise RuntimeError('Upstream E203 checkout is modified; use a clean dependency checkout.')
    if compiler:
        item = lock['zig_windows_x64']
        target = ROOT / '.tools'
        exe = target / 'ziglang' / 'zig.exe'
        if not exe.is_file():
            target.mkdir(exist_ok=True)
            wheel = target / 'ziglang.whl'
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}) if direct else urllib.request.ProxyHandler())
            print('Downloading pinned Zig compiler (80 MB)...', flush=True)
            with opener.open(item['url'], timeout=90) as response, wheel.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            if hashlib.sha256(wheel.read_bytes()).hexdigest() != item['sha256']:
                raise RuntimeError('Compiler archive checksum mismatch')
            with zipfile.ZipFile(wheel) as archive:
                archive.extractall(target)
        print(subprocess.check_output([str(exe), 'version'], text=True).strip())
    if verilator:
        item=lock['verilator_linux_x64'];target=ROOT/'.tools/verilator_linux'
        if not (target/'verilator').is_dir():
            target.mkdir(parents=True,exist_ok=True)
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}) if direct else urllib.request.ProxyHandler())
            print('Downloading pinned Linux Verilator (6.5 MB)...',flush=True)
            data=opener.open(item['url'],timeout=90).read()
            if hashlib.sha256(data).hexdigest()!=item['sha256']:raise RuntimeError('Verilator checksum mismatch')
            import io
            with zipfile.ZipFile(io.BytesIO(data)) as archive:archive.extractall(target)
    print('E203 dependency pinned at', dep['commit'], flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', action='store_true', help='Install local Windows x64 Zig cross-compiler')
    parser.add_argument('--direct', action='store_true', help='Bypass proxy for this download only')
    parser.add_argument('--verilator',action='store_true',help='Install Linux Verilator for WSL simulation')
    args = parser.parse_args()
    setup(args.compiler, args.direct,args.verilator)
