import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
import { Vault } from '../src/vault.mjs';
import { JobStore } from '../src/job-store.mjs';
import { ComputeRuntime } from '../src/compute-runtime.mjs';

test('authorized CSV becomes checked workbook and rendered PDF in the real isolated runtime', async () => {
  const root = await mkdtemp(join(tmpdir(), 'assistant-compute-check-'));
  const store = new JobStore(':memory:', new Vault(randomBytes(32)));
  const job = store.create('synthetic-phone','synthetic-work',{contains_health_data:false}).job;
  const input = store.saveFile(job.id,{filename:'values.csv',role:'input'},Buffer.from('item,value\nFirst,10\nSecond,20\nThird,30\n'));
  const runtime = new ComputeRuntime({root:join(root,'executions'),store});
  try {
    assert.equal(await runtime.available(),true);
    const result = await runtime.execute({id:'calculate',name:'run_python',arguments:{file_ids:[input.id],timeout_seconds:60,input_json:null,state_file_id:null,code:`
import pandas as pd, socket, os
from pathlib import Path
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors
import xlsxwriter
data = pd.read_csv(assistant.files[0]['path'])
total = int(data['value'].sum())
styles = getSampleStyleSheet()
table = Table([['Item','Value']] + data.values.tolist() + [['Total',total]], colWidths=[280,90])
table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#eeeeee')),('GRID',(0,0),(-1,-1),0.5,colors.HexColor('#bbbbbb')),('TOPPADDING',(0,0),(-1,-1),8),('BOTTOMPADDING',(0,0),(-1,-1),8)]))
SimpleDocTemplate('/outputs/report.pdf').build([Paragraph('Synthetic data report',styles['Title']),Spacer(1,18),table])
book = xlsxwriter.Workbook('/outputs/report.xlsx')
sheet = book.add_worksheet('Summary')
sheet.write_row('A1',['Item','Value'])
for i, row in enumerate(data.itertuples(index=False),2): sheet.write_row('A'+str(i),list(row))
sheet.write('A5','Total'); sheet.write_formula('B5','=SUM(B2:B4)',None,total); book.close()
network_blocked = False
try:
    connection = socket.create_connection(('1.1.1.1',443),timeout=0.25); connection.close()
except OSError: network_blocked = True
outside_write_blocked = False
try: Path('/not-an-output').write_text('not allowed')
except OSError: outside_write_blocked = True
assistant.save_state({'total':total})
assistant.publish({'total':total,'network_blocked':network_blocked,'outside_write_blocked':outside_write_blocked,'docker_socket_present':Path('/var/run/docker.sock').exists(),'credentials_present':any(k in os.environ for k in ['OPENAI_API_KEY','ACCESS_TOKEN'])})
`}},job,new AbortController().signal);
    assert.equal(result.succeeded,true,JSON.stringify(result.output));
    assert.equal(result.output.result.total,60);
    assert.equal(result.output.result.network_blocked,true);
    assert.equal(result.output.result.outside_write_blocked,true);
    assert.equal(result.output.result.docker_socket_present,false);
    assert.equal(result.output.result.credentials_present,false);
    assert.ok(result.output.state_file.id);
    const continued = await runtime.execute({id:'continue-calculation',name:'run_python',arguments:{
      file_ids:[], state_file_id:result.output.state_file.id, input_json:JSON.stringify({extra:7}),
      code:"import assistant as imported\nassert imported is assistant\nassistant.publish({'total':assistant.state['total']+assistant.input['extra'], 'fresh_scope':'data' not in globals()})"
    }},job,new AbortController().signal);
    assert.equal(continued.succeeded,true,JSON.stringify(continued.output));
    assert.deepEqual(continued.output.result,{total:67,fresh_scope:true});
    const pdf = result.output.files.find(x=>x.filename==='report.pdf');
    const workbook = result.output.files.find(x=>x.filename==='report.xlsx');
    assert.ok(pdf); assert.ok(workbook);
    const inspected = await runtime.execute({id:'inspect',name:'inspect_document',arguments:{file_id:pdf.id,file_ids:[],page:1}},job,new AbortController().signal);
    assert.equal(inspected.succeeded,true,JSON.stringify(inspected.output));
    assert.equal(inspected.output.result.page_count,1);
    assert.match(inspected.output.result.page_text,/Synthetic data report/);
    const preview = inspected.output.files.find(x=>x.filename==='page-1.png'); assert.ok(preview);
    const inspectedWorkbook=await runtime.execute({id:'inspect-workbook',name:'inspect_document',arguments:{file_id:workbook.id,file_ids:[],page:1}},job,new AbortController().signal);
    assert.equal(inspectedWorkbook.succeeded,true,JSON.stringify(inspectedWorkbook.output));
    const totalCell=inspectedWorkbook.output.result.sheets[0].preview.flat().find(cell=>cell.cell==='B5');
    assert.equal(totalCell.formula,'=SUM(B2:B4)');assert.equal(totalCell.cached_value,60);
    assert.ok(inspectedWorkbook.output.result.page_count>0);
    const evidence = resolve('../../../work/companion-compute-evidence');
    await mkdir(evidence,{recursive:true});
    await writeFile(join(evidence,'report-page.png'),store.file(job.id,job.owner,preview.id).data);
    await writeFile(join(evidence,'report.pdf'),store.file(job.id,job.owner,pdf.id).data);
    await writeFile(join(evidence,'report.xlsx'),store.file(job.id,job.owner,workbook.id).data);
    await writeFile(join(evidence,'result.json'),JSON.stringify({calculation:result.output.result,inspection:inspected.output.result,spreadsheet:inspectedWorkbook.output.result},null,2));
  } finally { store.close(); await rm(root,{recursive:true,force:true}); }
});
