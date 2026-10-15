import { ChatGPTError, isObject } from './errors.js';

/** Some ChatGPT streams deliver the complete items separately and leave the
 * terminal output empty. Only item.done + response.completed authorizes use. */
export class CompletedResponse {
  private items = new Map<number, Record<string, unknown>>();
  partialText(response: unknown): Record<string, unknown>[] {
    const terminal = isObject(response) && Array.isArray(response.output) ? response.output : [];
    const values = terminal.length ? terminal : [...this.items.entries()].sort((a,b)=>a[0]-b[0]).map(([,item])=>item);
    // Public text can be continued. An incomplete response NEVER authorizes a
    // function call, even if its partial JSON happens to parse.
    return values.filter(isObject).filter(item=>item.type==='message').map(item=>({...(typeof item.id==='string'?{id:item.id}:{}),type:'message',role:'assistant',content:
      (Array.isArray(item.content)?item.content:[]).filter(isObject).filter(part=>part.type==='output_text'&&typeof part.text==='string').map(part=>({type:'output_text',text:part.text}))})).filter(item=>item.content.length>0);
  }
  accept(event: Record<string, unknown>): Record<string, unknown> | undefined {
    if (event.type === 'response.output_item.done') {
      const index = event.output_index;
      if (!Number.isSafeInteger(index) || (index as number) < 0 || (index as number) >= 512 || !isObject(event.item)) {
        throw new ChatGPTError('invalid_stream', 'The response contained an invalid completed item.');
      }
      this.items.set(index as number, event.item);
    }
    if (event.type !== 'response.completed') return;
    if (!isObject(event.response) || (event.response.status !== undefined && event.response.status !== 'completed') || event.response.error) {
      throw new ChatGPTError('response_incomplete', 'The model did not confirm a completed response.');
    }
    const terminal = Array.isArray(event.response.output) ? event.response.output : [];
    const output = terminal.length ? terminal : [...this.items.entries()].sort((a,b)=>a[0]-b[0]).map(([,item])=>item);
    for (const item of output) {
      if (!isObject(item)) throw new ChatGPTError('invalid_stream', 'The response contained an invalid output.');
      if (item.type === 'function_call' && (item.status !== undefined && item.status !== 'completed')) {
        throw new ChatGPTError('response_incomplete', 'An action was not fully prepared. It has not been executed.');
      }
    }
    return {...event.response, output};
  }
}
