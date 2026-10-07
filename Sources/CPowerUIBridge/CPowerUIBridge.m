#import "CPowerUIBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

// Runtime declaration of the system interface. No private SDK headers needed.
@protocol BCLMOptimizationClient
- (id)initWithClientName:(NSString *)name;
- (NSDictionary *)status;
- (NSDictionary *)powerLogStatus;
- (void)resetEngagementOverride;
- (BOOL)disableSmartCharging:(NSError **)error;
@end

static id<BCLMOptimizationClient> optimization;

static bool prepareClient(void) {
    if (optimization) return true;
    if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI",
                RTLD_NOW | RTLD_LOCAL)) return false;
    Class type = NSClassFromString(@"PowerUISmartChargeClient");
    if (!type) return false;
    NSArray *methods = @[@"initWithClientName:", @"status", @"powerLogStatus",
        @"resetEngagementOverride", @"disableSmartCharging:"];
    for (NSString *method in methods) {
        if (![type instancesRespondToSelector:NSSelectorFromString(method)]) return false;
    }
    optimization = [[type alloc] initWithClientName:@"bclm_loop"];
    return optimization != nil;
}

static int32_t field(NSDictionary *dictionary, NSString *key) {
    id number = dictionary[key];
    return [number respondsToSelector:@selector(intValue)] ? [number intValue] : -1;
}

bool BCLMPowerUIRead(BCLMPowerUIState *output) {
    @autoreleasepool {
        @try {
            if (!output || !prepareClient()) return false;
            NSDictionary *status = [optimization status];
            NSDictionary *log = [optimization powerLogStatus];
            if (![status isKindOfClass:[NSDictionary class]] ||
                ![log isKindOfClass:[NSDictionary class]]) return false;
            BCLMPowerUIState state = {
                field(status, @"Enabled"), field(status, @"CurrentState"),
                field(status, @"Checkpoint"), field(log, @"isEngaged")
            };
            if (state.engaged < 0) state.engaged = state.enabled == 1 && state.state == 1;
            if (state.enabled < 0 || state.state < 0 || state.checkpoint < 0) return false;
            *output = state;
            return true;
        } @catch (NSException *exception) { return false; }
    }
}

static bool awaitState(int enabled, int state, int checkpoint, int engaged, int polls) {
    for (int remaining = polls; remaining > 0; --remaining) {
        BCLMPowerUIState current;
        if (BCLMPowerUIRead(&current) && current.enabled == enabled &&
            current.state == state && current.checkpoint == checkpoint &&
            (engaged < 0 || current.engaged == engaged)) return true;
        usleep(100000);
    }
    return false;
}

// Cleanup only. Do not re-engage native OBC: the 15.8 implementation
// always includes the firmware drain option in its 80% limit request.
bool BCLMPowerUIRelease(void) {
    @autoreleasepool {
        @try {
            BCLMPowerUIState current;
            if (!BCLMPowerUIRead(&current)) return false;
            if (current.enabled == 0 && current.state == 0 &&
                current.checkpoint == 10 && current.engaged == 0) return true;
            [optimization resetEngagementOverride];
            usleep(300000);
            NSError *error = nil;
            if (![optimization disableSmartCharging:&error] || error) return false;
            return awaitState(0, 0, 10, 0, 40);
        } @catch (NSException *exception) { return false; }
    }
}
