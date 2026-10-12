import { ChatGPTError, isObject } from './errors.js';

/** Some ChatGPT streams deliver the complete items separately and leave the
 * terminal output empty. Only item.done + response.completed authorizes use. */
export class CompletedResponse {
  private items = new Map<number, Record<string, unknown>>();
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
