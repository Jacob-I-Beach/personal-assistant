import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join, resolve, sep, extname } from 'node:path';
import { randomUUID } from 'node:crypto';

const IMAGE = 'personal-assistant-compute:1.0';
const safeName = name => typeof name === 'string' && name.length > 0 && name.length < 180 && !/[\\/:\x00-\x1f]/.test(name) && !['.','..'].includes(name) && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name);

function processResult(executable, args, {signal, timeout = 15000, maximumBytes = 96 * 1024 * 1024, onStop} = {}) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(executable, args, {windowsHide: true, stdio: ['ignore','pipe','pipe'], shell: false});
    const chunks = []; let length = 0, stderr = '', ended = false, stopped = false;
    const stop = () => { if (ended || stopped) return; stopped = true; onStop?.(); child.kill(); };
    const timer = setTimeout(stop, timeout);
    signal?.addEventListener('abort', stop, {once: true});
    child.stdout.on('data', data => { length += data.length; if (length > maximumBytes) stop(); else chunks.push(data); });
    child.stderr.on('data', data => { if (stderr.length < 4000) stderr += data.toString().slice(0,4000-stderr.length); });
    child.on('error', () => { ended = true; clearTimeout(timer); signal?.removeEventListener('abort', stop); reject(new Error('The computation service could not start.')); });
    child.on('close', code => {
      ended = true; clearTimeout(timer); signal?.removeEventListener('abort', stop);
      if (signal?.aborted) reject(signal.reason ?? new Error('Stopped'));
      else if (stopped) reject(new Error('This computation reached its time or output allowance.'));
      else if (code !== 0) reject(Object.assign(new Error('The isolated computation did not finish.'), {diagnostic: stderr}));
      else resolveResult(Buffer.concat(chunks));
    });
    if (signal?.aborted) stop();
  });
}

export class ComputeRuntime {
  constructor({root, store, docker = 'C:\\Program Files\\Docker\\Docker\\resources\\bin\\docker.exe'}) {
    this.root = resolve(root); this.store = store; this.docker = docker;
  }
  get definitions() { return computerTools; }
  supports(name) { return ['run_python','inspect_document'].includes(name); }
  title(name) { return name === 'inspect_document' ? 'Inspecting the actual document' : 'Working with your data'; }
  summary() { return 'Python on your computer with selected file inputs, scientific and document libraries, bounded execution and task-scoped state. Native phone actions still require the iPhone.'; }
  async available() {
    try {
      const context = (await processResult(this.docker, ['context','inspect','desktop-linux','--format','{{.Endpoints.docker.Host}}'])).toString().trim();
      if (context !== 'npipe:////./pipe/dockerDesktopLinuxEngine') return false;
      await processResult(this.docker, ['--context','desktop-linux','image','inspect', IMAGE, '--format','{{.Id}}']);
      return true;
    } catch { return false; }
  }
  async execute(call, job, signal) {
    if (!await this.available()) throw Object.assign(new Error(), {publicMessage: 'Start the computer’s computation service to use Python and document inspection.'});
    const args = call.arguments ?? {};
    const ids = Array.isArray(args.file_ids) ? [...args.file_ids] : typeof args.file_ids === 'string' ? JSON.parse(args.file_ids) : [];
    if (!Array.isArray(ids) || ids.length > 12 || ids.some(id => typeof id !== 'string')) throw new Error('Choose up to twelve task file IDs.');
    if (call.name === 'inspect_document' && typeof args.file_id === 'string' && !ids.includes(args.file_id)) ids.push(args.file_id);
    await mkdir(this.root, {recursive: true});
    const directory = await mkdtemp(join(this.root, 'execution-'));
    if (!directory.startsWith(this.root + sep)) throw new Error('Invalid execution directory.');
    const inputs = join(directory, 'inputs'), task = join(directory, 'task');
    await mkdir(inputs); await mkdir(task);
    const container = 'personal-assistant-' + randomUUID();
    const stopContainer = () => new Promise(resolveCleanup=>{
      const cleanup=spawn(this.docker,['--context','desktop-linux','rm','--force',container],{windowsHide:true,stdio:'ignore'});
      const timer=setTimeout(()=>{cleanup.kill();resolveCleanup();},10000);
      const done=()=>{clearTimeout(timer);resolveCleanup();};cleanup.on('error',done);cleanup.on('close',done);
    });
    try {
      const files = [], seen = new Set(); let inputBytes = 0, containsHealthData=job.payload.contains_health_data===true;
      for (const id of ids) {
        const file = this.store.file(job.id, job.owner, id);
        containsHealthData ||= file.metadata.contains_health_data===true;
        inputBytes += file.data.length;
        if (inputBytes > 64 * 1024 * 1024) throw new Error('Selected files exceed this execution’s input allowance.');
        let filename = safeName(file.metadata.filename) ? file.metadata.filename : id + extname(file.metadata.filename).slice(0,12);
        if (seen.has(filename.toLowerCase())) filename = id.slice(0,8) + '-' + filename;
        seen.add(filename.toLowerCase());
        await writeFile(join(inputs, filename), file.data, {flag: 'wx', mode: 0o600});
        files.push({id, filename, path: '/inputs/' + filename, sha256: file.metadata.sha, version: file.metadata.version});
      }
      const timeout = Math.min(180, Math.max(1, Number(args.timeout_seconds) || 60));
      let state = null;
      if (args.state_file_id) state = JSON.parse(this.store.file(job.id, job.owner, args.state_file_id).data.toString('utf8'));
      const request = {mode: call.name === 'inspect_document' ? 'inspect' : 'python', files,
        input: typeof args.input_json === 'string' ? JSON.parse(args.input_json) : null, state, timeout_seconds: timeout};
      if (call.name === 'inspect_document') {
        request.document_path = files.find(file => file.id === args.file_id)?.path;
        if (!request.document_path) throw new Error('The document was not supplied to this task.');
        request.page = Math.min(500, Math.max(1, Number(args.page) || 1));
      } else {
        if (typeof args.code !== 'string' || Buffer.byteLength(args.code) > 128 * 1024) throw new Error('Provide a bounded Python program.');
        await writeFile(join(task,'code.py'), args.code);
      }
      await writeFile(join(task,'request.json'), JSON.stringify(request));
      const data = await processResult(this.docker, ['--context','desktop-linux','run','--rm','--pull=never','--name',container,
        '--network=none','--read-only','--cap-drop=ALL','--security-opt=no-new-privileges','--pids-limit=64',
        '--memory=1536m','--memory-swap=1536m','--cpus=2','--user=65532:65532',
        '--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=256m,mode=1777',
        '--tmpfs','/outputs:rw,nosuid,nodev,noexec,size=128m,mode=1777',
        '--mount',`type=bind,source=${inputs},target=/inputs,readonly`,
        '--mount',`type=bind,source=${task},target=/task,readonly`, IMAGE],
        {signal, timeout: (timeout + 20) * 1000, onStop: stopContainer});
      const result = JSON.parse(data.toString('utf8'));
      if (typeof result.succeeded !== 'boolean' || !Array.isArray(result.files) || result.files.length > 30) throw new Error('The computation returned an invalid result.');
      const outputs = []; let outputBytes = 0;
      for (const file of result.files) {
        if (!safeName(file.filename) || typeof file.data_base64 !== 'string') throw new Error('An output has an invalid name.');
        const bytes = Buffer.from(file.data_base64, 'base64'); outputBytes += bytes.length;
        if (bytes.length > 24 * 1024 * 1024 || outputBytes > 48 * 1024 * 1024) throw new Error('Outputs exceed this task’s allowance.');
        outputs.push(this.store.saveFile(job.id, {filename: file.filename, source_operation_id: call.id, role: call.name === 'inspect_document' ? 'inspection' : 'artifact', contains_health_data: containsHealthData}, bytes));
      }
      let stateFile = null;
      if (result.state != null) stateFile = this.store.saveFile(job.id, {filename: 'intermediate-state.json', role: 'state', source_operation_id: call.id,contains_health_data:containsHealthData}, Buffer.from(JSON.stringify(result.state)));
      return {callID: call.id, name: call.name, succeeded: result.succeeded, completedAt: new Date().toISOString(),
        output: {status: result.succeeded ? 'completed' : 'failed', execution_location: 'your computer', result: result.result,
          output: result.stdout, output_truncated: result.stdout_truncated === true, error: result.error,
          files: outputs, state_file: stateFile, source_files: files.map(({id,sha256,version}) => ({id,sha256,version})),
          verification: call.name === 'inspect_document' ? 'Opened the source and returned bounded structural/page evidence.' : 'Code executed; inspect generated documents before claiming their layout is ready.'}};
    } finally {
      await stopContainer();
      if (!resolve(directory).startsWith(this.root + sep) || resolve(directory) === this.root) throw new Error('Temporary cleanup path is invalid.');
      await rm(directory, {recursive: true, force: true, maxRetries: 2});
    }
  }
}

const nullableString = {type: ['string','null']};
const object = properties => ({type: 'object', properties, required: Object.keys(properties), additionalProperties: false});
export const computerTools = [
  {name: 'run_python', description: 'Execute Python on the connected computer against selected task files. Includes NumPy, pandas, SciPy, Matplotlib, openpyxl, XlsxWriter, python-docx, python-pptx, ReportLab and PDF tools. Read files from assistant.files or /inputs; write artifacts to /outputs. Use assistant.publish(value) for a concise result and assistant.save_state(value) for reusable intermediate data. No task network or general host filesystem. Default 60 seconds, maximum 180; 1536 MiB memory.',
    parameters: object({code: {type: 'string'}, file_ids: {type:'array',items:{type:'string'},maxItems:12}, input_json: {...nullableString, description:'Optional JSON text parsed into assistant.input, or null. Use file IDs for datasets.'},
      state_file_id: nullableString, timeout_seconds: {type:'integer',minimum:1,maximum:180}})},
  {name: 'inspect_document', description: 'Open a task document, inspect page/sheet structure and render the requested actual page. Supports PDF, Word, Excel and PowerPoint. Formulas and cached values are separate; previews report coverage. Returns image evidence for the selected page and preserves the original.',
    parameters: object({file_id:{type:'string'},page:{type:'integer',minimum:1,maximum:500},file_ids:{type:'array',items:{type:'string'},maxItems:12}})}
];
