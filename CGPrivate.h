// Private API declarations shared by Tweak.x (callservicesd), TweakPhone.x (MobilePhone) and CGPolicy.m.
#import <Foundation/Foundation.h>

@interface TUHandle : NSObject
@property (nonatomic, readonly, copy) NSString *value;
@end

// The filtered object is a CSDCall on iOS 16 and a call update on iOS 17, and the filters' selectors differ too.
// Declared on NSObject so one set of helpers can talk to both.
@interface NSObject (CallGuardPrivate)
- (TUHandle *)handle;                 // CSDCall (iOS 16)
- (TUHandle *)remoteHandle;           // call update (iOS 17)
- (id)provider;                       // CSDCall (iOS 16)
- (BOOL)isTelephonyProvider;
- (void)setFilteredOutReason:(int)reason;
- (int)filteredOutReason;
- (BOOL)isUnknownCall:(id)call;       // iOS 16
- (BOOL)isUnknownCaller:(id)update;   // iOS 17
- (id)filters;                        // collection of the individual filters
- (id)silencingUserInfo;              // mutable dictionary the contacts filter writes its findings into

// MobilePhone (Phone app)
- (id)lcdView;                        // PHHandsetDialerView
- (id)contactLabel;                   // PHHandsetDialerLCDView, a PHHandsetDialerNameLabelView
- (NSString *)displayedName;          // PHHandsetDialerNameLabelView, the contact name shown under the digits
- (id)featureFlags;                   // MPFavoritesTableViewController (iOS 18)
- (BOOL)favoritesCallTapTargetsEnabled; // TUFeatureFlags (iOS 18)
- (NSString *)actionType;             // CNFavoritesEntry
- (NSString *)name;                   // CNFavoritesEntry
- (NSString *)callerName;             // CHRecentCall
- (NSString *)callerId;               // CHRecentCall
@end
