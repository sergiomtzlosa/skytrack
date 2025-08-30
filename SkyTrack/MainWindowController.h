#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MainWindowController : NSWindowController <CLLocationManagerDelegate, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate, WKScriptMessageHandler>

@property (strong, nonatomic) WKWebView *webView;
@property (strong, nonatomic) NSTextField *locationTextField;
@property (strong, nonatomic) NSDatePicker *datePicker;
@property (strong, nonatomic) NSTableView *planetTableView;

/// 3D planet inspector.
@property (strong, nonatomic) SCNView *planetSceneView;
@property (strong, nonatomic) NSTextField *planetNameLabel;
@property (strong, nonatomic) NSTextField *planetMetaLabel;
@property (strong, nonatomic) NSTextField *planetDescriptionLabel;
@property (strong, nonatomic) NSTextField *diameterValueLabel;
@property (strong, nonatomic) NSTextField *dayValueLabel;
@property (strong, nonatomic) NSTextField *yearValueLabel;
@property (strong, nonatomic) NSTextField *moonsValueLabel;

@property (strong, nonatomic) CLLocationManager *locationManager;

+ (nullable NSImage *)applicationIconImage;

- (IBAction)updateSky:(nullable id)sender;
- (IBAction)selectLocation:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END