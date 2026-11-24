// Preferences state and the "should this call / notification be blocked" decisions, shared by Tweak.x and TweakPhone.x.
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "CGPrivate.h"

#ifdef __cplusplus
extern "C" {
#endif

// iOS 17: shouldFilterIncomingCall:from: and isUnknownCaller:. Set by Tweak.x before the hooks are installed.
extern BOOL CGUpdateAPI;

// Idempotent: loads the preferences and starts listening for CG_PREFS_CHANGED. Both %ctor call it.
void CGPolicyInit(void);

// callservicesd. subject: the CSDCall (iOS 16) or the call update (iOS 17)
BOOL CGShouldBlock(id controller, id subject, TUHandle *handle, BOOL telephony);
BOOL CGShouldDropNotification(UNNotificationRequest *request);

// MobilePhone. The Phone app is sandboxed and cannot read our preferences domain, so callservicesd publishes the
// "confirm before calling" switch as the state of a Darwin notification and the Phone app reads that state.
BOOL CGPhoneConfirmCalls(void);

#ifdef __cplusplus
}
#endif
