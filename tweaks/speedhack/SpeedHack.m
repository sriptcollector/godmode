// SpeedHack — injected into any app GODMODE patches.
//
// Scales every Core Animation clock in the app (window.layer.speed):
//   2.0 = UI runs twice as fast, 0.5 = slow motion.
// Speed comes from Documents/godmode.json {"speed": 2.0}, which `gm speed` pushes over USB,
// falling back to the GMSpeed key that `gm patch` writes into Info.plist.
// Three-finger double-tap anywhere opens an on-device speed picker.

#import <UIKit/UIKit.h>

static NSString *const kKey = @"gm.speed";

static NSString *ConfigPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"godmode.json"];
}

static float CurrentSpeed(void) {
    NSData *data = [NSData dataWithContentsOfFile:ConfigPath()];
    if (data) {
        NSDictionary *cfg = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([cfg isKindOfClass:NSDictionary.class] && [cfg[@"speed"] respondsToSelector:@selector(floatValue)])
            return MAX(0.05f, [cfg[@"speed"] floatValue]);
    }
    NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:kKey];
    if (saved) return saved.floatValue;
    NSNumber *baked = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GMSpeed"];
    return baked ? baked.floatValue : 1.0f;
}

static void Apply(float speed) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) w.layer.speed = speed;
    }
}

@interface GMSpeedPicker : NSObject <UIGestureRecognizerDelegate>
@end

@implementation GMSpeedPicker
+ (instancetype)shared { static GMSpeedPicker *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [self new]; }); return s; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }

- (void)attachTo:(UIWindow *)w {
    for (UIGestureRecognizer *g in w.gestureRecognizers) if (g.delegate == self) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    tap.cancelsTouchesInView = NO;
    tap.delegate = self;
    [w addGestureRecognizer:tap];
}

- (void)open:(UITapGestureRecognizer *)g {
    UIViewController *top = g.view.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GODMODE"
        message:[NSString stringWithFormat:@"UI speed: %.2gx", CurrentSpeed()]
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in @[@0.25, @0.5, @1, @1.5, @2, @3, @5]) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@x", n]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                [NSFileManager.defaultManager removeItemAtPath:ConfigPath() error:nil];
                [NSUserDefaults.standardUserDefaults setObject:n forKey:kKey];
                Apply(n.floatValue);
            }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = g.view;
    [top presentViewController:a animated:YES completion:nil];
}
@end

__attribute__((constructor)) static void GMInit(void) {
    NSLog(@"[GODMODE] SpeedHack loaded in %@ (speed %.2fx)", NSBundle.mainBundle.bundleIdentifier, CurrentSpeed());
    void (^refresh)(NSNotification *) = ^(NSNotification *n) {
        Apply(CurrentSpeed());
        if ([n.object isKindOfClass:UIWindow.class]) [GMSpeedPicker.shared attachTo:n.object];
    };
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
}
