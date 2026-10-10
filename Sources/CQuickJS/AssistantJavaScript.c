#include "AssistantJavaScript.h"
#include "vendor/quickjs.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

struct PAJSControl { atomic_bool cancelled; uint64_t deadline; };
static uint64_t monotonic_ms(void) {
#ifdef _WIN32
    return GetTickCount64();
#else
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000 + (uint64_t)time.tv_nsec / 1000000;
#endif
}
PAJSControl *pa_js_control_create(void) {
    PAJSControl *control = calloc(1, sizeof(*control));
    if (control) atomic_init(&control->cancelled, false);
    return control;
}
void pa_js_control_cancel(PAJSControl *control) { atomic_store(&control->cancelled, true); }
void pa_js_control_free(PAJSControl *control) { free(control); }
void pa_js_string_free(char *value) { free(value); }
static int interrupt(JSRuntime *runtime, void *opaque) {
    PAJSControl *control = opaque;
    (void)runtime;
    return atomic_load(&control->cancelled) || monotonic_ms() >= control->deadline;
}
static int copy_string(JSContext *context, JSValueConst value, size_t limit,
                       char **output, size_t *output_len) {
    size_t length = 0;
    const char *text = JS_ToCStringLen(context, &length, value);
    if (!text) return 4;
    if (length > limit) { JS_FreeCString(context, text); return 3; }
    *output = malloc(length + 1);
    if (!*output) { JS_FreeCString(context, text); return 4; }
    memcpy(*output, text, length);
    (*output)[length] = 0;
    *output_len = length;
    JS_FreeCString(context, text);
    return 0;
}
static JSValue json_value(JSContext *context, JSValueConst this_value, int count, JSValueConst *arguments) {
    (void)this_value;
    if (count < 2) return JS_ThrowTypeError(context, "Invalid JSON result.");
    JSValueConst value = arguments[1];
    double number;
    if (JS_IsNumber(value) && (JS_ToFloat64(context, &number, value) < 0 || !isfinite(number)))
        return JS_ThrowTypeError(context, "Return finite numbers; NaN and Infinity are not valid results.");
    if (JS_IsUndefined(value) || JS_IsFunction(context, value) || JS_IsBigInt(value))
        return JS_ThrowTypeError(context, "Return JSON-compatible values; convert BigInt to a string explicitly.");
    if (JS_IsObject(value) && JS_PromiseState(context, value) != JS_PROMISE_NOT_A_PROMISE)
        return JS_ThrowTypeError(context, "Only synchronous scripts are supported. Return the computed result, not a Promise.");
    return JS_DupValue(context, value);
}
int pa_js_run(PAJSControl *control, const char *source, size_t source_len,
              const char *input, size_t input_len, size_t memory_bytes,
              uint64_t timeout_ms, size_t output_limit, char **output, size_t *output_len) {
    *output = NULL; *output_len = 0;
    control->deadline = monotonic_ms() + timeout_ms;
    if (interrupt(NULL, control)) return 2;
    JSRuntime *runtime = JS_NewRuntime();
    if (!runtime) return 4;
    JS_SetMemoryLimit(runtime, memory_bytes);
    JS_SetMaxStackSize(runtime, 256 * 1024);
    JS_SetCanBlock(runtime, false);
    JS_SetInterruptHandler(runtime, interrupt, control);
    JSContext *context = JS_NewContext(runtime);
    if (!context) { JS_FreeRuntime(runtime); return 4; }
    int status = 1;
    /* No libc, OS modules, workers, host files, network, native objects or bytecode loader. */
    JSValue global = JS_GetGlobalObject(context);
    JSAtom atom = JS_NewAtom(context, "Atomics");
    JS_DeleteProperty(context, global, atom, 0); JS_FreeAtom(context, atom);
    atom = JS_NewAtom(context, "SharedArrayBuffer");
    JS_DeleteProperty(context, global, atom, 0); JS_FreeAtom(context, atom);
    JSValue data = JS_ParseJSON(context, input, input_len, "input.json");
    if (JS_IsException(data)) { JS_FreeValue(context, global); goto failure; }
    if (JS_SetPropertyStr(context, global, "input", data) < 0) {
        JS_FreeValue(context, global); goto failure;
    }
    JS_FreeValue(context, global);
    JSValue value = JS_Eval(context, source, source_len, "script.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) goto failure;
    JSValue replacer = JS_NewCFunction(context, json_value, "validateResult", 2);
    JSValue json = JS_JSONStringify(context, value, replacer, JS_UNDEFINED);
    JS_FreeValue(context, replacer);
    JS_FreeValue(context, value);
    if (JS_IsException(json)) goto failure;
    if (JS_IsUndefined(json)) { JS_FreeValue(context, json); JS_ThrowTypeError(context, "Return a JSON-compatible value."); goto failure; }
    status = copy_string(context, json, output_limit, output, output_len);
    JS_FreeValue(context, json);
    goto cleanup;
failure: {
    if (interrupt(runtime, control)) { status = 2; goto cleanup; }
    JSValue error = JS_GetException(context);
    int copied = copy_string(context, error, 4096, output, output_len);
    JS_FreeValue(context, error);
    status = copied == 0 ? 1 : copied;
}
cleanup:
    if (interrupt(runtime, control)) status = 2;
    JS_FreeContext(context);
    JS_FreeRuntime(runtime);
    return status;
}
