// GodModeKit — injected into every app GODMODE patches. Everything here runs on the phone,
// live, with no computer attached.
//
//   open the menu:  three-finger double-tap  OR  two-finger hold (1s)
//
//   • Edit layout — tap any element (nav-bar tab, button, banner, whole section) and hide it.
//     Rules persist per app and re-apply instantly whenever the app redraws.
//     Hidden tabs in a tab row collapse so the remaining tabs spread out evenly.
//   • Speed      — scales every Core Animation clock in the app (window.layer.speed), 0.25x … 5x.
//   • Time limit — after N minutes/day the app turns grayscale and drops to slow motion.
//
// The Mac can still push Documents/godmode.json {"speed": 2} via `gm speed`.

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#define GMLog(fmt, ...) NSLog(@"[GODMODE] " fmt, ##__VA_ARGS__)

static NSString *const kSpeed = @"gm.speed";
static NSString *const kRules = @"gm.rules";
static NSString *const kLimit = @"gm.limitMinutes";
static NSString *const kUsagePrefix = @"gm.usage.";
static NSString *const kGPSOn  = @"gm.gps.on";
static NSString *const kGPSLat = @"gm.gps.lat";
static NSString *const kGPSLon = @"gm.gps.lon";
static NSString *const kGPSName = @"gm.gps.name";

static NSUserDefaults *D(void) { return NSUserDefaults.standardUserDefaults; }

#pragma mark - windows

static NSArray<UIWindow *> *AppWindows(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        [out addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    return out;
}

static UIWindow *KeyWindow(void) {
    for (UIWindow *w in AppWindows()) if (w.isKeyWindow) return w;
    return AppWindows().firstObject;
}

static UIViewController *TopVC(void) {
    UIViewController *top = KeyWindow().rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

#pragma mark - speed

static NSString *ConfigPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"godmode.json"];
}

static BOOL gTimesUp = NO;

static float ChosenSpeed(void) {
    NSData *data = [NSData dataWithContentsOfFile:ConfigPath()];
    if (data) {  // pushed from the Mac — adopt it as the on-phone setting, then consume it
        NSDictionary *cfg = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([cfg isKindOfClass:NSDictionary.class] && [cfg[@"speed"] respondsToSelector:@selector(floatValue)])
            [D() setFloat:MAX(0.05f, [cfg[@"speed"] floatValue]) forKey:kSpeed];
        [NSFileManager.defaultManager removeItemAtPath:ConfigPath() error:nil];
    }
    if ([D() objectForKey:kSpeed]) return [D() floatForKey:kSpeed];
    NSNumber *baked = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GMSpeed"];
    return baked ? baked.floatValue : 1.0f;
}

static void ApplySpeed(void) {
    float s = gTimesUp ? MIN(ChosenSpeed(), 0.25f) : ChosenSpeed();
    for (UIWindow *w in AppWindows()) if (w.layer.speed != s) w.layer.speed = s;
}

#pragma mark - hide rules
//
// A rule = { cls, parent, ident?, label?, index? }. Matching prefers the accessibility identifier,
// then the accessibility label (what VoiceOver reads — "Reels", "Search and explore"…),
// then position among same-class siblings as a last resort.

static const void *kGMHiddenKey = &kGMHiddenKey;
static NSArray<NSDictionary *> *gRules;
static NSSet<NSString *> *gRuleClasses;

static void LoadRules(void) {
    gRules = [D() arrayForKey:kRules] ?: @[];
    NSMutableSet *cls = [NSMutableSet set];
    for (NSDictionary *r in gRules) if (r[@"cls"]) [cls addObject:r[@"cls"]];
    gRuleClasses = cls;
}

static NSUInteger SiblingIndex(UIView *v) {
    NSUInteger i = 0;
    for (UIView *s in v.superview.subviews) {
        if (s == v) return i;
        if (s.class == v.class) i++;
    }
    return NSNotFound;
}

static NSString *Label(UIView *v) {
    NSString *l = v.accessibilityLabel;
    if (l.length) return l;
    if ([v isKindOfClass:UIButton.class]) return [(UIButton *)v titleForState:UIControlStateNormal];
    if ([v isKindOfClass:UILabel.class]) return ((UILabel *)v).text;
    return nil;
}

static NSDictionary *RuleFor(UIView *v) {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"cls"] = NSStringFromClass(v.class);
    r[@"parent"] = NSStringFromClass(v.superview.class) ?: @"";
    if (v.accessibilityIdentifier.length) r[@"ident"] = v.accessibilityIdentifier;
    else if (Label(v).length) r[@"label"] = Label(v);
    else r[@"index"] = @(SiblingIndex(v));
    return r;
}

static NSString *Describe(NSDictionary *r) {
    NSString *what = r[@"ident"] ?: r[@"label"] ?: [NSString stringWithFormat:@"#%@", r[@"index"]];
    return [NSString stringWithFormat:@"%@  ·  %@", what, r[@"cls"]];
}

static BOOL Matches(UIView *v, NSDictionary *r) {
    if (![NSStringFromClass(v.class) isEqualToString:r[@"cls"]]) return NO;
    if (![NSStringFromClass(v.superview.class) isEqualToString:r[@"parent"]]) return NO;
    if (r[@"ident"]) return [v.accessibilityIdentifier isEqualToString:r[@"ident"]];
    if (r[@"label"]) return [Label(v) isEqualToString:r[@"label"]];
    return [r[@"index"] unsignedIntegerValue] == SiblingIndex(v);
}

static BOOL IsGMHidden(UIView *v) { return [objc_getAssociatedObject(v, kGMHiddenKey) boolValue]; }

static void SetGMHidden(UIView *v, BOOL hide) {
    if (IsGMHidden(v) == hide) { if (hide && !v.hidden) v.hidden = YES; return; }
    objc_setAssociatedObject(v, kGMHiddenKey, hide ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden = hide;
    v.userInteractionEnabled = !hide;
    [v.superview setNeedsLayout];
}

#pragma mark - tab-row collapse
//
// Hiding a tab in a custom tab bar would leave a hole. When the hidden view sits in a row of
// equal-sized siblings, we hook that container class's -layoutSubviews and re-spread the
// visible siblings across the full width after the app lays them out.

static NSMutableSet<NSString *> *gHookedRows;

static NSArray<UIView *> *RowSiblings(UIView *container, Class cls) {
    NSMutableArray *row = [NSMutableArray array];
    for (UIView *s in container.subviews) if (s.class == cls) [row addObject:s];
    if (row.count < 3) return nil;
    UIView *first = row.firstObject;
    for (UIView *s in row) {  // same height + same y = a row
        if (fabs(s.frame.size.height - first.frame.size.height) > 2 || fabs(s.frame.origin.y - first.frame.origin.y) > 2) return nil;
    }
    return [row sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
}

static void Respread(UIView *container) {
    if ([container isKindOfClass:UIStackView.class]) return;  // stack views collapse hidden views themselves
    NSMutableSet<Class> *hiddenClasses = [NSMutableSet set];
    for (UIView *s in container.subviews) if (IsGMHidden(s)) [hiddenClasses addObject:s.class];
    for (Class cls in hiddenClasses) {
        NSArray *row = RowSiblings(container, cls);
        if (!row) continue;
        NSArray *visible = [row filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView *s, id _) { return !IsGMHidden(s); }]];
        if (!visible.count) continue;
        CGFloat minX = CGRectGetMinX([row.firstObject frame]), maxX = CGRectGetMaxX([row.lastObject frame]);
        CGFloat w = (maxX - minX) / visible.count;
        [visible enumerateObjectsUsingBlock:^(UIView *s, NSUInteger i, BOOL *_) {
            CGRect f = s.frame;
            f.origin.x = minX + i * w;
            f.size.width = w;
            s.frame = f;
        }];
    }
}

static void HookRowContainer(UIView *container) {
    if (!container || [container isKindOfClass:UIStackView.class]) return;
    Class cls = container.class;
    if (cls == UIView.class || cls == UIWindow.class) return;  // never hook the base classes
    NSString *name = NSStringFromClass(cls);
    if ([gHookedRows containsObject:name]) return;
    [gHookedRows addObject:name];
    SEL sel = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(cls, sel);
    IMP orig = method_getImplementation(m);
    IMP repl = imp_implementationWithBlock(^(UIView *self_) {
        ((void (*)(id, SEL))orig)(self_, sel);
        if (self_.class == cls) Respread(self_);
    });
    // add on the class itself so we never patch an inherited implementation shared with other classes
    if (!class_addMethod(cls, sel, repl, method_getTypeEncoding(m))) method_setImplementation(m, repl);
    GMLog(@"collapsing tab row in %@", name);
}

#pragma mark - apply

static NSUInteger gHiddenCount;

static void Walk(UIView *v) {
    if (gRuleClasses.count && [gRuleClasses containsObject:NSStringFromClass(v.class)]) {
        BOOL hit = NO;
        for (NSDictionary *r in gRules) if (Matches(v, r)) { hit = YES; break; }
        if (hit) {
            gHiddenCount++;
            SetGMHidden(v, YES);
            if (RowSiblings(v.superview, v.class)) HookRowContainer(v.superview);
            return;
        }
    }
    if (IsGMHidden(v)) SetGMHidden(v, NO);  // rule was removed
    for (UIView *s in v.subviews) Walk(s);
}

static void ApplyRules(void) {
    gHiddenCount = 0;
    for (UIWindow *w in AppWindows()) Walk(w);
}

#pragma mark - time limit

static NSString *TodayKey(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    return [kUsagePrefix stringByAppendingString:[f stringFromDate:NSDate.date]];
}

static UIView *gGrayOverlay;
static UILabel *gTimesUpBanner;

static void UpdateTimesUp(void) {
    NSInteger limit = [D() integerForKey:kLimit];
    double used = [D() doubleForKey:TodayKey()];
    BOOL up = limit > 0 && used >= limit * 60;
    if (up == gTimesUp && (!up || gGrayOverlay.superview == KeyWindow())) return;
    gTimesUp = up;
    [gGrayOverlay removeFromSuperview];
    [gTimesUpBanner removeFromSuperview];
    if (up) {
        UIWindow *w = KeyWindow();
        if (!gGrayOverlay) {
            gGrayOverlay = [UIView new];
            gGrayOverlay.backgroundColor = UIColor.grayColor;
            gGrayOverlay.layer.compositingFilter = @"saturationBlendMode";  // desaturates everything under it
            gGrayOverlay.userInteractionEnabled = NO;
            gTimesUpBanner = [UILabel new];
            gTimesUpBanner.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
            gTimesUpBanner.textAlignment = NSTextAlignmentCenter;
            gTimesUpBanner.textColor = UIColor.blackColor;
            gTimesUpBanner.backgroundColor = [UIColor colorWithRed:0.66 green:1 blue:0.2 alpha:1];
            gTimesUpBanner.userInteractionEnabled = NO;
        }
        gGrayOverlay.frame = w.bounds;
        gGrayOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        gTimesUpBanner.text = [NSString stringWithFormat:@"GODMODE · %ld min limit hit · slow mode", (long)limit];
        gTimesUpBanner.frame = CGRectMake(0, w.safeAreaInsets.top, w.bounds.size.width, 22);
        [w addSubview:gGrayOverlay];
        [w addSubview:gTimesUpBanner];
    }
    ApplySpeed();
}

#pragma mark - element picker

@interface GMPicker : UIView
@property (nonatomic, weak) UIView *target;
@property (nonatomic, strong) UIView *box;
@property (nonatomic, strong) UILabel *info;
@end

@implementation GMPicker

static UIButton *GMButton(NSString *title, BOOL primary, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold];
    b.backgroundColor = primary ? [UIColor colorWithRed:0.66 green:1 blue:0.2 alpha:1] : [UIColor colorWithWhite:0.18 alpha:1];
    [b setTitleColor:primary ? UIColor.blackColor : UIColor.whiteColor forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (void)showIn:(UIWindow *)w {
    GMPicker *p = [[GMPicker alloc] initWithFrame:w.bounds];
    p.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    p.backgroundColor = [UIColor colorWithWhite:0 alpha:0.08];

    p.box = [UIView new];
    p.box.userInteractionEnabled = NO;
    p.box.layer.borderWidth = 2;
    p.box.layer.borderColor = [UIColor colorWithRed:0.66 green:1 blue:0.2 alpha:1].CGColor;
    p.box.backgroundColor = [UIColor colorWithRed:0.66 green:1 blue:0.2 alpha:0.18];
    p.box.hidden = YES;
    [p addSubview:p.box];

    UIView *bar = [UIView new];
    bar.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.96];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [p addSubview:bar];

    p.info = [UILabel new];
    p.info.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    p.info.textColor = UIColor.whiteColor;
    p.info.numberOfLines = 2;
    p.info.text = @"EDIT LAYOUT — tap anything to select it";

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        GMButton(@"bigger", NO, p, @selector(parent)),
        GMButton(@"smaller", NO, p, @selector(child)),
        GMButton(@"HIDE", YES, p, @selector(hide)),
        GMButton(@"done", NO, p, @selector(done)),
    ]];
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 6;

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[p.info, buttons]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 8;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:col];

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:p.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:p.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:p.safeAreaLayoutGuide.topAnchor],
        [col.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [col.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [col.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10],
        [col.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-10],
        [buttons.heightAnchor constraintEqualToConstant:40],
    ]];
    [p addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:p action:@selector(tapped:)]];
    [w addSubview:p];
}

// Deepest visible view under the point, ignoring userInteractionEnabled (labels/images count).
static UIView *Deepest(UIView *v, CGPoint p, UIView *skip) {
    if (v == skip || v.hidden || v.alpha < 0.02 || ![v pointInside:p withEvent:nil]) return nil;
    for (UIView *s in v.subviews.reverseObjectEnumerator) {
        UIView *hit = Deepest(s, [v convertPoint:p toView:s], skip);
        if (hit) return hit;
    }
    return v;
}

- (void)tapped:(UITapGestureRecognizer *)g {
    UIView *bar = self.info.superview.superview;
    if (CGRectContainsPoint(bar.frame, [g locationInView:self])) return;
    self.target = Deepest(self.window, [g locationInView:self.window], self);
    [self refresh];
}

- (void)parent {
    if (self.target.superview && self.target.superview != self.window) self.target = self.target.superview;
    [self refresh];
}

- (void)child {
    UIView *t = self.target;
    if (!t) return;
    CGPoint c = [self convertPoint:self.box.center toView:t];
    for (UIView *s in t.subviews.reverseObjectEnumerator)
        if (!s.hidden && [s pointInside:[t convertPoint:c toView:s] withEvent:nil]) { self.target = s; break; }
    [self refresh];
}

- (void)refresh {
    UIView *t = self.target;
    self.box.hidden = !t;
    if (!t) return;
    self.box.frame = [t convertRect:t.bounds toView:self];
    NSDictionary *r = RuleFor(t);
    self.info.text = [NSString stringWithFormat:@"%@\n%.0f×%.0f", Describe(r), t.bounds.size.width, t.bounds.size.height];
}

- (void)hide {
    UIView *t = self.target;
    if (!t) return;
    NSMutableArray *rules = [gRules mutableCopy];
    [rules addObject:RuleFor(t)];
    [D() setObject:rules forKey:kRules];
    LoadRules();
    ApplyRules();
    [t.superview layoutIfNeeded];
    GMLog(@"hide rule added: %@", Describe(RuleFor(t)));
    self.target = nil;
    [self refresh];
    self.info.text = [NSString stringWithFormat:@"hidden ✓  (%lu rules) — tap the next thing or hit done", (unsigned long)gRules.count];
}

- (void)done { [self removeFromSuperview]; }
@end

#pragma mark - fake GPS (standalone, per app, no computer)
//
// Swizzle CLLocationManager so *this app alone* reports a location you pick from the on-phone menu.
// Only works when the app already has location permission (we don't ask on its behalf). This is NOT
// system-wide — it changes what this one patched app sees, which is the most you can do no-jailbreak
// without the cable. Pick a city in the GODMODE menu → "Fake GPS".

// city name -> {lat, lon}; mirrors gmlib/gps.py PLACES
static NSDictionary<NSString *, NSArray<NSNumber *> *> *GPSPlaces(void) {
    return @{ @"San Francisco": @[@37.7749, @(-122.4194)], @"Los Angeles": @[@34.0522, @(-118.2437)],
              @"New York": @[@40.7128, @(-74.0060)], @"London": @[@51.5074, @(-0.1278)],
              @"Tokyo": @[@35.6762, @139.6503], @"Paris": @[@48.8566, @2.3522],
              @"Las Vegas": @[@36.1699, @(-115.1398)], @"Miami": @[@25.7617, @(-80.1918)] };
}

static BOOL GPSOn(void) { return [D() boolForKey:kGPSOn]; }

static CLLocation *FakeLocation(void) {
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake([D() doubleForKey:kGPSLat], [D() doubleForKey:kGPSLon]);
    return [[CLLocation alloc] initWithCoordinate:c altitude:12
                                horizontalAccuracy:5 verticalAccuracy:5
                                            course:0 speed:0 timestamp:NSDate.date];
}

static NSHashTable *gGPSManagers;  // weak set of managers that are "updating", so we keep feeding them

static void GMDeliver(CLLocationManager *mgr) {
    if (!GPSOn() || !mgr) return;
    id<CLLocationManagerDelegate> del = mgr.delegate;
    if ([del respondsToSelector:@selector(locationManager:didUpdateLocations:)])
        [del locationManager:mgr didUpdateLocations:@[FakeLocation()]];
}

static void FeedGPSManagers(void) {
    if (!GPSOn()) return;
    for (CLLocationManager *mgr in gGPSManagers.allObjects) GMDeliver(mgr);
}

static void InstallGPSHooks(void) {
    Class cls = CLLocationManager.class;
    gGPSManagers = [NSHashTable weakObjectsHashTable];

    // -location getter → hand back the fake coordinate
    Method loc = class_getInstanceMethod(cls, @selector(location));
    IMP locOrig = method_getImplementation(loc);
    method_setImplementation(loc, imp_implementationWithBlock(^CLLocation *(id self_) {
        if (GPSOn()) return FakeLocation();
        return ((CLLocation *(*)(id, SEL))locOrig)(self_, @selector(location));
    }));

    // -startUpdatingLocation → let the real thing run, then start feeding fakes
    Method start = class_getInstanceMethod(cls, @selector(startUpdatingLocation));
    IMP startOrig = method_getImplementation(start);
    method_setImplementation(start, imp_implementationWithBlock(^(id self_) {
        ((void (*)(id, SEL))startOrig)(self_, @selector(startUpdatingLocation));
        if (GPSOn()) {
            [gGPSManagers addObject:self_];
            CLLocationManager *mgr = self_;
            dispatch_async(dispatch_get_main_queue(), ^{ GMDeliver(mgr); });
        }
    }));

    // -stopUpdatingLocation → stop feeding this manager
    Method stop = class_getInstanceMethod(cls, @selector(stopUpdatingLocation));
    IMP stopOrig = method_getImplementation(stop);
    method_setImplementation(stop, imp_implementationWithBlock(^(id self_) {
        [gGPSManagers removeObject:self_];
        ((void (*)(id, SEL))stopOrig)(self_, @selector(stopUpdatingLocation));
    }));

    // -requestLocation (one-shot) → deliver a single fake fix
    Method req = class_getInstanceMethod(cls, @selector(requestLocation));
    if (req) {
        IMP reqOrig = method_getImplementation(req);
        method_setImplementation(req, imp_implementationWithBlock(^(id self_) {
            if (GPSOn()) { CLLocationManager *mgr = self_; dispatch_async(dispatch_get_main_queue(), ^{ GMDeliver(mgr); }); return; }
            ((void (*)(id, SEL))reqOrig)(self_, @selector(requestLocation));
        }));
    }
    GMLog(@"GPS hooks installed (spoof %@)", GPSOn() ? @"on" : @"off");
}

#pragma mark - menu

@interface GMMenu : NSObject <UIGestureRecognizerDelegate>
@end

@implementation GMMenu
+ (instancetype)shared { static GMMenu *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [self new]; }); return s; }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }

- (void)attachTo:(UIWindow *)w {
    for (UIGestureRecognizer *g in w.gestureRecognizers) if (g.delegate == self) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(open:)];
    hold.numberOfTouchesRequired = 2;
    hold.minimumPressDuration = 1.0;
    for (UIGestureRecognizer *g in @[tap, hold]) {
        g.cancelsTouchesInView = NO;
        g.delegate = self;
        [w addGestureRecognizer:g];
    }
}

- (void)open:(UIGestureRecognizer *)g {
    if (g && g.state != UIGestureRecognizerStateRecognized && g.state != UIGestureRecognizerStateBegan) return;
    UIViewController *top = TopVC();
    if ([top isKindOfClass:UIAlertController.class]) return;
    NSInteger limit = [D() integerForKey:kLimit];
    double used = [D() doubleForKey:TodayKey()] / 60;
    NSString *msg = [NSString stringWithFormat:@"speed %.2gx · %lu hidden · %.0f min today%@",
                     ChosenSpeed(), (unsigned long)gRules.count, used,
                     limit ? [NSString stringWithFormat:@" / %ld", (long)limit] : @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GODMODE" message:msg
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"✂︎  Edit layout (tap to hide)" style:UIAlertActionStyleDefault handler:^(id _) {
        [GMPicker showIn:KeyWindow()];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"↺  Hidden items (%lu)", (unsigned long)gRules.count]
                                          style:UIAlertActionStyleDefault handler:^(id _) { [self rules]; }]];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⏱  UI speed  ·  %.2gx", ChosenSpeed()]
                                          style:UIAlertActionStyleDefault handler:^(id _) { [self speed]; }]];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⏳  Daily limit  ·  %@", limit ? [NSString stringWithFormat:@"%ld min", (long)limit] : @"off"]
                                          style:UIAlertActionStyleDefault handler:^(id _) { [self limit]; }]];
    NSString *gpsName = GPSOn() ? ([D() stringForKey:kGPSName] ?: @"on") : @"off";
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📍  Fake GPS  ·  %@", gpsName]
                                          style:UIAlertActionStyleDefault handler:^(id _) { [self gps]; }]];
    // FLEX ships as a framework inside the patched app; load it lazily so GodModeKit needn't link it.
    if (NSClassFromString(@"FLEXManager")) {
        [a addAction:[UIAlertAction actionWithTitle:@"🔎  Inspector (FLEX)" style:UIAlertActionStyleDefault handler:^(id _) {
            [GMMenu showFLEX];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

+ (void)showFLEX {
    Class flex = NSClassFromString(@"FLEXManager");
    if (!flex) return;
    id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id mgr = msg(flex, @selector(sharedManager));
    if (mgr) msg(mgr, @selector(showExplorer));
}

- (void)present:(UIAlertController *)a {
    UIViewController *top = TopVC();
    a.popoverPresentationController.sourceView = top.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
    [top presentViewController:a animated:YES completion:nil];
}

- (void)speed {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"UI speed" message:@"applies instantly, saved for this app"
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in @[@0.25, @0.5, @0.75, @1, @1.5, @2, @3, @5]) {
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@x%@", n, n.floatValue == ChosenSpeed() ? @"  ✓" : @""]
                                              style:UIAlertActionStyleDefault handler:^(id _) {
            [D() setFloat:n.floatValue forKey:kSpeed];
            ApplySpeed();
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

- (void)limit {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Daily limit"
        message:@"when you hit it, this app goes grayscale + slow motion until midnight"
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *n in @[@0, @5, @10, @15, @30, @60]) {
        [a addAction:[UIAlertAction actionWithTitle:n.integerValue ? [NSString stringWithFormat:@"%@ min", n] : @"off"
                                              style:UIAlertActionStyleDefault handler:^(id _) {
            [D() setInteger:n.integerValue forKey:kLimit];
            UpdateTimesUp();
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

- (void)gps {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Fake GPS"
        message:@"this app alone will report the picked location (it needs location permission already). Not system-wide."
        preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *places = GPSPlaces();
    NSString *current = [D() stringForKey:kGPSName];
    for (NSString *name in [places.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        BOOL on = GPSOn() && [current isEqualToString:name];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%@", name, on ? @"  ✓" : @""]
                                              style:UIAlertActionStyleDefault handler:^(id _) {
            NSArray<NSNumber *> *ll = places[name];
            [D() setDouble:ll[0].doubleValue forKey:kGPSLat];
            [D() setDouble:ll[1].doubleValue forKey:kGPSLon];
            [D() setObject:name forKey:kGPSName];
            [D() setBool:YES forKey:kGPSOn];
            FeedGPSManagers();
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:GPSOn() ? @"turn OFF (use real location)" : @"off"
                                          style:UIAlertActionStyleDestructive handler:^(id _) {
        [D() setBool:NO forKey:kGPSOn];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}

- (void)rules {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Hidden items" message:@"tap one to bring it back"
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [gRules enumerateObjectsUsingBlock:^(NSDictionary *r, NSUInteger i, BOOL *_) {
        [a addAction:[UIAlertAction actionWithTitle:Describe(r) style:UIAlertActionStyleDefault handler:^(id _) {
            NSMutableArray *rules = [gRules mutableCopy];
            [rules removeObjectAtIndex:i];
            [D() setObject:rules forKey:kRules];
            LoadRules();
            ApplyRules();
        }]];
    }];
    if (gRules.count) {
        [a addAction:[UIAlertAction actionWithTitle:@"Unhide everything" style:UIAlertActionStyleDestructive handler:^(id _) {
            [D() removeObjectForKey:kRules];
            LoadRules();
            ApplyRules();
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}
@end

#pragma mark - sideload fixes
//
// Re-signed apps lose their App Group entitlement, so -containerURLForSecurityApplicationGroupIdentifier:
// returns nil and apps like Reddit crash on launch. Hand them a private folder inside their own sandbox.

static void FixAppGroups(void) {
    Method m = class_getInstanceMethod(NSFileManager.class, @selector(containerURLForSecurityApplicationGroupIdentifier:));
    if (!m) return;
    IMP orig = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^NSURL *(NSFileManager *fm, NSString *group) {
        NSURL *url = ((NSURL *(*)(id, SEL, NSString *))orig)(fm, @selector(containerURLForSecurityApplicationGroupIdentifier:), group);
        if (url || !group.length) return url;
        NSURL *lib = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
        url = [[lib URLByAppendingPathComponent:@"GMAppGroups"] URLByAppendingPathComponent:group isDirectory:YES];
        [fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
        return url;
    }));
}

#pragma mark - boot

// Recipe defaults (mods/<app>.json "defaults") arrive as Info.plist GMDefaults. Seeded only where
// the key has never been set, so anything you change on the phone wins.
static void SeedDefaults(void) {
    NSDictionary *seed = [NSBundle.mainBundle objectForInfoDictionaryKey:@"GMDefaults"];
    if (![seed isKindOfClass:NSDictionary.class]) return;
    [seed enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *_) {
        if (![D() objectForKey:k]) [D() setObject:v forKey:k];
    }];
}

__attribute__((constructor)) static void GMInit(void) {
    FixAppGroups();
    SeedDefaults();
    InstallGPSHooks();
    gHookedRows = [NSMutableSet set];
    LoadRules();
    // Load the bundled FLEX inspector if it shipped with the app, so its menu item lights up.
    if (!NSClassFromString(@"FLEXManager")) {
        dlopen([[[NSBundle.mainBundle.privateFrameworksURL
                  URLByAppendingPathComponent:@"FLEX.framework/FLEX"] path] fileSystemRepresentation], RTLD_NOW);
    }
    GMLog(@"GodModeKit loaded (speed %.2fx, %lu hide rules, FLEX %@)",
          ChosenSpeed(), (unsigned long)gRules.count, NSClassFromString(@"FLEXManager") ? @"yes" : @"no");

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    void (^refresh)(NSNotification *) = ^(NSNotification *n) {
        if ([n.object isKindOfClass:UIWindow.class]) [GMMenu.shared attachTo:n.object];
        ApplySpeed();
        ApplyRules();
        UpdateTimesUp();
    };
    [nc addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
    NSString *debug = NSProcessInfo.processInfo.environment[@"GM_DEBUG"];  // simulator test hook: picker | menu
    if (debug) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([debug isEqualToString:@"menu"]) [GMMenu.shared open:nil];
        else [GMPicker showIn:KeyWindow()];
    });

    // Rules re-apply 4x a second so views the app rebuilds (new screens, reloaded tab bars) stay hidden.
    __block CFTimeInterval last = CACurrentMediaTime();
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *_) {
        CFTimeInterval now = CACurrentMediaTime();
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            [D() setDouble:[D() doubleForKey:TodayKey()] + (now - last) forKey:TodayKey()];
            ApplyRules();
            static int n = 0;
            if (++n % 4 == 0) { ApplySpeed(); UpdateTimesUp(); FeedGPSManagers(); }
        }
        last = now;
    }];
}
