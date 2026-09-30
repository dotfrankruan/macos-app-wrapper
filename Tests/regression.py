import json
import pathlib
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='appwrapper-test-') as temp:
    root = pathlib.Path(temp)
    source = root / 'hello $(touch INJECTED) `touch BACKTICK` \' " $HOME'
    source.write_text('#!/bin/zsh\nprintf "ok:%s\\n" "$1"\n')
    config = dict(executable=str(source), appName='Safe', bundleID='com.example.safe',
                  outputDirectory=str(root / 'out'), copyDependencies=False, adhocSign=False)
    def build(**updates):
        path = root / 'config.json'
        path.write_text(json.dumps(config | updates))
        return subprocess.run([str(binary), '--cli', str(path)], capture_output=True, text=True)
    def check(result, success):
        assert (result.returncode == 0) == success, result.stdout + result.stderr
    check(build(), True)
    app = root / 'out/Safe.app'
    launcher = app / 'Contents/MacOS/Safe'
    run = subprocess.run([str(launcher), 'a b'], capture_output=True, text=True)
    assert run.returncode == 0 and run.stdout == 'ok:a b\n', run
    payload = app / 'Contents/Resources/payload'
    assert not (payload / 'INJECTED').exists()
    assert not (payload / 'BACKTICK').exists()
    link = root / 'linked'
    link.symlink_to(source)
    check(build(executable=str(link)), True)
    assert subprocess.check_output([str(launcher), 'link'], text=True) == 'ok:link\n'
    before = launcher.read_bytes()
    check(build(icon=str(root / 'missing.icns')), False)
    assert launcher.read_bytes() == before
    check(build(appName='../Escape'), False)
    assert not (root / 'Escape.app').exists()
    check(build(executable=str(root)), False)
    assert launcher.read_bytes() == before
    check(build(script='#!/bin/zsh\nprintf replaced'), True)
    assert subprocess.check_output([str(launcher)], text=True) == 'replaced'
    check(build(script=''), True)
    assert subprocess.check_output([str(launcher), 'x'], text=True) == 'ok:x\n'
    assert not list((root / 'out').glob('.AppWrapper-*'))
print('PASS: shell quoting, arguments, failed-build preservation, path rejection, directory rejection, replacement, blank template, staging cleanup')
