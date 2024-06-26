#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PlanetModel : NSObject

@property (copy, nonatomic) NSString *name;
@property (copy, nonatomic) NSString *symbol;
@property (copy, nonatomic) NSString *planetDescription;
@property (assign, nonatomic) double magnitude;
@property (copy, nonatomic) NSString *constellation;
@property (assign, nonatomic) double distanceAU;

/// Human-readable facts shown in the 3D inspector.
@property (copy, nonatomic) NSString *diameter;
@property (copy, nonatomic) NSString *dayLength;
@property (copy, nonatomic) NSString *yearLength;
@property (copy, nonatomic) NSString *moons;

/// Axial tilt in degrees, used to orient the 3D globe.
@property (assign, nonatomic) double axialTilt;

+ (instancetype)planetWithName:(NSString *)name
                        symbol:(NSString *)symbol
             planetDescription:(NSString *)planetDescription
                     magnitude:(double)magnitude
                  constellation:(NSString *)constellation
                     distanceAU:(double)distanceAU
                       diameter:(NSString *)diameter
                    dayLength:(NSString *)dayLength
                   yearLength:(NSString *)yearLength
                         moons:(NSString *)moons
                    axialTilt:(double)axialTilt;

+ (NSArray<PlanetModel *> *)planetData;

@end

NS_ASSUME_NONNULL_END