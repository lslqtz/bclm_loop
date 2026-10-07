#ifndef BCLM_POWER_UI_BRIDGE_H
#define BCLM_POWER_UI_BRIDGE_H
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t enabled;
    int32_t state;
    int32_t checkpoint;
    int32_t engaged;
} BCLMPowerUIState;

bool BCLMPowerUIRead(BCLMPowerUIState *state);
// Cleanup for overrides created by earlier versions; no engagement API.
bool BCLMPowerUIRelease(void);
#endif
