#ifndef ASSISTANT_JAVASCRIPT_H
#define ASSISTANT_JAVASCRIPT_H
#include <stddef.h>
#include <stdint.h>

typedef struct PAJSControl PAJSControl;
PAJSControl *pa_js_control_create(void);
void pa_js_control_cancel(PAJSControl *control);
void pa_js_control_free(PAJSControl *control);
/* Result: 0 success, 1 script error, 2 cancelled/deadline, 3 output limit, 4 allocation failure. */
int pa_js_run(PAJSControl *control, const char *source, size_t source_len,
              const char *input, size_t input_len, size_t memory_bytes,
              uint64_t timeout_ms, size_t output_limit, char **output, size_t *output_len);
void pa_js_string_free(char *value);
#endif
