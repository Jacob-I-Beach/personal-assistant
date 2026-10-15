// Personal Assistant adaptation of the upstream text-only Responses helper.
// The upstream noncommercial license applies to this component.
import OpenAI from "openai";
import { apiError, ChatGPTError, isObject } from "./errors.js";
import type { StructuredResponseOptions } from "./types.js";
import { CompletedResponse } from './completed-response.js';

export async function streamStructuredResponse(accessToken: string, options: StructuredResponseOptions, signal: AbortSignal, transport: typeof fetch = fetch): Promise<Record<string, unknown>> {
  const allowed = new Set(["model", "input", "instructions", "tools", "reasoning", "include", "parallel_tool_calls", "text", "store", "stream"]);
  if (Object.keys(options.body).some(key => !allowed.has(key)) || typeof options.body.model !== "string" || !Array.isArray(options.body.input)) {
    throw new ChatGPTError("invalid_request", "The task contains unsupported ChatGPT request fields.");
  }
  if (options.body.input.some(item => isObject(item) && item.role === "system")) {
    throw new ChatGPTError("invalid_request", "Put system guidance in instructions.");
  }
  const client = new OpenAI({apiKey: accessToken, baseURL: "https://api.openai.com/v1", organization: null, project: null,
    logLevel: "warn", maxRetries: 0, fetch: transport, fetchOptions: {redirect: "error"},
    defaultHeaders: {authorization: `Bearer ${accessToken}`, "openai-organization": null, "openai-project": null}});
  const requestSignal = AbortSignal.any([signal, AbortSignal.timeout(60 * 60 * 1000)]);
  let response: Response | undefined;
  try {
    const body = {...options.body, store: false, stream: true} as unknown as OpenAI.Responses.ResponseCreateParamsStreaming;
    const result = await client.responses.create(body, {signal: requestSignal, headers: {accept: "text/event-stream"}}).withResponse();
    response = result.response;
    const contentType = response.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
    if (!response.body || (contentType && contentType !== "text/event-stream")) {
      await response.body?.cancel();
      throw new ChatGPTError("invalid_stream", "ChatGPT did not return the expected response stream.", true, response.status);
    }
    let receivedBytes = 0;
    const assembly = new CompletedResponse();
    for await (const value of result.data) {
      requestSignal.throwIfAborted();
      if (!isObject(value)) continue;
      const event = value as unknown as Record<string, unknown>;
      receivedBytes += Buffer.byteLength(JSON.stringify(event));
      if (receivedBytes > 32 * 1024 * 1024) throw new ChatGPTError("response_too_large", "The response exceeded this task's output allowance.");
      if (event.type === "response.failed" || event.type === "error") {
        throw apiError(event.type === "response.failed" ? event.response : event, response.status, result.request_id);
      }
      if (event.type === "response.incomplete") {
        const partial=isObject(event.response)?event.response:null;
        if(isObject(partial?.incomplete_details)&&partial.incomplete_details.reason==='max_output_tokens'){
          throw Object.assign(new ChatGPTError('output_limit','The reply reached its output allowance; saved text can continue.'),{partialOutput:assembly.partialText(partial)});
        }
        throw new ChatGPTError("response_incomplete", "The model stopped before this step completed. Saved progress remains available.", true);
      }
      await options.onEvent?.(event);
      const completed = assembly.accept(event);
      if (completed) return completed;
    }
    requestSignal.throwIfAborted();
    throw new ChatGPTError("stream_interrupted", "The model connection ended before completion. Saved progress remains available.", true);
  } catch (error) {
    if (signal.aborted) throw new ChatGPTError("cancelled", "The task was stopped.");
    if (error instanceof ChatGPTError) throw error;
    if (error instanceof OpenAI.APIError && !(error instanceof OpenAI.APIConnectionError) && !(error instanceof OpenAI.APIUserAbortError)) {
      const detail = typeof error.error === "string" ? {error: error.error} : error.error;
      throw apiError(detail, error.status ?? response?.status, error.requestID ?? response?.headers.get("x-request-id"));
    }
    throw new ChatGPTError(response ? "stream_interrupted" : "network_error", "The computer could not finish this model connection. Saved progress is kept.", true);
  }
}
