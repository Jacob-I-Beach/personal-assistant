"""Bounded parent process. User code has no host filesystem or task network."""
import base64
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

MAX_FILE = 24 * 1024 * 1024
MAX_TOTAL = 48 * 1024 * 1024
request = json.loads(Path('/task/request.json').read_text())
timeout = max(1, min(1800, int(request.get('timeout_seconds', 60))))
processors = str(max(1, min(8, int(request.get('cpu_count', 2)))))
Path('/tmp/home').mkdir(exist_ok=True)
stdout_path, stderr_path = Path('/tmp/stdout.log'), Path('/tmp/stderr.log')
mode = request.get('mode', 'python')
command = [sys.executable, '-I', '/runner/inspect_document.py' if mode == 'inspect' else '/runner/user_entry.py']
try:
    with stdout_path.open('wb') as out, stderr_path.open('wb') as err:
        process = subprocess.run(command, stdout=out, stderr=err, timeout=timeout, cwd='/outputs',
                                 env={'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': '/tmp/home', 'PYTHONDONTWRITEBYTECODE': '1', 'MPLBACKEND': 'Agg', 'MPLCONFIGDIR': '/tmp/matplotlib', 'LANG': 'C.UTF-8', 'OPENBLAS_NUM_THREADS': processors, 'OMP_NUM_THREADS': processors, 'MKL_NUM_THREADS': processors, 'NUMEXPR_NUM_THREADS': processors})
    with stdout_path.open('rb') as stream:
        output = stream.read(16384).decode('utf-8', 'replace')
    with stderr_path.open('rb') as stream:
        if stderr_path.stat().st_size > 8192:
            error_bytes = stream.read(3072) + b'\n[Earlier traceback detail omitted]\n'
            stream.seek(-5120, os.SEEK_END)
            error_bytes += stream.read(5120)
        else:
            error_bytes = stream.read(8192)
    error = error_bytes.decode('utf-8', 'replace')
    files, total = [], 0
    candidates = list(Path('/outputs').iterdir())
    if len(candidates) > 30:
        raise ValueError('This execution produced too many output files.')
    for path in sorted(candidates):
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or path.is_symlink():
            raise ValueError('Outputs must be ordinary files in the output folder.')
        if info.st_size > MAX_FILE or total + info.st_size > MAX_TOTAL:
            raise ValueError('Output files exceed the execution allowance.')
        total += info.st_size
        files.append({'filename': path.name, 'data_base64': base64.b64encode(path.read_bytes()).decode('ascii')})
    result_file, state_file = Path('/tmp/assistant-result.json'), Path('/tmp/assistant-state.json')
    result = json.loads(result_file.read_text()) if result_file.exists() and result_file.stat().st_size <= 256 * 1024 else None
    state_value = json.loads(state_file.read_text()) if state_file.exists() and state_file.stat().st_size <= 24 * 1024 * 1024 else None
    print(json.dumps({'succeeded': process.returncode == 0, 'result': result, 'stdout': output,
                      'stdout_truncated': stdout_path.stat().st_size > 16384, 'error': error if process.returncode else None,
                      'state': state_value, 'files': files}, ensure_ascii=False, allow_nan=False))
except subprocess.TimeoutExpired:
    print(json.dumps({'succeeded': False, 'error': 'Execution reached its time allowance.', 'files': []}))
except Exception as error:
    print(json.dumps({'succeeded': False, 'error': str(error)[:500], 'files': []}))
