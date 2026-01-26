#import "PlanetModel.h"

@implementation PlanetModel

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
                    axialTilt:(double)axialTilt {
    PlanetModel *planet = [[PlanetModel alloc] init];
    planet.name = name;
    planet.symbol = symbol;
    planet.planetDescription = planetDescription;
    planet.magnitude = magnitude;
    planet.constellation = constellation;
    planet.distanceAU = distanceAU;
    planet.diameter = diameter;
    planet.dayLength = dayLength;
    planet.yearLength = yearLength;
    planet.moons = moons;
    planet.axialTilt = axialTilt;
    return planet;
}

+ (NSArray<PlanetModel *> *)planetData {
    return @[
        [PlanetModel planetWithName:@"Mercury"
                             symbol:@"☿"
                  planetDescription:@"Smallest planet in the Solar System, heavily cratered and airless."
                          magnitude:-0.5
                      constellation:@"Ophiuchus"
                         distanceAU:0.39
                           diameter:@"4,879 km"
                        dayLength:@"58.6 Earth days"
                       yearLength:@"88 Earth days"
                             moons:@"0"
                        axialTilt:0.03],
        [PlanetModel planetWithName:@"Venus"
                             symbol:@"♀"
                  planetDescription:@"Brightest natural object in Earth's sky after the Sun and Moon, wrapped in thick clouds."
                          magnitude:-4.9
                      constellation:@"Sagittarius"
                         distanceAU:0.72
                           diameter:@"12,104 km"
                        dayLength:@"243 Earth days (retrograde)"
                       yearLength:@"225 Earth days"
                             moons:@"0"
                        axialTilt:177.4],
        [PlanetModel planetWithName:@"Earth"
                             symbol:@"♁"
                  planetDescription:@"Our home planet, the only known place to support life."
                          magnitude:-0.84
                      constellation:@"Sagittarius"
                         distanceAU:1.00
                           diameter:@"12,742 km"
                        dayLength:@"24 hours"
                       yearLength:@"365.25 days"
                             moons:@"1"
                        axialTilt:23.4],
        [PlanetModel planetWithName:@"Mars"
                             symbol:@"♂"
                  planetDescription:@"The red planet, site of the largest volcano and canyon in the Solar System."
                          magnitude:1.84
                      constellation:@"Sagittarius"
                         distanceAU:1.52
                           diameter:@"6,779 km"
                        dayLength:@"24.6 hours"
                       yearLength:@"687 Earth days"
                             moons:@"2"
                        axialTilt:25.2],
        [PlanetModel planetWithName:@"Jupiter"
                             symbol:@"♃"
                  planetDescription:@"Largest planet, a gas giant with a Great Red Spot larger than Earth."
                          magnitude:-2.94
                      constellation:@"Ophiuchus"
                         distanceAU:5.20
                           diameter:@"139,820 km"
                        dayLength:@"9.9 hours"
                       yearLength:@"11.9 Earth years"
                             moons:@"95"
                        axialTilt:3.1],
        [PlanetModel planetWithName:@"Saturn"
                             symbol:@"♄"
                  planetDescription:@"Famous for its extensive ring system made of ice and rock."
                          magnitude:0.72
                      constellation:@"Sagittarius"
                         distanceAU:9.54
                           diameter:@"116,460 km"
                        dayLength:@"10.7 hours"
                       yearLength:@"29.5 Earth years"
                             moons:@"146"
                        axialTilt:26.7],
        [PlanetModel planetWithName:@"Uranus"
                             symbol:@"♅"
                  planetDescription:@"Ice giant that appears cyan because of methane in its atmosphere."
                          magnitude:5.78
                      constellation:@"Aries"
                         distanceAU:19.19
                           diameter:@"50,724 km"
                        dayLength:@"17.2 hours (retrograde)"
                       yearLength:@"84 Earth years"
                             moons:@"28"
                        axialTilt:97.8],
        [PlanetModel planetWithName:@"Neptune"
                             symbol:@"♆"
                  planetDescription:@"Windiest planet in the Solar System, a deep blue ice giant."
                          magnitude:7.78
                      constellation:@"Capricornus"
                         distanceAU:30.07
                           diameter:@"49,244 km"
                        dayLength:@"16.1 hours"
                       yearLength:@"165 Earth years"
                             moons:@"16"
                        axialTilt:28.3],
        [PlanetModel planetWithName:@"Pluto"
                             symbol:@"♇"
                  planetDescription:@"Dwarf planet in the Kuiper Belt, home to the bright heart-shaped plain Tombaugh Regio."
                          magnitude:14.4
                      constellation:@"Aquarius"
                         distanceAU:39.48
                           diameter:@"2,377 km"
                        dayLength:@"6.4 Earth days (retrograde)"
                       yearLength:@"248 Earth years"
                             moons:@"5"
                        axialTilt:122.5]
    ];
}

@end