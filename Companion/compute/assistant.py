"""Small result/state helpers inside the isolated computation environment."""
import json
from pathlib import Path

_request = json.loads(Path('/task/request.json').read_text())
input = _request.get('input')
files = _request.get('files', [])
state = _request.get('state')

def publish(value):
    encoded = json.dumps(value, ensure_ascii=False, allow_nan=False)
    if len(encoded.encode()) > 256 * 1024:
        raise ValueError('Publish a concise result and save larger data as an output file.')
    Path('/tmp/assistant-result.json').write_text(encoded)

def save_state(value):
    encoded = json.dumps(value, ensure_ascii=False, allow_nan=False)
    if len(encoded.encode()) > 24 * 1024 * 1024:
        raise ValueError('Intermediate JSON exceeds 24 MiB. Save larger datasets as bounded output files and retain their task file handles.')
    Path('/tmp/assistant-state.json').write_text(encoded)

def output_path(name):
    if not name or Path(name).name != name or '\\' in name or name in {'.', '..'}:
        raise ValueError('Use a simple output filename.')
    return Path('/outputs') / name
