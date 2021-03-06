/**
 A GeoJsonLinearGeometry is a geometry made of lines
 */
public protocol GeoJsonLinearGeometry: GeoJsonCoordinatesGeometry {
    var lines: [GeodesicLine] { get }
    
    var length: Double { get }
}
