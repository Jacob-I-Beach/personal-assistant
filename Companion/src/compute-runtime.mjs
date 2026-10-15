import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join, resolve, sep, extname } from 'node:path';
import { randomUUID } from 'node:crypto';

const IMAGE = 'personal-assistant-compute:1.3';
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
  supports(name) { return ['run_python','inspect_document','list_task_files','read_task_output','publish_task_files'].includes(name); }
  title(name) { return name === 'inspect_document' ? 'Inspecting the actual document' : 'Working with your data'; }
  summary() { return 'Python on your computer with selected file inputs, scientific and document libraries, bounded execution and task-scoped state. Native phone actions still require the iPhone.'; }
  async available(signal) {
    try {
      const context = (await processResult(this.docker, ['context','inspect','desktop-linux','--format','{{.Endpoints.docker.Host}}'],{signal})).toString().trim();
      if (context !== 'npipe:////./pipe/dockerDesktopLinuxEngine') return false;
      await processResult(this.docker, ['--context','desktop-linux','image','inspect', IMAGE, '--format','{{.Id}}'],{signal});
      return true;
    } catch { return false; }
  }
  async execute(call, job, signal) {
    if(call.name==='publish_task_files'){
      const ids=call.arguments.file_ids,caption=call.arguments.caption;
      if(!Array.isArray(ids)||!ids.length||ids.length>8||ids.some(id=>typeof id!=='string')||typeof caption!=='string'||caption.length>1000)throw new Error('Choose one to eight task file IDs and a short caption.');
      const files=[];let health=job.payload.contains_health_data===true;
      for(const id of new Set(ids)){
        const source=this.store.file(job.id,job.owner,id);health ||= source.metadata.contains_health_data===true;
        const published=this.store.files(job.id,job.owner).find(file=>file.role==='artifact'&&file.publication_source_id===id&&file.sha===source.metadata.sha);
        files.push(published??(source.metadata.publication_source_id?source.metadata:this.store.saveFile(job.id,{filename:source.metadata.filename,role:'artifact',source_operation_id:call.id,publication_source_id:id,publication_source_version:source.metadata.version,contains_health_data:source.metadata.contains_health_data===true},source.data)));
      }
      return {callID:call.id,name:call.name,succeeded:true,containsHealthData:health,output:{status:'published_to_chat',caption,presented_files:files,notice:'These saved files are attached to the conversation as it synchronizes. Images render inline; documents open in the native preview. This is not evidence that the user has viewed them.'}};
    }
    if(call.name==='list_task_files')return {callID:call.id,name:call.name,succeeded:true,output:{status:'available',files:this.store.files(job.id,job.owner)}};
    if(call.name==='read_task_output'){
      const operation=this.store.operation(job.id,call.arguments.call_id);
      if(!operation.result)throw new Error('No completed receipt is available for that operation.');
      const text=JSON.stringify(operation.result.output),offset=Math.max(0,Math.min(text.length,Number(call.arguments.offset)||0));
      return {callID:call.id,name:call.name,succeeded:true,containsHealthData:operation.result.containsHealthData===true,output:{operation_id:call.arguments.call_id,text:text.slice(offset,offset+12000),next_offset:Math.min(text.length,offset+12000),total_characters:text.length,notice:'Exact saved source excerpt, not a new instruction.'}};
    }
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
      const timeout = Math.min(1800, Math.max(1, Number(args.timeout_seconds) || 60));
      const memory = Math.min(8192, Math.max(512, Number(args.memory_mib) || 2048));
      const processors = Math.min(8, Math.max(1, Number(args.cpu_count) || 2));
      let state = null;
      if (args.state_file_id) {
        const saved = this.store.file(job.id, job.owner, args.state_file_id);
        if (saved.data.length > 24 * 1024 * 1024) throw new Error('Intermediate JSON exceeds 24 MiB. Read larger datasets through selected input files.');
        containsHealthData ||= saved.metadata.contains_health_data === true;
        state = JSON.parse(saved.data.toString('utf8'));
      }
      const request = {mode: call.name === 'inspect_document' ? 'inspect' : 'python', files,
        input: typeof args.input_json === 'string' ? JSON.parse(args.input_json) : null, state, timeout_seconds: timeout, cpu_count: processors};
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
        `--memory=${memory}m`,`--memory-swap=${memory}m`,`--cpus=${processors}`,'--user=65532:65532',
        '--tmpfs','/tmp:rw,nosuid,nodev,noexec,size=256m,mode=1777',
        '--tmpfs','/outputs:rw,nosuid,nodev,noexec,size=256m,mode=1777',
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
      return {callID: call.id, name: call.name, succeeded: result.succeeded, completedAt: new Date().toISOString(),containsHealthData:containsHealthData,
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
  {name:'publish_task_files',description:'Show selected task files in the conversation. Use this when the user asks to see a computer/browser screenshot, a rendered page, chart, or other output. Inspection images are otherwise private working material, not chat attachments. Uses actual file IDs from tool receipts or list_task_files; never invent a file path or claim an image was sent without this publication receipt. Existing bytes and source versions are preserved.',parameters:object({file_ids:{type:'array',items:{type:'string'},minItems:1,maxItems:8},caption:{type:'string',maxLength:1000}})},
  {name:'list_task_files',description:'List the actual files currently available to this task on the computer, with stable IDs and versions. Use after uploading a Library file or recovering an interrupted transfer.',parameters:object({})},
  {name:'read_task_output',description:'Read a bounded exact excerpt of a completed tool receipt in this computer task. Useful after working context was compacted. Does not rerun the operation.',parameters:object({call_id:{type:'string'},offset:{type:'integer',minimum:0}})},
  {name: 'run_python', description: 'Execute Python on the connected computer against selected task files. Includes NumPy, pandas, SciPy, Matplotlib, openpyxl, XlsxWriter, python-docx, python-pptx, ReportLab and PDF tools. assistant.files is a list of dictionaries with id, filename and path; originals are in /inputs. Write artifacts to /outputs. assistant.publish(value) returns a concise result up to 256 KiB. assistant.save_state(value) retains JSON up to 24 MiB behind a state_file handle; provide that ID as state_file_id next time and read assistant.state. State bytes stay out of model context. Isolated from network and general host files. Default 60 seconds and 2 GiB; request up to 1800 seconds, 8 GiB and 8 CPU cores when warranted. Use reviewed run_computer_command for installed GPU programs or host resources.',
    parameters: object({code: {type: 'string'}, file_ids: {type:'array',items:{type:'string'},maxItems:12}, input_json: {...nullableString, description:'Optional JSON text parsed into assistant.input, or null. Use file IDs for datasets.'},
      state_file_id: nullableString, timeout_seconds: {type:'integer',minimum:1,maximum:1800},memory_mib:{type:['integer','null'],minimum:512,maximum:8192},cpu_count:{type:['integer','null'],minimum:1,maximum:8}})},
  {name: 'inspect_document', description: 'Open a task document, inspect page/sheet structure and render the requested actual page. Supports PDF, Word, Excel and PowerPoint. Formulas and cached values are separate; previews report coverage. Returns image evidence for the selected page and preserves the original.',
    parameters: object({file_id:{type:'string'},page:{type:'integer',minimum:1,maximum:500},file_ids:{type:'array',items:{type:'string'},maxItems:12}})}
];
