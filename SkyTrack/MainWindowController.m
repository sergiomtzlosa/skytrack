#import "MainWindowController.h"
#import "PlanetModel.h"
#import <MapKit/MapKit.h>

static NSString * const kDefaultLocationName = @"New York, NY, United States";
static NSString * const kCurrentLocationName = @"Current Location";
static const double kDefaultLatitude = 40.7128;
static const double kDefaultLongitude = -74.0060;

#pragma mark - Color and drawing helpers

static NSColor *SKColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

static NSImage *SKImage(CGSize size, void (^draw)(CGContextRef ctx, CGSize size)) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:(NSInteger)size.width
                                                                     pixelsHigh:(NSInteger)size.height
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSDeviceRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphics];
    draw(graphics.CGContext, size);
    [NSGraphicsContext restoreGraphicsState];

    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image addRepresentation:rep];
    return image;
}

static void SKFillVerticalGradient(CGContextRef ctx, CGRect rect, NSColor *bottomColor, NSColor *topColor) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(__bridge id)bottomColor.CGColor, (__bridge id)topColor.CGColor];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

static void SKDrawRadialGlow(CGContextRef ctx, CGPoint center, CGFloat radius, NSColor *color, CGFloat strength) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (__bridge id)[color colorWithAlphaComponent:strength].CGColor,
        (__bridge id)[color colorWithAlphaComponent:0.0].CGColor
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawRadialGradient(ctx, gradient, center, 0, center, radius, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

static NSColor *SKBlend(NSColor *a, NSColor *b, double t) {
    t = MAX(0.0, MIN(1.0, t));
    return [a blendedColorWithFraction:t ofColor:b];
}

/// Deterministic pseudo-random generator so textures look the same on every launch.
static uint32_t SKRandomState = 0x9E3779B9u;

static void SKSeedRandom(uint32_t seed) {
    SKRandomState = seed ? seed : 0x9E3779B9u;
}

static double SKRandom(void) {
    SKRandomState = SKRandomState * 1664525u + 1013904223u;
    return (double)(SKRandomState >> 8) / 16777216.0;
}

static double SKRandomRange(double min, double max) {
    return min + (max - min) * SKRandom();
}

/// Paints horizontal latitude bands between the colors in the palette.
static void SKDrawBands(CGContextRef ctx, CGSize size, NSArray<NSColor *> *palette,
                        double frequency, double wobble) {
    CGFloat width = size.width;
    CGFloat height = size.height;
    NSUInteger count = palette.count;
    if (count < 2) {
        return;
    }

    for (NSInteger y = 0; y < (NSInteger)height; y++) {
        double t = (double)y / height;
        double wave = 0.5 + 0.5 * sin(t * M_PI * 2.0 * frequency + sin(t * 9.0) * wobble);
        wave = pow(wave, 1.15);
        double pos = wave * (double)(count - 1);
        NSUInteger low = MIN((NSUInteger)floor(pos), count - 1);
        NSUInteger high = MIN(low + 1, count - 1);
        NSColor *color = SKBlend(palette[low], palette[high], pos - floor(pos));
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillRect(ctx, CGRectMake(0, y, width, 1));
    }
}

/// Thin horizontal wisps used to break up banded atmospheres.
static void SKDrawStreaks(CGContextRef ctx, CGSize size, NSInteger count,
                          CGFloat alpha, BOOL light) {
    CGFloat width = size.width;
    CGFloat height = size.height;
    for (NSInteger i = 0; i < count; i++) {
        CGFloat x = SKRandomRange(-40, width);
        CGFloat y = SKRandomRange(0, height);
        CGFloat w = SKRandomRange(40, 220);
        CGFloat h = SKRandomRange(1.0, 4.5);
        CGFloat localAlpha = alpha * SKRandomRange(0.35, 1.0);
        NSColor *color = light ? [NSColor colorWithWhite:1.0 alpha:localAlpha]
                               : [NSColor colorWithWhite:0.0 alpha:localAlpha];
        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(x, y, w, h));
    }
}

#pragma mark - Suggestion panel

@interface SKSuggestionPanelView : NSView
@end

@implementation SKSuggestionPanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.shadowColor = [NSColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.28;
        self.layer.shadowRadius = 10.0;
        self.layer.shadowOffset = CGSizeMake(0, -3);
    }
    return self;
}

- (void)layout {
    [super layout];
    CGPathRef shadowPath = CGPathCreateWithRoundedRect(self.bounds, 8.0, 8.0, NULL);
    self.layer.shadowPath = shadowPath;
    CGPathRelease(shadowPath);
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8 yRadius:8];

    [[NSColor windowBackgroundColor] setFill];
    [path fill];

    [[[NSColor separatorColor] colorWithAlphaComponent:0.7] setStroke];
    path.lineWidth = 1.0;
    [path stroke];
}

@end

#pragma mark - Suggestion cell

@interface SKSuggestionCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@end

@implementation SKSuggestionCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        NSTextField *title = [NSTextField labelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
        title.textColor = [NSColor labelColor];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:title];
        self.titleLabel = title;
        self.textField = title;

        NSTextField *subtitle = [NSTextField labelWithString:@""];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.font = [NSFont systemFontOfSize:10.5];
        subtitle.textColor = [NSColor secondaryLabelColor];
        subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:subtitle];
        self.subtitleLabel = subtitle;

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],

            [subtitle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [subtitle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],
        ]];
    }
    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];

    BOOL emphasized = (backgroundStyle == NSBackgroundStyleEmphasized);
    self.titleLabel.textColor = emphasized ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
    self.subtitleLabel.textColor = emphasized
        ? [[NSColor alternateSelectedControlTextColor] colorWithAlphaComponent:0.78]
        : [NSColor secondaryLabelColor];
}

@end

#pragma mark - Planet row and cell

@interface SKPlanetRowView : NSTableRowView
@end

@implementation SKPlanetRowView

- (NSBackgroundStyle)interiorBackgroundStyle {
    return NSBackgroundStyleNormal;
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSRect pillRect = NSInsetRect(self.bounds, 8.0, 4.0);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:6.0 yRadius:6.0];
    [[[NSColor controlAccentColor] colorWithAlphaComponent:0.20] setFill];
    [path fill];
}

@end

@interface SKPlanetCellView : NSTableCellView
@property (nonatomic, strong) NSTextField *planetLabel;
@end

@implementation SKPlanetCellView

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];
    self.planetLabel.textColor = [NSColor labelColor];
}

@end

#pragma mark - Planet scene view

@interface SKPlanetSceneView : SCNView
@end

@implementation SKPlanetSceneView

// Orbit is still provided by SceneKit's camera control; zoom gestures are ignored.
- (void)scrollWheel:(NSEvent *)event {
}

- (void)magnifyWithEvent:(NSEvent *)event {
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
}

@end

@interface MainWindowController () <NSTextFieldDelegate, MKLocalSearchCompleterDelegate, NSWindowDelegate> {
    NSMutableDictionary<NSString *, NSImage *> *_textureCache;
    NSMutableDictionary<NSString *, NSDictionary *> *_geocodeCache;
    NSMutableSet<NSString *> *_reverseGeocodeAttempts;
    NSImage *_ringImage;
    NSImage *_starfieldImage;
}
@property (nonatomic, strong) NSArray<PlanetModel *> *planets;
@property (nonatomic, strong) CLGeocoder *geocoder;
@property (nonatomic, strong) CLGeocoder *reverseGeocoder;
@property (nonatomic, strong) NSProgressIndicator *searchSpinner;
@property (nonatomic) NSUInteger geocodeRequestToken;

@property (nonatomic, strong) MKLocalSearchCompleter *searchCompleter;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *suggestions;
@property (nonatomic, strong) NSView *suggestionsContainer;
@property (nonatomic, strong) NSTableView *suggestionsTable;
@property (nonatomic, strong) NSLayoutConstraint *suggestionsHeightConstraint;
@property (nonatomic) BOOL suggestionsDismissed;
@property (nonatomic) BOOL updatingLocationFieldProgrammatically;

@property (nonatomic, strong) NSView *sidebarView;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic, strong) NSButton *sidebarToggleButton;

@property (nonatomic, strong) NSWindow *planetPopoutWindow;
@property (nonatomic, strong) SKPlanetSceneView *planetPopoutView;

- (void)geocodeQuery:(NSString *)query;
- (void)reverseGeocodeLocation:(CLLocation *)location coordinateText:(NSString *)coordinateText;
- (void)cacheLocation:(CLLocation *)location name:(NSString *)name forQuery:(NSString *)query;
- (NSString *)displayNameForPlacemark:(CLPlacemark *)placemark fallback:(NSString *)fallback;
- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message;
- (void)buildSuggestionViewsInContentView:(NSView *)content locationField:(NSTextField *)locationField;
- (void)updateSuggestionsVisibility;
- (void)hideSuggestions;
- (void)acceptSuggestionAtIndex:(NSInteger)index;
- (void)setLocationFieldText:(NSString *)text;
- (NSImage *)bundledTextureNamed:(NSString *)name extension:(NSString *)extension;
- (SCNScene *)sceneForPlanet:(PlanetModel *)planet pointOfView:(SCNNode **)outCameraNode;
- (IBAction)popOutPlanetView:(id)sender;
- (void)configurePopoutForPlanet:(PlanetModel *)planet;
- (IBAction)toggleSidebar:(id)sender;
@end

@implementation MainWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1380, 800);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SkyTrack";
    window.minSize = NSMakeSize(1100, 620);
    window.restorable = NO;
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _planets = [PlanetModel planetData];
        _textureCache = [NSMutableDictionary dictionary];
        _geocodeCache = [NSMutableDictionary dictionary];
        _reverseGeocodeAttempts = [NSMutableSet set];
        _geocoder = [[CLGeocoder alloc] init];

        _searchCompleter = [[MKLocalSearchCompleter alloc] init];
        _searchCompleter.delegate = self;
        _searchCompleter.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypePointOfInterest;

        CLLocation *defaultLocation = [[CLLocation alloc] initWithLatitude:kDefaultLatitude
                                                                longitude:kDefaultLongitude];
        [self cacheLocation:defaultLocation name:kDefaultLocationName forQuery:kDefaultLocationName];
        [self buildInterface];
        [self configureLocationServices];
        [self updateSky:nil];
    }
    return self;
}

- (void)dealloc {
    [self.locationManager stopUpdatingLocation];
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"planetPicked"];
}

#pragma mark - Interface

- (void)buildInterface {
    NSView *content = self.window.contentView;

    // Sidebar: planet list plus a details panel.
    NSTableView *table = [[NSTableView alloc] init];
    table.headerView = nil;
    table.rowHeight = 34;
    table.usesAlternatingRowBackgroundColors = NO;
    table.backgroundColor = [NSColor clearColor];
    table.allowsEmptySelection = NO;
    table.dataSource = self;
    table.delegate = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"planet"];
    column.width = 220;
    [table addTableColumn:column];
    self.planetTableView = table;

    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    scrollView.documentView = table;

    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] init];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.material = NSVisualEffectMaterialSidebar;
    sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    [sidebar addSubview:scrollView];
    self.sidebarView = sidebar;

    // Web view with a script bridge so clicks on the chart reach the app.
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *contentController = [[WKUserContentController alloc] init];
    [contentController addScriptMessageHandler:self name:@"planetPicked"];
    configuration.userContentController = contentController;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.allowsBackForwardNavigationGestures = NO;
    self.webView = webView;

    // 3D inspector on the right.
    NSVisualEffectView *inspector = [self buildInspectorView];
    inspector.translatesAutoresizingMaskIntoConstraints = NO;

    // Control bar.
    NSTextField *locationField = [[NSTextField alloc] init];
    locationField.translatesAutoresizingMaskIntoConstraints = NO;
    locationField.placeholderString = @"City, address, or coordinates";
    locationField.stringValue = kDefaultLocationName;
    locationField.target = self;
    locationField.action = @selector(updateSky:);
    locationField.toolTip = @"Type a city or address and press Return to search, or enter coordinates as latitude, longitude (for example 40.7128, -74.0060)";
    locationField.delegate = self;
    self.locationTextField = locationField;

    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.controlSize = NSControlSizeSmall;
    spinner.displayedWhenStopped = NO;
    self.searchSpinner = spinner;

    NSDatePicker *datePicker = [[NSDatePicker alloc] init];
    datePicker.translatesAutoresizingMaskIntoConstraints = NO;
    datePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    datePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    datePicker.dateValue = [NSDate date];
    datePicker.target = self;
    datePicker.action = @selector(updateSky:);
    self.datePicker = datePicker;

    NSButton *todayButton = [NSButton buttonWithTitle:@"Today" target:self action:@selector(jumpToToday:)];
    todayButton.translatesAutoresizingMaskIntoConstraints = NO;
    todayButton.bezelStyle = NSBezelStyleRounded;

    NSButton *locateButton = [NSButton buttonWithTitle:@"Use My Location" target:self action:@selector(selectLocation:)];
    locateButton.translatesAutoresizingMaskIntoConstraints = NO;
    locateButton.bezelStyle = NSBezelStyleRounded;

    NSButton *sidebarToggle = [NSButton buttonWithTitle:@"Planets" target:self action:@selector(toggleSidebar:)];
    sidebarToggle.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarToggle.bezelStyle = NSBezelStyleRounded;
    sidebarToggle.buttonType = NSButtonTypeToggle;
    sidebarToggle.state = NSControlStateValueOn;
    sidebarToggle.toolTip = @"Hide the planet list";
    if (@available(macOS 11.0, *)) {
        NSImage *sidebarIcon = [NSImage imageWithSystemSymbolName:@"sidebar.left" accessibilityDescription:@"Planet list"];
        if (sidebarIcon) {
            sidebarToggle.image = sidebarIcon;
            sidebarToggle.imagePosition = NSImageLeading;
        }
    }
    self.sidebarToggleButton = sidebarToggle;

    [content addSubview:sidebar];
    [content addSubview:webView];
    [content addSubview:inspector];
    [content addSubview:locationField];
    [content addSubview:spinner];
    [content addSubview:datePicker];
    [content addSubview:todayButton];
    [content addSubview:locateButton];
    [content addSubview:sidebarToggle];

    [self buildSuggestionViewsInContentView:content locationField:locationField];

    NSLayoutConstraint *sidebarWidthConstraint = [sidebar.widthAnchor constraintEqualToConstant:260];
    self.sidebarWidthConstraint = sidebarWidthConstraint;

    [NSLayoutConstraint activateConstraints:@[
        // Sidebar
        [sidebar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:content.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        sidebarWidthConstraint,

        [scrollView.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor],

        // Web view
        [webView.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:inspector.leadingAnchor],
        [webView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:locationField.topAnchor constant:-16],

        // Inspector
        [inspector.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [inspector.topAnchor constraintEqualToAnchor:content.topAnchor],
        [inspector.bottomAnchor constraintEqualToAnchor:locationField.topAnchor constant:-16],
        [inspector.widthAnchor constraintEqualToConstant:300],

        // Control bar
        [sidebarToggle.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:16],
        [sidebarToggle.centerYAnchor constraintEqualToAnchor:locationField.centerYAnchor],

        [locationField.leadingAnchor constraintEqualToAnchor:sidebarToggle.trailingAnchor constant:12],
        [locationField.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [locationField.widthAnchor constraintGreaterThanOrEqualToConstant:180],

        [spinner.leadingAnchor constraintEqualToAnchor:locationField.trailingAnchor constant:6],
        [spinner.centerYAnchor constraintEqualToAnchor:locationField.centerYAnchor],
        [spinner.widthAnchor constraintEqualToConstant:16],
        [spinner.heightAnchor constraintEqualToConstant:16],

        [locateButton.leadingAnchor constraintEqualToAnchor:spinner.trailingAnchor constant:6],
        [locateButton.centerYAnchor constraintEqualToAnchor:locationField.centerYAnchor],

        [datePicker.leadingAnchor constraintEqualToAnchor:locateButton.trailingAnchor constant:20],
        [datePicker.centerYAnchor constraintEqualToAnchor:locationField.centerYAnchor],
        [datePicker.widthAnchor constraintGreaterThanOrEqualToConstant:190],

        [todayButton.leadingAnchor constraintEqualToAnchor:datePicker.trailingAnchor constant:6],
        [todayButton.centerYAnchor constraintEqualToAnchor:locationField.centerYAnchor],
        [todayButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
    ]];

    if (self.planets.count > 0) {
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self showPlanet:self.planets[0]];
    }
}

- (NSVisualEffectView *)buildInspectorView {
    NSVisualEffectView *inspector = [[NSVisualEffectView alloc] init];
    inspector.material = NSVisualEffectMaterialSidebar;
    inspector.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    inspector.state = NSVisualEffectStateActive;

    NSBox *edge = [[NSBox alloc] init];
    edge.translatesAutoresizingMaskIntoConstraints = NO;
    edge.boxType = NSBoxSeparator;

    NSMutableAttributedString *headingText = [[NSMutableAttributedString alloc] initWithString:@"3D PLANET VIEW" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
        NSKernAttributeName: @(1.4)
    }];
    NSTextField *heading = [NSTextField labelWithString:@""];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.attributedStringValue = headingText;

    NSButton *popoutButton = [NSButton buttonWithTitle:@"Pop Out"
                                                target:self
                                                action:@selector(popOutPlanetView:)];
    popoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    popoutButton.bezelStyle = NSBezelStyleRounded;
    popoutButton.controlSize = NSControlSizeSmall;
    popoutButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    popoutButton.toolTip = @"Open this 3D view in a separate window";

    SCNView *sceneView = [[SKPlanetSceneView alloc] initWithFrame:NSZeroRect];
    sceneView.translatesAutoresizingMaskIntoConstraints = NO;
    sceneView.backgroundColor = [NSColor blackColor];
    sceneView.allowsCameraControl = YES;
    sceneView.toolTip = @"Drag to orbit the planet";
    sceneView.autoenablesDefaultLighting = NO;
    sceneView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    sceneView.preferredFramesPerSecond = 30;
    sceneView.playing = YES;
    sceneView.wantsLayer = YES;
    sceneView.layer.cornerRadius = 12;
    sceneView.layer.masksToBounds = YES;
    self.planetSceneView = sceneView;

    NSBox *infoSeparator = [[NSBox alloc] init];
    infoSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    infoSeparator.boxType = NSBoxSeparator;

    NSMutableAttributedString *infoHeadingText = [[NSMutableAttributedString alloc] initWithString:@"PLANET INFO" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor],
        NSKernAttributeName: @(1.4)
    }];
    NSTextField *infoHeading = [NSTextField labelWithString:@""];
    infoHeading.translatesAutoresizingMaskIntoConstraints = NO;
    infoHeading.attributedStringValue = infoHeadingText;

    NSTextField *nameLabel = [NSTextField labelWithString:@""];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    nameLabel.textColor = [NSColor labelColor];
    self.planetNameLabel = nameLabel;

    NSTextField *metaLabel = [NSTextField labelWithString:@""];
    metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    metaLabel.font = [NSFont systemFontOfSize:11];
    metaLabel.textColor = [NSColor secondaryLabelColor];
    metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.planetMetaLabel = metaLabel;

    self.diameterValueLabel = [self factValueLabel];
    self.dayValueLabel = [self factValueLabel];
    self.yearValueLabel = [self factValueLabel];
    self.moonsValueLabel = [self factValueLabel];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self factNameLabelWithString:@"DIAMETER"], self.diameterValueLabel],
        @[[self factNameLabelWithString:@"DAY"], self.dayValueLabel],
        @[[self factNameLabelWithString:@"YEAR"], self.yearValueLabel],
        @[[self factNameLabelWithString:@"MOONS"], self.moonsValueLabel]
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 6;
    grid.columnSpacing = 14;
    grid.xPlacement = NSGridCellPlacementLeading;
    grid.yPlacement = NSGridCellPlacementCenter;

    NSTextField *descriptionLabel = [NSTextField wrappingLabelWithString:@""];
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descriptionLabel.font = [NSFont systemFontOfSize:11];
    descriptionLabel.textColor = [NSColor secondaryLabelColor];
    descriptionLabel.selectable = YES;
    self.planetDescriptionLabel = descriptionLabel;

    [inspector addSubview:edge];
    [inspector addSubview:heading];
    [inspector addSubview:popoutButton];
    [inspector addSubview:sceneView];
    [inspector addSubview:infoSeparator];
    [inspector addSubview:infoHeading];
    [inspector addSubview:nameLabel];
    [inspector addSubview:metaLabel];
    [inspector addSubview:grid];
    [inspector addSubview:descriptionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [edge.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor],
        [edge.topAnchor constraintEqualToAnchor:inspector.topAnchor],
        [edge.bottomAnchor constraintEqualToAnchor:inspector.bottomAnchor],
        [edge.widthAnchor constraintEqualToConstant:1],

        [heading.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [heading.topAnchor constraintEqualToAnchor:inspector.topAnchor constant:16],

        [popoutButton.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-12],
        [popoutButton.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
        [popoutButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:heading.trailingAnchor constant:8],

        [sceneView.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:12],
        [sceneView.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-12],
        [sceneView.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:10],
        [sceneView.heightAnchor constraintEqualToAnchor:sceneView.widthAnchor],

        [infoSeparator.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [infoSeparator.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-16],
        [infoSeparator.topAnchor constraintEqualToAnchor:sceneView.bottomAnchor constant:16],

        [infoHeading.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [infoHeading.topAnchor constraintEqualToAnchor:infoSeparator.bottomAnchor constant:10],

        [nameLabel.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [nameLabel.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-16],
        [nameLabel.topAnchor constraintEqualToAnchor:infoHeading.bottomAnchor constant:6],

        [metaLabel.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [metaLabel.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-16],
        [metaLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],

        [grid.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:inspector.trailingAnchor constant:-16],
        [grid.topAnchor constraintEqualToAnchor:metaLabel.bottomAnchor constant:14],

        [descriptionLabel.leadingAnchor constraintEqualToAnchor:inspector.leadingAnchor constant:16],
        [descriptionLabel.trailingAnchor constraintEqualToAnchor:inspector.trailingAnchor constant:-16],
        [descriptionLabel.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:14],
        [descriptionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:inspector.bottomAnchor constant:-14],
    ]];

    return inspector;
}

- (NSTextField *)factNameLabelWithString:(NSString *)string {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold];
    label.textColor = [NSColor tertiaryLabelColor];
    return label;
}

- (NSTextField *)factValueLabel {
    NSTextField *label = [NSTextField labelWithString:@"—"];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)buildSuggestionViewsInContentView:(NSView *)content locationField:(NSTextField *)locationField {
    SKSuggestionPanelView *container = [[SKSuggestionPanelView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.hidden = YES;
    self.suggestionsContainer = container;

    NSTableView *table = [[NSTableView alloc] init];
    table.headerView = nil;
    table.rowHeight = 42.0;
    table.intercellSpacing = NSMakeSize(0, 0);
    table.backgroundColor = [NSColor clearColor];
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsEmptySelection = YES;
    table.refusesFirstResponder = YES;
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.action = @selector(suggestionSelected:);
    self.suggestionsTable = table;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"suggestion"];
    column.width = 280;
    column.minWidth = 200;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [table addTableColumn:column];
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    scrollView.documentView = table;

    [container addSubview:scrollView];
    [content addSubview:container];

    NSLayoutConstraint *heightConstraint = [container.heightAnchor constraintEqualToConstant:0];
    self.suggestionsHeightConstraint = heightConstraint;

    NSLayoutConstraint *widthConstraint = [container.widthAnchor constraintEqualToAnchor:locationField.widthAnchor];
    widthConstraint.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [container.leadingAnchor constraintEqualToAnchor:locationField.leadingAnchor],
        [container.bottomAnchor constraintEqualToAnchor:locationField.topAnchor constant:-6],
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:280],
        widthConstraint,
        heightConstraint,

        [scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
        [scrollView.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
    ]];
}

#pragma mark - Actions

- (IBAction)toggleSidebar:(id)sender {
    BOOL show = self.sidebarView.hidden;
    self.sidebarView.hidden = !show;
    self.sidebarWidthConstraint.constant = show ? 260.0 : 0.0;
    self.sidebarToggleButton.state = show ? NSControlStateValueOn : NSControlStateValueOff;
    self.sidebarToggleButton.toolTip = show ? @"Hide the planet list" : @"Show the planet list";
}

- (IBAction)updateSky:(id)sender {
    NSDate *date = self.datePicker.dateValue ?: [NSDate date];
    NSString *query = [self.locationTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    CLLocationCoordinate2D coordinate;
    if ([self coordinateFromString:query coordinate:&coordinate]) {
        [self loadSkyMapWithCoordinate:coordinate locationName:query date:date];

        // Replace raw coordinates with a readable place name when possible.
        if (![_reverseGeocodeAttempts containsObject:query]) {
            [_reverseGeocodeAttempts addObject:query];
            CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude
                                                              longitude:coordinate.longitude];
            [self reverseGeocodeLocation:location coordinateText:query];
        }
        return;
    }

    if (query.length == 0) {
        // Nothing typed: fall back to the current location, then a named default city.
        CLLocation *current = self.locationManager.location;
        if (current) {
            [self setLocationFieldText:kCurrentLocationName];
            [self cacheLocation:current name:kCurrentLocationName forQuery:kCurrentLocationName];
            [self loadSkyMapWithCoordinate:current.coordinate locationName:kCurrentLocationName date:date];
            [self reverseGeocodeLocation:current coordinateText:kCurrentLocationName];
        } else {
            CLLocation *fallback = [[CLLocation alloc] initWithLatitude:kDefaultLatitude
                                                              longitude:kDefaultLongitude];
            [self setLocationFieldText:kDefaultLocationName];
            [self cacheLocation:fallback name:kDefaultLocationName forQuery:kDefaultLocationName];
            [self loadSkyMapWithCoordinate:fallback.coordinate locationName:kDefaultLocationName date:date];
        }
        return;
    }

    // Reuse a place that was already resolved (for example when the date changes).
    NSDictionary *cached = _geocodeCache[query.lowercaseString];
    if (cached) {
        CLLocation *location = cached[@"location"];
        NSString *cachedName = cached[@"name"] ?: query;
        [self loadSkyMapWithCoordinate:location.coordinate locationName:cachedName date:date];
        return;
    }

    [self geocodeQuery:query];
}

- (IBAction)selectLocation:(id)sender {
    if (![CLLocationManager locationServicesEnabled]) {
        [self presentLocationError:@"Location services are disabled. Enter a city or coordinates manually."];
        return;
    }

    switch (self.locationManager.authorizationStatus) {
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            [self presentLocationError:@"Location access is not allowed. Enter a city or coordinates manually, or enable it in System Settings."];
            return;
        case kCLAuthorizationStatusNotDetermined:
            [self.locationManager requestWhenInUseAuthorization];
            return;
        default:
            break;
    }

    [self.locationManager startUpdatingLocation];
}

- (IBAction)jumpToToday:(id)sender {
    self.datePicker.dateValue = [NSDate date];
    [self updateSky:nil];
}

- (void)planetSelected:(id)sender {
    NSInteger row = self.planetTableView.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.planets.count) {
        return;
    }

    PlanetModel *planet = self.planets[(NSUInteger)row];
    [self showPlanet:planet];
}

#pragma mark - 3D planet inspector

- (void)showPlanet:(PlanetModel *)planet {
    if (!planet) {
        return;
    }

    self.planetNameLabel.stringValue = [NSString stringWithFormat:@"%@  %@", planet.symbol, planet.name];
    self.planetMetaLabel.stringValue = [NSString stringWithFormat:@"%@ · magnitude %.2f · %.2f AU",
                                        planet.constellation, planet.magnitude, planet.distanceAU];
    self.planetDescriptionLabel.stringValue = planet.planetDescription;

    self.diameterValueLabel.stringValue = planet.diameter;
    self.dayValueLabel.stringValue = planet.dayLength;
    self.yearValueLabel.stringValue = planet.yearLength;
    self.moonsValueLabel.stringValue = planet.moons;

    self.diameterValueLabel.toolTip = planet.diameter;
    self.dayValueLabel.toolTip = planet.dayLength;
    self.yearValueLabel.toolTip = planet.yearLength;
    self.moonsValueLabel.toolTip = planet.moons;

    [self configureSceneForPlanet:planet];
}

- (SCNScene *)sceneForPlanet:(PlanetModel *)planet pointOfView:(SCNNode **)outCameraNode {
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = [self starfieldImage];

    // Tilt the whole planet system by its axial tilt.
    SCNNode *tiltNode = [SCNNode node];
    tiltNode.eulerAngles = SCNVector3Make(0, 0, planet.axialTilt * M_PI / 180.0);
    [scene.rootNode addChildNode:tiltNode];

    BOOL isEarth = [planet.name isEqualToString:@"Earth"];

    // Globe.
    SCNSphere *sphere = [SCNSphere sphereWithRadius:1.0];
    sphere.segmentCount = 96;

    SCNMaterial *material = [SCNMaterial material];
    material.lightingModelName = SCNLightingModelBlinn;
    material.diffuse.contents = [self textureForPlanet:planet.name];
    material.diffuse.wrapS = SCNWrapModeRepeat;
    material.diffuse.wrapT = SCNWrapModeClamp;
    material.diffuse.mipFilter = SCNFilterModeLinear;
    material.specular.contents = [NSColor colorWithWhite:0.10 alpha:1.0];
    material.shininess = 0.12;

    if (isEarth) {
        // Relief from the bundled topography normal map.
        NSImage *normalMap = [self bundledTextureNamed:@"earth_normal" extension:@"jpg"];
        if (normalMap) {
            material.normal.contents = normalMap;
            material.normal.intensity = 0.65;
            material.normal.wrapS = SCNWrapModeRepeat;
            material.normal.wrapT = SCNWrapModeClamp;
            material.normal.mipFilter = SCNFilterModeLinear;
        }

        // The specular map is bright over water and black over land, so sunlight
        // produces ocean glints without making the continents look wet.
        NSImage *specularMap = [self bundledTextureNamed:@"earth_specular" extension:@"jpg"];
        if (specularMap) {
            material.specular.contents = specularMap;
            material.specular.intensity = 0.28;
            material.specular.wrapS = SCNWrapModeRepeat;
            material.specular.wrapT = SCNWrapModeClamp;
            material.specular.mipFilter = SCNFilterModeLinear;
            material.shininess = 0.5;
        }
    }

    sphere.materials = @[material];

    SCNNode *spinNode = [SCNNode node];
    SCNNode *globe = [SCNNode nodeWithGeometry:sphere];
    [spinNode addChildNode:globe];
    [tiltNode addChildNode:spinNode];

    CGFloat spinDuration = 26.0;
    SCNAction *spin = [SCNAction repeatActionForever:[SCNAction rotateByAngle:2.0 * M_PI
                                                                  aroundAxis:SCNVector3Make(0, 1, 0)
                                                                      duration:spinDuration]];
    [spinNode runAction:spin];

    // A cloud shell locked to the globe adds atmosphere without drifting
    // relative to the surface while the user orbits.
    if (isEarth) {
        NSImage *cloudMap = [self bundledTextureNamed:@"earth_clouds" extension:@"png"];
        if (cloudMap) {
            SCNSphere *cloudSphere = [SCNSphere sphereWithRadius:1.006];
            cloudSphere.segmentCount = 96;

            SCNMaterial *cloudMaterial = [SCNMaterial material];
            cloudMaterial.lightingModelName = SCNLightingModelBlinn;
            cloudMaterial.diffuse.contents = cloudMap;
            cloudMaterial.diffuse.wrapS = SCNWrapModeRepeat;
            cloudMaterial.diffuse.wrapT = SCNWrapModeClamp;
            cloudMaterial.diffuse.mipFilter = SCNFilterModeLinear;
            cloudMaterial.specular.contents = [NSColor colorWithWhite:0.0 alpha:1.0];
            cloudMaterial.shininess = 0.0;
            cloudMaterial.transparencyMode = SCNTransparencyModeAOne;
            cloudMaterial.transparency = 0.65;
            cloudMaterial.blendMode = SCNBlendModeAlpha;
            cloudMaterial.writesToDepthBuffer = NO;
            cloudMaterial.readsFromDepthBuffer = YES;
            cloudMaterial.doubleSided = NO;
            cloudSphere.materials = @[cloudMaterial];

            // Keep the atmosphere locked to the globe so it never drifts
            // relative to the surface while the user orbits the model.
            SCNNode *cloudNode = [SCNNode nodeWithGeometry:cloudSphere];
            cloudNode.renderingOrder = 5;
            [spinNode addChildNode:cloudNode];
        }
    }

    // A view-dependent blue rim on a slightly larger transparent sphere gives
    // Earth an atmosphere. It belongs to the planet, not the camera, so it
    // stays locked to the globe while the user orbits the model.
    if (isEarth) {
        SCNSphere *atmosphereSphere = [SCNSphere sphereWithRadius:1.015];
        atmosphereSphere.segmentCount = 96;

        SCNMaterial *atmosphereMaterial = [SCNMaterial material];
        atmosphereMaterial.lightingModelName = SCNLightingModelConstant;
        atmosphereMaterial.diffuse.contents = [NSColor blackColor];
        atmosphereMaterial.transparencyMode = SCNTransparencyModeAOne;
        atmosphereMaterial.blendMode = SCNBlendModeAdd;
        atmosphereMaterial.writesToDepthBuffer = NO;
        atmosphereMaterial.readsFromDepthBuffer = YES;
        atmosphereMaterial.doubleSided = NO;
        atmosphereMaterial.shaderModifiers = @{
            SCNShaderModifierEntryPointFragment:
                @"#pragma body\n"
                 "float rim = 1.0 - max(0.0, dot(_surface.normal, _surface.view));\n"
                 "rim = pow(rim, 3.0);\n"
                 "_output.color.rgb = vec3(0.28, 0.58, 1.0) * rim;\n"
                 "_output.color.a = rim;\n"
        };
        atmosphereSphere.materials = @[atmosphereMaterial];

        SCNNode *atmosphereNode = [SCNNode nodeWithGeometry:atmosphereSphere];
        atmosphereNode.renderingOrder = 10;
        [tiltNode addChildNode:atmosphereNode];
    }

    // Saturn's rings.
    if ([planet.name isEqualToString:@"Saturn"]) {
        SCNPlane *ringPlane = [SCNPlane planeWithWidth:4.0 height:4.0];
        SCNMaterial *ringMaterial = [SCNMaterial material];
        ringMaterial.lightingModelName = SCNLightingModelConstant;
        ringMaterial.diffuse.contents = [self saturnRingImage];
        ringMaterial.transparencyMode = SCNTransparencyModeAOne;
        ringMaterial.blendMode = SCNBlendModeAlpha;
        ringMaterial.doubleSided = YES;
        ringPlane.materials = @[ringMaterial];

        SCNNode *ringNode = [SCNNode nodeWithGeometry:ringPlane];
        ringNode.eulerAngles = SCNVector3Make(-M_PI_2, 0, 0);
        [tiltNode addChildNode:ringNode];
    }

    // Camera.
    SCNNode *cameraNode = [SCNNode node];
    SCNCamera *camera = [SCNCamera camera];
    camera.fieldOfView = 38.0;
    camera.zNear = 0.1;
    camera.zFar = 100.0;
    cameraNode.camera = camera;

    CGFloat cameraDistance = [planet.name isEqualToString:@"Saturn"] ? 6.3 : 4.4;
    cameraNode.position = SCNVector3Make(0, cameraDistance * 0.11, cameraDistance);
    [cameraNode lookAt:SCNVector3Zero];
    [scene.rootNode addChildNode:cameraNode];

    // Lighting: warm key light, cool fill, bluish rim.
    SCNNode *keyNode = [SCNNode node];
    SCNLight *keyLight = [SCNLight light];
    keyLight.type = SCNLightTypeDirectional;
    keyLight.intensity = 1150;
    keyLight.color = SKColor(1.0, 0.97, 0.90, 1.0);
    keyNode.light = keyLight;
    keyNode.position = SCNVector3Make(3.0, 2.2, 4.0);
    [keyNode lookAt:SCNVector3Zero];
    [scene.rootNode addChildNode:keyNode];

    SCNNode *fillNode = [SCNNode node];
    SCNLight *fillLight = [SCNLight light];
    fillLight.type = SCNLightTypeAmbient;
    fillLight.intensity = 260;
    fillLight.color = SKColor(0.55, 0.65, 0.90, 1.0);
    fillNode.light = fillLight;
    [scene.rootNode addChildNode:fillNode];

    SCNNode *rimNode = [SCNNode node];
    SCNLight *rimLight = [SCNLight light];
    rimLight.type = SCNLightTypeDirectional;
    rimLight.intensity = 620;
    rimLight.color = SKColor(0.55, 0.70, 1.0, 1.0);
    rimNode.light = rimLight;
    rimNode.position = SCNVector3Make(-3.5, -1.0, -3.0);
    [rimNode lookAt:SCNVector3Zero];
    [scene.rootNode addChildNode:rimNode];

    if (outCameraNode) {
        *outCameraNode = cameraNode;
    }
    return scene;
}

- (void)configureSceneForPlanet:(PlanetModel *)planet {
    SCNNode *cameraNode = nil;
    SCNScene *scene = [self sceneForPlanet:planet pointOfView:&cameraNode];
    self.planetSceneView.scene = scene;
    self.planetSceneView.pointOfView = cameraNode;
    self.planetSceneView.playing = YES;

    if (self.planetPopoutWindow) {
        [self configurePopoutForPlanet:planet];
    }
}

- (IBAction)popOutPlanetView:(id)sender {
    NSInteger row = self.planetTableView.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.planets.count) {
        return;
    }
    PlanetModel *planet = self.planets[(NSUInteger)row];

    BOOL created = NO;
    if (!self.planetPopoutWindow) {
        NSRect contentRect = NSMakeRect(0, 0, 620, 620);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                       styleMask:(NSWindowStyleMaskTitled |
                                                                  NSWindowStyleMaskClosable |
                                                                  NSWindowStyleMaskMiniaturizable |
                                                                  NSWindowStyleMaskResizable)
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = [NSString stringWithFormat:@"%@ — 3D View", planet.name];
        window.subtitle = @"Drag to orbit";
        window.releasedWhenClosed = NO;
        window.restorable = NO;
        window.tabbingMode = NSWindowTabbingModeDisallowed;
        window.minSize = NSMakeSize(360, 360);
        window.backgroundColor = [NSColor blackColor];
        window.delegate = self;

        SKPlanetSceneView *view = [[SKPlanetSceneView alloc] initWithFrame:NSMakeRect(0, 0, 620, 620)];
        view.translatesAutoresizingMaskIntoConstraints = YES;
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.backgroundColor = [NSColor blackColor];
        view.allowsCameraControl = YES;
        view.toolTip = @"Drag to orbit the planet";
        view.autoenablesDefaultLighting = NO;
        view.antialiasingMode = SCNAntialiasingModeMultisampling4X;
        view.preferredFramesPerSecond = 60;
        view.playing = YES;
        window.contentView = view;

        self.planetPopoutWindow = window;
        self.planetPopoutView = view;
        created = YES;

        NSRect windowFrame = window.frame;
        NSRect mainFrame = self.window.frame;
        NSPoint origin = NSMakePoint(NSMidX(mainFrame) - NSWidth(windowFrame) / 2.0,
                                     NSMidY(mainFrame) - NSHeight(windowFrame) / 2.0);
        [window setFrameOrigin:origin];
    }

    if (created) {
        [self configurePopoutForPlanet:planet];
    }

    [self.planetPopoutWindow makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)configurePopoutForPlanet:(PlanetModel *)planet {
    if (!self.planetPopoutWindow || !self.planetPopoutView) {
        return;
    }

    SCNNode *cameraNode = nil;
    SCNScene *scene = [self sceneForPlanet:planet pointOfView:&cameraNode];
    self.planetPopoutView.scene = scene;
    self.planetPopoutView.pointOfView = cameraNode;
    self.planetPopoutView.playing = YES;
    self.planetPopoutWindow.title = [NSString stringWithFormat:@"%@ — 3D View", planet.name];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.planetPopoutWindow) {
        self.planetPopoutWindow = nil;
        self.planetPopoutView = nil;
    }
}

- (void)selectPlanetNamed:(NSString *)name {
    NSUInteger index = [self.planets indexOfObjectPassingTest:^BOOL(PlanetModel *planet, NSUInteger idx, BOOL *stop) {
        return [planet.name caseInsensitiveCompare:name] == NSOrderedSame;
    }];
    if (index == NSNotFound) {
        return;
    }

    if (self.planetTableView.selectedRow == (NSInteger)index) {
        [self showPlanet:self.planets[index]];
    } else {
        [self.planetTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [self.planetTableView scrollRowToVisible:(NSInteger)index];
    }
}

#pragma mark - Procedural planet textures

- (NSImage *)textureForPlanet:(NSString *)name {
    NSImage *cached = _textureCache[name];
    if (cached) {
        return cached;
    }

    // Earth uses a real NASA Blue Marble map (bundled, so the app stays
    // offline). The procedural planet below remains as a fallback.
    NSImage *image = nil;
    if ([name isEqualToString:@"Earth"]) {
        image = [self bundledTextureNamed:@"earth_day" extension:@"jpg"];
    }
    if (!image) {
        image = [self generateTextureForPlanet:name];
    }
    _textureCache[name] = image;
    return image;
}

- (NSImage *)bundledTextureNamed:(NSString *)name extension:(NSString *)extension {
    NSString *cacheKey = [NSString stringWithFormat:@"bundled.%@.%@", name, extension];
    NSImage *cached = _textureCache[cacheKey];
    if (cached) {
        return cached;
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:extension];
    if (!path) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image) {
        _textureCache[cacheKey] = image;
    }
    return image;
}

- (NSImage *)generateTextureForPlanet:(NSString *)name {
    CGSize size = CGSizeMake(1024, 512);

    if ([name isEqualToString:@"Mercury"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            CGRect rect = CGRectMake(0, 0, size.width, size.height);
            SKFillVerticalGradient(ctx, rect, SKColor(0.36, 0.34, 0.31, 1.0), SKColor(0.58, 0.55, 0.50, 1.0));
            SKSeedRandom(0x4D455243u);

            for (NSInteger i = 0; i < 380; i++) {
                CGFloat x = SKRandomRange(0, size.width);
                CGFloat y = SKRandomRange(0, size.height);
                CGFloat r = 1.5 + pow(SKRandom(), 2.1) * 15.0;
                CGFloat shade = SKRandomRange(0.28, 0.62);
                CGContextSetFillColorWithColor(ctx, SKColor(shade, shade * 0.96, shade * 0.9, 0.45).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - r, y - r, r * 2, r * 2));

                CGContextSetStrokeColorWithColor(ctx, SKColor(0.78, 0.75, 0.70, 0.28).CGColor);
                CGContextSetLineWidth(ctx, 1.0);
                CGContextStrokeEllipseInRect(ctx, CGRectMake(x - r, y - r, r * 2, r * 2));

                if (r > 5.0 && SKRandom() < 0.6) {
                    CGContextSetFillColorWithColor(ctx, SKColor(0.83, 0.80, 0.74, 0.16).CGColor);
                    CGContextFillEllipseInRect(ctx, CGRectMake(x - r * 0.55, y + r * 0.05, r * 0.8, r * 0.5));
                }
            }

            SKDrawStreaks(ctx, size, 40, 0.05, NO);
        });
    }

    if ([name isEqualToString:@"Venus"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            NSArray<NSColor *> *palette = @[
                SKColor(0.76, 0.62, 0.36, 1.0),
                SKColor(0.88, 0.75, 0.46, 1.0),
                SKColor(0.95, 0.86, 0.60, 1.0),
                SKColor(0.84, 0.70, 0.42, 1.0)
            ];
            SKDrawBands(ctx, size, palette, 5.0, 0.55);
            SKSeedRandom(0x56454E55u);

            for (NSInteger i = 0; i < 90; i++) {
                CGFloat x = SKRandomRange(-60, size.width);
                CGFloat y = SKRandomRange(0, size.height);
                CGFloat w = SKRandomRange(60, 240);
                CGFloat h = SKRandomRange(4, 14);
                CGContextSetFillColorWithColor(ctx, SKColor(1.0, 0.96, 0.82, SKRandomRange(0.03, 0.10)).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x, y, w, h));
            }

            SKDrawStreaks(ctx, size, 70, 0.05, NO);
            SKDrawStreaks(ctx, size, 50, 0.05, YES);
        });
    }

    if ([name isEqualToString:@"Earth"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            CGFloat w = size.width;
            CGFloat h = size.height;
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, h),
                                   SKColor(0.05, 0.16, 0.32, 1.0),
                                   SKColor(0.12, 0.30, 0.55, 1.0));

            SKSeedRandom(0x45415254u);

            // Continental clusters of overlapping blobs.
            NSArray<NSValue *> *centers = @[
                [NSValue valueWithPoint:NSMakePoint(0.18, 0.30)],
                [NSValue valueWithPoint:NSMakePoint(0.26, 0.58)],
                [NSValue valueWithPoint:NSMakePoint(0.47, 0.28)],
                [NSValue valueWithPoint:NSMakePoint(0.52, 0.66)],
                [NSValue valueWithPoint:NSMakePoint(0.70, 0.38)],
                [NSValue valueWithPoint:NSMakePoint(0.82, 0.62)],
                [NSValue valueWithPoint:NSMakePoint(0.92, 0.32)],
                [NSValue valueWithPoint:NSMakePoint(0.06, 0.70)],
            ];

            for (NSValue *value in centers) {
                NSPoint center = value.pointValue;
                CGFloat cx = center.x * w;
                CGFloat cy = center.y * h;
                for (NSInteger i = 0; i < 80; i++) {
                    CGFloat dx = SKRandomRange(-70, 70);
                    CGFloat dy = SKRandomRange(-45, 45);
                    CGFloat rx = SKRandomRange(12, 46);
                    CGFloat ry = SKRandomRange(8, 34);
                    double tone = SKRandom();
                    NSColor *color = tone < 0.45 ? SKColor(0.22, 0.40, 0.21, 0.92)
                                    : tone < 0.75 ? SKColor(0.34, 0.48, 0.24, 0.92)
                                    : tone < 0.9  ? SKColor(0.50, 0.44, 0.28, 0.90)
                                                  : SKColor(0.62, 0.55, 0.36, 0.88);
                    CGContextSetFillColorWithColor(ctx, color.CGColor);
                    CGContextFillEllipseInRect(ctx, CGRectMake(cx + dx - rx, cy + dy - ry, rx * 2, ry * 2));
                }
            }

            // Polar ice.
            SKFillVerticalGradient(ctx, CGRectMake(0, h - 46, w, 46),
                                   SKColor(0.92, 0.96, 1.0, 0.0), SKColor(0.95, 0.98, 1.0, 0.95));
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, 40),
                                   SKColor(0.95, 0.98, 1.0, 0.95), SKColor(0.92, 0.96, 1.0, 0.0));

            // Clouds.
            for (NSInteger i = 0; i < 120; i++) {
                CGFloat x = SKRandomRange(-80, w);
                CGFloat y = SKRandomRange(0, h);
                CGFloat cw = SKRandomRange(50, 190);
                CGFloat ch = SKRandomRange(6, 20);
                CGContextSetFillColorWithColor(ctx, SKColor(1.0, 1.0, 1.0, SKRandomRange(0.06, 0.22)).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x, y, cw, ch));
            }
        });
    }

    if ([name isEqualToString:@"Mars"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            CGFloat w = size.width;
            CGFloat h = size.height;
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, h),
                                   SKColor(0.43, 0.18, 0.11, 1.0),
                                   SKColor(0.67, 0.31, 0.17, 1.0));
            SKSeedRandom(0x4D415253u);

            for (NSInteger i = 0; i < 120; i++) {
                CGFloat x = SKRandomRange(0, w);
                CGFloat y = SKRandomRange(0, h);
                CGFloat rx = SKRandomRange(18, 110);
                CGFloat ry = SKRandomRange(10, 55);
                BOOL dark = SKRandom() < 0.62;
                NSColor *color = dark ? SKColor(0.30, 0.13, 0.09, SKRandomRange(0.10, 0.28))
                                      : SKColor(0.80, 0.48, 0.28, SKRandomRange(0.08, 0.20));
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - rx, y - ry, rx * 2, ry * 2));
            }

            SKDrawStreaks(ctx, size, 60, 0.05, NO);
            SKDrawStreaks(ctx, size, 40, 0.05, YES);

            SKFillVerticalGradient(ctx, CGRectMake(0, h - 26, w, 26),
                                   SKColor(1, 1, 1, 0.0), SKColor(1, 1, 1, 0.85));
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, 20),
                                   SKColor(1, 1, 1, 0.85), SKColor(1, 1, 1, 0.0));
        });
    }

    if ([name isEqualToString:@"Jupiter"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            NSArray<NSColor *> *palette = @[
                SKColor(0.42, 0.28, 0.18, 1.0),
                SKColor(0.63, 0.44, 0.28, 1.0),
                SKColor(0.82, 0.68, 0.48, 1.0),
                SKColor(0.92, 0.84, 0.68, 1.0),
                SKColor(0.75, 0.57, 0.38, 1.0),
                SKColor(0.88, 0.78, 0.60, 1.0)
            ];
            SKDrawBands(ctx, size, palette, 9.0, 0.85);
            SKSeedRandom(0x4A555049u);
            SKDrawStreaks(ctx, size, 180, 0.06, YES);
            SKDrawStreaks(ctx, size, 140, 0.06, NO);

            // Great Red Spot.
            CGFloat spotX = size.width * 0.32;
            CGFloat spotY = size.height * 0.42;
            CGContextSetFillColorWithColor(ctx, SKColor(0.78, 0.38, 0.24, 0.95).CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(spotX - 62, spotY - 30, 124, 60));
            CGContextSetFillColorWithColor(ctx, SKColor(0.64, 0.27, 0.16, 0.95).CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(spotX - 42, spotY - 20, 84, 40));
            CGContextSetFillColorWithColor(ctx, SKColor(0.87, 0.55, 0.38, 0.5).CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(spotX - 72, spotY - 36, 144, 72));

            // White storms.
            for (NSInteger i = 0; i < 14; i++) {
                CGFloat x = SKRandomRange(0, size.width);
                CGFloat y = SKRandomRange(0, size.height);
                CGFloat rx = SKRandomRange(10, 28);
                CGFloat ry = SKRandomRange(4, 11);
                CGContextSetFillColorWithColor(ctx, SKColor(1, 1, 1, SKRandomRange(0.10, 0.28)).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - rx, y - ry, rx * 2, ry * 2));
            }
        });
    }

    if ([name isEqualToString:@"Saturn"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            NSArray<NSColor *> *palette = @[
                SKColor(0.72, 0.62, 0.42, 1.0),
                SKColor(0.85, 0.76, 0.55, 1.0),
                SKColor(0.93, 0.86, 0.67, 1.0),
                SKColor(0.88, 0.79, 0.58, 1.0),
                SKColor(0.80, 0.70, 0.50, 1.0)
            ];
            SKDrawBands(ctx, size, palette, 7.0, 0.45);
            SKSeedRandom(0x53415455u);
            SKDrawStreaks(ctx, size, 120, 0.04, YES);
            SKDrawStreaks(ctx, size, 80, 0.04, NO);
        });
    }

    if ([name isEqualToString:@"Uranus"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            NSArray<NSColor *> *palette = @[
                SKColor(0.56, 0.80, 0.82, 1.0),
                SKColor(0.66, 0.88, 0.89, 1.0),
                SKColor(0.72, 0.91, 0.92, 1.0),
                SKColor(0.63, 0.86, 0.88, 1.0)
            ];
            SKDrawBands(ctx, size, palette, 4.0, 0.25);
            SKSeedRandom(0x5552414Eu);
            SKDrawStreaks(ctx, size, 60, 0.03, YES);
            SKDrawStreaks(ctx, size, 30, 0.03, NO);
        });
    }

    if ([name isEqualToString:@"Pluto"]) {
        return SKImage(size, ^(CGContextRef ctx, CGSize size) {
            CGFloat w = size.width;
            CGFloat h = size.height;
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, h),
                                   SKColor(0.36, 0.28, 0.23, 1.0),
                                   SKColor(0.63, 0.53, 0.42, 1.0));
            SKSeedRandom(0x504C5554u);

            // Dark equatorial belt (Cthulhu Macula).
            for (NSInteger i = 0; i < 90; i++) {
                CGFloat x = SKRandomRange(-40, w * 0.55);
                CGFloat y = SKRandomRange(h * 0.20, h * 0.64);
                CGFloat rx = SKRandomRange(24, 90);
                CGFloat ry = SKRandomRange(10, 38);
                CGContextSetFillColorWithColor(ctx, SKColor(0.17, 0.09, 0.07, SKRandomRange(0.10, 0.26)).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - rx, y - ry, rx * 2, ry * 2));
            }

            // Bright heart-shaped nitrogen plain (Tombaugh Regio).
            CGFloat cx = w * 0.61;
            CGFloat cy = h * 0.56;
            CGContextSetFillColorWithColor(ctx, SKColor(0.93, 0.88, 0.79, 0.90).CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(cx - 118, cy - 24, 112, 106));
            CGContextFillEllipseInRect(ctx, CGRectMake(cx + 6, cy - 28, 112, 112));
            CGContextFillEllipseInRect(ctx, CGRectMake(cx - 70, cy - 56, 168, 138));

            for (NSInteger i = 0; i < 26; i++) {
                CGFloat x = cx + SKRandomRange(-90, 90);
                CGFloat y = cy + SKRandomRange(-60, 60);
                CGFloat rx = SKRandomRange(14, 36);
                CGContextSetFillColorWithColor(ctx, SKColor(0.95, 0.91, 0.83, SKRandomRange(0.15, 0.40)).CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - rx, y - rx * 0.7, rx * 2, rx * 1.4));
            }

            // Craters and mottled ice.
            for (NSInteger i = 0; i < 130; i++) {
                CGFloat x = SKRandomRange(0, w);
                CGFloat y = SKRandomRange(0, h);
                CGFloat r = SKRandomRange(2, 12);
                BOOL bright = SKRandom() < 0.45;
                NSColor *color = bright ? SKColor(0.82, 0.76, 0.66, SKRandomRange(0.10, 0.30))
                                        : SKColor(0.28, 0.20, 0.16, SKRandomRange(0.10, 0.26));
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                CGContextFillEllipseInRect(ctx, CGRectMake(x - r, y - r, r * 2, r * 2));
            }

            // Faint polar frost.
            SKFillVerticalGradient(ctx, CGRectMake(0, h - 34, w, 34),
                                   SKColor(0.86, 0.82, 0.74, 0.0), SKColor(0.88, 0.84, 0.76, 0.35));
            SKFillVerticalGradient(ctx, CGRectMake(0, 0, w, 26),
                                   SKColor(0.86, 0.82, 0.74, 0.30), SKColor(0.86, 0.82, 0.74, 0.0));
        });
    }

    // Neptune (also the default).
    return SKImage(size, ^(CGContextRef ctx, CGSize size) {
        NSArray<NSColor *> *palette = @[
            SKColor(0.13, 0.21, 0.53, 1.0),
            SKColor(0.19, 0.30, 0.68, 1.0),
            SKColor(0.26, 0.39, 0.80, 1.0),
            SKColor(0.20, 0.32, 0.70, 1.0)
        ];
        SKDrawBands(ctx, size, palette, 6.0, 0.5);
        SKSeedRandom(0x4E455054u);

        // Dark spot with a bright companion cloud.
        CGContextSetFillColorWithColor(ctx, SKColor(0.09, 0.15, 0.40, 0.65).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(size.width * 0.58, size.height * 0.34, 122, 56));
        CGContextSetFillColorWithColor(ctx, SKColor(0.62, 0.74, 0.98, 0.22).CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(size.width * 0.55, size.height * 0.43, 150, 26));

        SKDrawStreaks(ctx, size, 90, 0.04, YES);
        SKDrawStreaks(ctx, size, 60, 0.04, NO);
    });
}

- (NSImage *)saturnRingImage {
    if (_ringImage) {
        return _ringImage;
    }

    _ringImage = SKImage(CGSizeMake(512, 512), ^(CGContextRef ctx, CGSize size) {
        CGContextClearRect(ctx, CGRectMake(0, 0, size.width, size.height));
        CGPoint center = CGPointMake(size.width / 2.0, size.height / 2.0);
        CGFloat inner = 154.0;
        CGFloat outer = 256.0;

        for (CGFloat radius = inner; radius < outer; radius += 0.75) {
            double t = (radius - inner) / (outer - inner);
            double alpha = 0.0;

            if (t < 0.10) {
                alpha = 0.10 + 0.12 * t / 0.10;          // C ring (faint)
            } else if (t < 0.64) {
                alpha = 0.78 + 0.16 * sin(t * 54.0);     // B ring (bright)
            } else if (t < 0.72) {
                alpha = 0.05;                            // Cassini division
            } else if (t < 0.97) {
                alpha = 0.52 + 0.12 * sin(t * 42.0);     // A ring
            } else {
                alpha = 0.30 * (1.0 - t) / 0.03;         // outer fade
            }

            // Encke gap.
            if (t > 0.88 && t < 0.895) {
                alpha = 0.04;
            }

            alpha = MAX(0.0, MIN(1.0, alpha));
            double tone = 0.80 + 0.06 * sin(t * 30.0);
            NSColor *color = SKColor(tone, tone * 0.92, tone * 0.74, alpha);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 1.0);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2));
        }
    });

    return _ringImage;
}

- (NSImage *)starfieldImage {
    if (_starfieldImage) {
        return _starfieldImage;
    }

    _starfieldImage = SKImage(CGSizeMake(1024, 1024), ^(CGContextRef ctx, CGSize size) {
        CGRect rect = CGRectMake(0, 0, size.width, size.height);
        CGContextSetFillColorWithColor(ctx, SKColor(0.016, 0.024, 0.051, 1.0).CGColor);
        CGContextFillRect(ctx, rect);

        // Soft nebula patches.
        SKDrawRadialGlow(ctx, CGPointMake(280, 700), 380, SKColor(0.20, 0.28, 0.55, 1.0), 0.22);
        SKDrawRadialGlow(ctx, CGPointMake(760, 320), 340, SKColor(0.32, 0.22, 0.48, 1.0), 0.16);
        SKDrawRadialGlow(ctx, CGPointMake(620, 780), 300, SKColor(0.16, 0.34, 0.48, 1.0), 0.12);

        SKSeedRandom(0x53544152u);

        // Milky Way band.
        for (NSInteger i = 0; i < 900; i++) {
            CGFloat x = SKRandomRange(0, size.width);
            CGFloat bandY = size.height * 0.42 + sin(x / size.width * M_PI * 2.0) * size.height * 0.14;
            CGFloat y = bandY + SKRandomRange(-70, 70);
            CGFloat radius = SKRandomRange(0.3, 1.1);
            CGFloat alpha = SKRandomRange(0.05, 0.30);
            CGContextSetFillColorWithColor(ctx, SKColor(0.78, 0.84, 1.0, alpha).CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x, y, radius * 2, radius * 2));
        }

        // Field stars.
        for (NSInteger i = 0; i < 620; i++) {
            CGFloat x = SKRandomRange(0, size.width);
            CGFloat y = SKRandomRange(0, size.height);
            CGFloat radius = SKRandomRange(0.4, 1.7);
            CGFloat alpha = SKRandomRange(0.20, 0.95);
            double warmth = SKRandom();
            NSColor *color = warmth < 0.15 ? SKColor(1.0, 0.88, 0.70, alpha)
                            : warmth < 0.30 ? SKColor(0.72, 0.82, 1.0, alpha)
                                            : SKColor(1.0, 1.0, 1.0, alpha);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(x, y, radius * 2, radius * 2));

            if (radius > 1.45) {
                SKDrawRadialGlow(ctx, CGPointMake(x + radius, y + radius), radius * 7.0, color, 0.35);
            }
        }
    });

    return _starfieldImage;
}

#pragma mark - Location

- (void)configureLocationServices {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;

    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager.authorizationStatus == kCLAuthorizationStatusAuthorizedAlways) {
        [manager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (!location) {
        return;
    }

    [manager stopUpdatingLocation];

    // Show a readable placeholder immediately, then the resolved place name.
    [self setLocationFieldText:kCurrentLocationName];
    [self cacheLocation:location name:kCurrentLocationName forQuery:kCurrentLocationName];

    NSDate *date = self.datePicker.dateValue ?: [NSDate date];
    [self loadSkyMapWithCoordinate:location.coordinate locationName:kCurrentLocationName date:date];

    [self reverseGeocodeLocation:location coordinateText:kCurrentLocationName];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"SkyTrack location error: %@", error.localizedDescription);
}

- (void)presentLocationError:(NSString *)message {
    [self presentAlertWithTitle:@"Location unavailable" message:message];
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Geocoding

- (void)cacheLocation:(CLLocation *)location name:(NSString *)name forQuery:(NSString *)query {
    if (!location || query.length == 0) {
        return;
    }

    _geocodeCache[query.lowercaseString] = @{
        @"location": location,
        @"name": name.length > 0 ? name : query
    };
}

- (void)geocodeQuery:(NSString *)query {
    self.geocodeRequestToken += 1;
    NSUInteger token = self.geocodeRequestToken;
    [self.geocoder cancelGeocode];

    NSString *submittedText = self.locationTextField.stringValue;

    [self.searchSpinner startAnimation:nil];

    __weak typeof(self) weakSelf = self;
    [self.geocoder geocodeAddressString:query completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || token != self.geocodeRequestToken) {
            return;
        }

        [self.searchSpinner stopAnimation:nil];

        // The user may have edited the field while this lookup was running.
        if (![self.locationTextField.stringValue isEqualToString:submittedText]) {
            return;
        }

        BOOL canceled = [error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorGeocodeCanceled;
        if (canceled) {
            return;
        }

        CLPlacemark *placemark = placemarks.firstObject;
        if (!placemark || !placemark.location) {
            BOOL noResult = [error.domain isEqualToString:kCLErrorDomain] && error.code == kCLErrorGeocodeFoundNoResult;
            NSString *message;
            if (error && !noResult) {
                message = [NSString stringWithFormat:@"Could not search for “%@”. %@", query, error.localizedDescription];
            } else {
                message = [NSString stringWithFormat:@"No matches for “%@”. Try a city and country, or enter coordinates as latitude, longitude.", query];
            }
            [self presentAlertWithTitle:@"Location not found" message:message];
            return;
        }

        NSString *displayName = [self displayNameForPlacemark:placemark fallback:query];
        [self cacheLocation:placemark.location name:displayName forQuery:query];
        [self cacheLocation:placemark.location name:displayName forQuery:displayName];

        [self setLocationFieldText:displayName];

        NSDate *date = self.datePicker.dateValue ?: [NSDate date];
        [self loadSkyMapWithCoordinate:placemark.location.coordinate locationName:displayName date:date];
    }];
}

- (void)reverseGeocodeLocation:(CLLocation *)location coordinateText:(NSString *)coordinateText {
    if (!self.reverseGeocoder) {
        self.reverseGeocoder = [[CLGeocoder alloc] init];
    }
    [self.reverseGeocoder cancelGeocode];

    __weak typeof(self) weakSelf = self;
    [self.reverseGeocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || placemarks.count == 0) {
            return;
        }

        // The user may have typed a different location while this lookup was running.
        if (![self.locationTextField.stringValue isEqualToString:coordinateText]) {
            return;
        }

        CLPlacemark *placemark = placemarks.firstObject;
        NSString *displayName = [self displayNameForPlacemark:placemark fallback:coordinateText];
        [self cacheLocation:location name:displayName forQuery:coordinateText];
        [self cacheLocation:location name:displayName forQuery:displayName];

        [self setLocationFieldText:displayName];

        NSDate *date = self.datePicker.dateValue ?: [NSDate date];
        [self loadSkyMapWithCoordinate:location.coordinate locationName:displayName date:date];
    }];
}

- (NSString *)displayNameForPlacemark:(CLPlacemark *)placemark fallback:(NSString *)fallback {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    NSString *primary = placemark.locality.length > 0 ? placemark.locality : placemark.subAdministrativeArea;
    if (primary.length == 0) {
        primary = placemark.name;
    }
    if (primary.length > 0) {
        [parts addObject:primary];
    }
    if (placemark.administrativeArea.length > 0 && ![parts containsObject:placemark.administrativeArea]) {
        [parts addObject:placemark.administrativeArea];
    }
    if (placemark.country.length > 0 && ![parts containsObject:placemark.country]) {
        [parts addObject:placemark.country];
    }

    return parts.count > 0 ? [parts componentsJoinedByString:@", "] : fallback;
}

- (BOOL)coordinateFromString:(NSString *)string coordinate:(CLLocationCoordinate2D *)coordinate {
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@","];
    if (parts.count != 2) {
        return NO;
    }

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *latitudeString = [parts[0] stringByTrimmingCharactersInSet:whitespace];
    NSString *longitudeString = [parts[1] stringByTrimmingCharactersInSet:whitespace];
    if (latitudeString.length == 0 || longitudeString.length == 0) {
        return NO;
    }

    NSScanner *latitudeScanner = [NSScanner scannerWithString:latitudeString];
    latitudeScanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double latitude = 0;
    if (![latitudeScanner scanDouble:&latitude] || !latitudeScanner.isAtEnd) {
        return NO;
    }

    NSScanner *longitudeScanner = [NSScanner scannerWithString:longitudeString];
    longitudeScanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double longitude = 0;
    if (![longitudeScanner scanDouble:&longitude] || !longitudeScanner.isAtEnd) {
        return NO;
    }

    if (latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0) {
        return NO;
    }

    if (coordinate) {
        coordinate->latitude = latitude;
        coordinate->longitude = longitude;
    }
    return YES;
}

#pragma mark - Sky map

- (void)loadSkyMapWithCoordinate:(CLLocationCoordinate2D)coordinate locationName:(NSString *)locationName date:(NSDate *)date {
    if (self.searchCompleter) {
        self.searchCompleter.region = MKCoordinateRegionMakeWithDistance(coordinate, 500000, 500000);
    }

    NSURL *templateURL = [[NSBundle mainBundle] URLForResource:@"sky" withExtension:@"html" subdirectory:@"Resources"];
    if (!templateURL) {
        templateURL = [[NSBundle mainBundle] URLForResource:@"sky" withExtension:@"html"];
    }

    NSString *html = nil;
    if (templateURL) {
        html = [NSString stringWithContentsOfURL:templateURL encoding:NSUTF8StringEncoding error:NULL];
    }

    if (html.length == 0) {
        html = @"<html><body style=\"background:#05070f;color:#dbe6ff;font-family:-apple-system;\"><h2>SkyTrack</h2><p>Sky map resource is missing from the application bundle.</p></body></html>";
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MMM d, y 'at' h:mm a zzz";
    NSString *dateString = [formatter stringFromDate:date];

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    isoFormatter.dateFormat = @"yyyy-MM-dd";
    NSString *isoDateString = [isoFormatter stringFromDate:date];

    NSString *planetsJSON = [self planetsJSON];

    html = [html stringByReplacingOccurrencesOfString:@"{{DATE}}" withString:[self escapedHTMLString:dateString]];
    html = [html stringByReplacingOccurrencesOfString:@"{{DATE_ISO}}" withString:isoDateString];
    html = [html stringByReplacingOccurrencesOfString:@"{{LOCATION}}" withString:[self escapedHTMLString:locationName]];
    html = [html stringByReplacingOccurrencesOfString:@"{{LAT}}" withString:[NSString stringWithFormat:@"%.4f", coordinate.latitude]];
    html = [html stringByReplacingOccurrencesOfString:@"{{LON}}" withString:[NSString stringWithFormat:@"%.4f", coordinate.longitude]];
    html = [html stringByReplacingOccurrencesOfString:@"{{PLANETS}}" withString:planetsJSON];

    [self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (NSString *)planetsJSON {
    NSMutableArray *items = [NSMutableArray array];
    for (PlanetModel *planet in self.planets) {
        [items addObject:@{
            @"name": planet.name,
            @"symbol": planet.symbol,
            @"constellation": planet.constellation,
            @"magnitude": @(planet.magnitude)
        }];
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:NULL];
    if (!data) {
        return @"[]";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]";
}

- (NSString *)escapedHTMLString:(NSString *)string {
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (tableView == self.planetTableView) {
        return [[SKPlanetRowView alloc] init];
    }
    return nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.suggestionsTable) {
        return (NSInteger)self.suggestions.count;
    }
    return (NSInteger)self.planets.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.suggestionsTable) {
        static NSUserInterfaceItemIdentifier const suggestionIdentifier = @"SuggestionCell";

        SKSuggestionCellView *cell = [tableView makeViewWithIdentifier:suggestionIdentifier owner:self];
        if (!cell) {
            cell = [[SKSuggestionCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
            cell.identifier = suggestionIdentifier;
        }

        if (row >= 0 && (NSUInteger)row < self.suggestions.count) {
            MKLocalSearchCompletion *completion = self.suggestions[(NSUInteger)row];
            cell.titleLabel.stringValue = completion.title ?: @"";
            cell.subtitleLabel.stringValue = completion.subtitle ?: @"";
        }
        return cell;
    }

    static NSUserInterfaceItemIdentifier const cellIdentifier = @"PlanetCell";

    SKPlanetCellView *cell = [tableView makeViewWithIdentifier:cellIdentifier owner:self];
    if (!cell) {
        cell = [[SKPlanetCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cell.identifier = cellIdentifier;

        NSTextField *text = [NSTextField labelWithString:@""];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.textColor = [NSColor labelColor];
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:text];
        cell.planetLabel = text;
        cell.textField = text;

        [NSLayoutConstraint activateConstraints:@[
            [text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
            [text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    if (row >= 0 && (NSUInteger)row < self.planets.count) {
        PlanetModel *planet = self.planets[(NSUInteger)row];
        cell.textField.stringValue = [NSString stringWithFormat:@"%@  %@", planet.symbol, planet.name];
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.planetTableView) {
        return;
    }
    [self planetSelected:notification.object];
}

#pragma mark - Location suggestions

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object != self.locationTextField || self.updatingLocationFieldProgrammatically) {
        return;
    }

    NSString *query = [self.locationTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.suggestionsDismissed = NO;

    CLLocationCoordinate2D ignoredCoordinate;
    if (query.length < 2 || [self coordinateFromString:query coordinate:&ignoredCoordinate]) {
        [self hideSuggestions];
        self.searchCompleter.queryFragment = @"";
        return;
    }

    self.searchCompleter.queryFragment = query;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object != self.locationTextField) {
        return;
    }

    // Let a click on the suggestion list land before hiding it.
    [self performSelector:@selector(hideSuggestions) withObject:nil afterDelay:0.2];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control != self.locationTextField) {
        return NO;
    }

    BOOL suggestionsVisible = !self.suggestionsContainer.hidden && self.suggestions.count > 0;

    if (commandSelector == @selector(moveDown:)) {
        if (suggestionsVisible) {
            NSInteger row = self.suggestionsTable.selectedRow;
            row = row < 0 ? 0 : MIN(row + 1, (NSInteger)self.suggestions.count - 1);
            [self selectSuggestionRow:row];
            return YES;
        }
    } else if (commandSelector == @selector(moveUp:)) {
        if (suggestionsVisible) {
            NSInteger row = self.suggestionsTable.selectedRow;
            row = row < 0 ? (NSInteger)self.suggestions.count - 1 : MAX(row - 1, 0);
            [self selectSuggestionRow:row];
            return YES;
        }
    } else if (commandSelector == @selector(insertNewline:)) {
        if (suggestionsVisible && self.suggestionsTable.selectedRow >= 0) {
            [self acceptSuggestionAtIndex:self.suggestionsTable.selectedRow];
        } else {
            [self hideSuggestions];
            [self updateSky:nil];
        }
        return YES;
    } else if (commandSelector == @selector(cancelOperation:)) {
        if (suggestionsVisible) {
            self.suggestionsDismissed = YES;
            [self hideSuggestions];
            return YES;
        }
    } else if (commandSelector == @selector(selectAll:)) {
        [textView selectAll:nil];
        return YES;
    }

    return NO;
}

- (void)selectSuggestionRow:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.suggestions.count) {
        return;
    }

    [self.suggestionsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self.suggestionsTable scrollRowToVisible:row];
}

- (void)suggestionSelected:(id)sender {
    NSInteger row = self.suggestionsTable.clickedRow;
    if (row < 0) {
        row = self.suggestionsTable.selectedRow;
    }
    [self acceptSuggestionAtIndex:row];
}

- (void)acceptSuggestionAtIndex:(NSInteger)index {
    if (index < 0 || (NSUInteger)index >= self.suggestions.count) {
        return;
    }

    self.suggestionsDismissed = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSuggestions) object:nil];
    [self hideSuggestions];

    MKLocalSearchCompletion *completion = self.suggestions[(NSUInteger)index];
    NSString *title = completion.title ?: @"";
    NSString *subtitle = completion.subtitle ?: @"";
    NSString *query = title;
    if (title.length > 0 && subtitle.length > 0) {
        query = [NSString stringWithFormat:@"%@, %@", title, subtitle];
    } else if (title.length == 0) {
        query = subtitle;
    }

    [self setLocationFieldText:title];
    [self.window makeFirstResponder:self.locationTextField];
    NSText *fieldEditor = [self.locationTextField currentEditor];
    if (fieldEditor) {
        fieldEditor.selectedRange = NSMakeRange(title.length, 0);
    }

    if (query.length > 0) {
        [self geocodeQuery:query];
    }
}

- (void)updateSuggestionsVisibility {
    if (self.suggestionsDismissed || self.suggestions.count == 0) {
        self.suggestionsContainer.hidden = YES;
        return;
    }

    CGFloat height = MIN(self.suggestions.count, (NSUInteger)6) * self.suggestionsTable.rowHeight + 8.0;
    self.suggestionsHeightConstraint.constant = height;
    self.suggestionsContainer.hidden = NO;
}

- (void)hideSuggestions {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideSuggestions) object:nil];
    self.suggestionsContainer.hidden = YES;
    [self.suggestionsTable deselectAll:nil];
}

- (void)setLocationFieldText:(NSString *)text {
    self.updatingLocationFieldProgrammatically = YES;

    NSText *fieldEditor = [self.locationTextField currentEditor];
    if (fieldEditor) {
        fieldEditor.string = text;
        fieldEditor.selectedRange = NSMakeRange(text.length, 0);
    }
    self.locationTextField.stringValue = text;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.updatingLocationFieldProgrammatically = NO;
    });
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    if (completer != self.searchCompleter || self.suggestionsDismissed) {
        return;
    }

    NSString *query = [self.locationTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length < 2 || ![completer.queryFragment isEqualToString:query] || self.locationTextField.currentEditor == nil) {
        return;
    }

    NSUInteger limit = MIN(completer.results.count, (NSUInteger)6);
    self.suggestions = limit > 0 ? [completer.results subarrayWithRange:NSMakeRange(0, limit)] : @[];

    [self.suggestionsTable reloadData];
    if (self.suggestions.count == 0) {
        [self hideSuggestions];
        return;
    }

    [self selectSuggestionRow:0];
    [self updateSuggestionsVisibility];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    if (completer != self.searchCompleter) {
        return;
    }
    [self hideSuggestions];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"SkyTrack web view failed to load: %@", error.localizedDescription);
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"planetPicked"]) {
        return;
    }

    id body = message.body;
    if ([body isKindOfClass:[NSString class]]) {
        [self selectPlanetNamed:(NSString *)body];
    }
}

@end