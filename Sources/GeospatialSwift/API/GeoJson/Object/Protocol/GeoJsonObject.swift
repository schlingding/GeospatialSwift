import Foundation

/**
 GeoJsonObject Protocol
 
 Does not support projected coordinates, only geographic
 */
public protocol GeoJsonObject: CustomStringConvertible {
    var type: GeoJsonObjectType { get }
    
    var objectGeometries: [GeoJsonGeometry]? { get }
    
    var objectBoundingBox: GeodesicBoundingBox? { get }
    
    var geoJson: GeoJsonDictionary { get }
    
    // SOMEDAY: Could this be expanded to more than point?
    func objectDistance(to point: GeodesicPoint, tolerance: Double) -> Double?
    
    // SOMEDAY: Could this be expanded to more than point?
    func contains(_ point: GeodesicPoint, tolerance: Double) -> Bool
    
    // SOMEDAY: More fun!
    //func overlaps(geoJsonObject: GeoJsonObject, tolerance: Double) -> Bool
    
    func invalidReasons(tolerance: Double) -> [GeoJsonInvalidReason]
}

extension GeoJsonObject {
    public func contains(_ point: GeodesicPoint) -> Bool { return contains(point, tolerance: 0) }
    
    public func objectDistance(to point: GeodesicPoint) -> Double? { return objectDistance(to: point, tolerance: 0) }
}

extension GeoJsonObject {
    public var isSimpleGeometry: Bool {
        return [.point, .lineString, .polygon].contains(type)
    }
    
    // Trust geoJson serialization
    public var geoJsonData: Data {
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: geoJson, options: [])
    }
    
    // Trust geoJson encoding
    public var geoJsonString: String {
        return String(data: geoJsonData, encoding: .utf8)!
    }
    
    public var coordinatesGeometries: [GeoJsonCoordinatesGeometry] {
        return (objectGeometries ?? []).flatMap { objectGeometry -> [GeoJsonCoordinatesGeometry] in
            if let geometry = objectGeometry as? GeoJsonCoordinatesGeometry { return [geometry] }
            
            return objectGeometry.coordinatesGeometries
        }
    }
    
    public var linearGeometries: [GeoJsonLinearGeometry] {
        return (objectGeometries ?? []).flatMap { objectGeometry -> [GeoJsonLinearGeometry] in
            if let geometry = objectGeometry as? GeoJsonLinearGeometry { return [geometry] }
            
            if objectGeometry is GeoJsonCoordinatesGeometry { return [] }
            
            return objectGeometry.linearGeometries
        }
    }
    
    public var closedGeometries: [GeoJsonClosedGeometry] {
        return (objectGeometries ?? []).flatMap { objectGeometry -> [GeoJsonClosedGeometry] in
            if let geometry = objectGeometry as? GeoJsonClosedGeometry { return [geometry] }
            
            if objectGeometry is GeoJsonCoordinatesGeometry { return [] }
            
            return objectGeometry.closedGeometries
        }
    }
}

public enum GeoJsonInvalidReason {
    case multipointInvalidReasons(_: [MultipointInvalidReason])
    case lineStringInvalidReasons(_: [LineStringInvalidReason])
    case multiLineStringInvalidReasons(_: [[LineStringInvalidReason]])
    case polygonInvalidReasons(_: [PolygonInvalidReason])
    case multiPolygonInvalidReasons(_: [[PolygonInvalidReason]])
}

extension GeoJsonObject {
    // swiftlint:disable:next cyclomatic_complexity
    public func invalidReasons(tolerance: Double) -> [GeoJsonInvalidReason] {
        guard let objectGeometries = objectGeometries else { return [] }
        
        let invalidReasons = objectGeometries.compactMap { object -> [GeoJsonInvalidReason] in
            switch object {
            case _ as GeoJsonPoint:
                return []
            case let object as GeoJsonMultiPoint:
                return [.multipointInvalidReasons(object.invalidReasons(tolerance: tolerance))]
            case let object as GeoJsonLineString:
                return [.lineStringInvalidReasons(object.invalidReasons(tolerance: tolerance))]
            case let object as GeoJsonMultiLineString:
                return [.multiLineStringInvalidReasons(object.invalidReasons(tolerance: tolerance))]
            case let object as GeoJsonPolygon:
                return [.polygonInvalidReasons(object.invalidReasons(tolerance: tolerance))]
            case let object as GeoJsonMultiPolygon:
                return [.multiPolygonInvalidReasons(object.invalidReasons(tolerance: tolerance))]
            case let object as GeoJsonGeometryCollection:
                return object.invalidReasons(tolerance: tolerance)
            case let object as GeoJsonFeature:
                return object.invalidReasons(tolerance: tolerance)
            case let object as GeoJsonFeatureCollection:
                return object.invalidReasons(tolerance: tolerance)
            default:
                return []
            }
        }
        
        return invalidReasons.flatMap { $0 }
    }
}

// swiftlint:disable:next cyclomatic_complexity
public func == (lhs: GeoJsonObject?, rhs: GeoJsonObject?) -> Bool {
    guard lhs != nil || rhs != nil else { return type(of: lhs) == type(of: rhs) }
    
    guard lhs?.type == rhs?.type, let type = lhs?.type ?? rhs?.type else { return false }
    
    switch type {
    case .featureCollection:
        guard let lhs = lhs as? GeoJsonFeatureCollection, let rhs = rhs as? GeoJsonFeatureCollection, lhs.features.count == rhs.features.count else { return false }
        
        for feature in lhs.features where !rhs.features.contains { $0 == feature } { return false }
        
        return true
    case .feature:
        guard let lhs = lhs as? GeoJsonFeature, let rhs = rhs as? GeoJsonFeature else { return false }
        
        return lhs.geometry == rhs.geometry && lhs.idAsString == rhs.idAsString && lhs.properties == rhs.properties
    case .geometryCollection:
        guard let lhs = lhs as? GeoJsonGeometryCollection, let rhs = rhs as? GeoJsonGeometryCollection else { return false }
        
        if lhs.objectGeometries == nil && rhs.objectGeometries == nil { return true }
        
        guard let lhsGeometries = lhs.objectGeometries, let rhsGeometries = rhs.objectGeometries, lhsGeometries.count == rhsGeometries.count else { return false }
        
        for geometry in lhsGeometries where !rhsGeometries.contains { $0 == geometry } { return false }
        
        return true
    case .multiPolygon:
        guard let lhs = lhs as? GeoJsonMultiPolygon, let rhs = rhs as? GeoJsonMultiPolygon, lhs.polygons.count == rhs.polygons.count else { return false }
        
        for polygon in lhs.polygons where !rhs.polygons.contains { $0 == polygon } { return false }
        
        return true
    case .polygon:
        guard let lhs = lhs as? GeoJsonPolygon, let rhs = rhs as? GeoJsonPolygon, lhs.negativeRings.count == rhs.negativeRings.count else { return false }
        
        guard lhs.geoJsonMainRing == rhs.geoJsonMainRing else { return false }
        
        for linearRing in lhs.geoJsonNegativeRings where !(rhs.geoJsonNegativeRings).contains { $0 == linearRing } { return false }
        
        return true
    case .multiLineString:
        guard let lhs = lhs as? GeoJsonMultiLineString, let rhs = rhs as? GeoJsonMultiLineString, lhs.lineStrings.count == rhs.lineStrings.count else { return false }
        
        for lineString in lhs.lineStrings where !rhs.lineStrings.contains { $0 == lineString } { return false }
        
        return true
    case .lineString:
        guard let lhs = lhs as? GeoJsonLineString, let rhs = rhs as? GeoJsonLineString, lhs.points.count == rhs.points.count else { return false }
        
        for (index, point) in lhs.points.enumerated() where !(rhs.points[index] == point) { return false }
        
        return true
    case .multiPoint:
        guard let lhs = lhs as? GeoJsonMultiPoint, let rhs = rhs as? GeoJsonMultiPoint, lhs.points.count == rhs.points.count else { return false }
        
        for point in lhs.points where !rhs.points.contains { $0 == point } { return false }
        
        return true
    case .point:
        guard let lhs = lhs as? GeodesicPoint, let rhs = rhs as? GeodesicPoint else { return false }
        
        return lhs == rhs
    }
}

public func == (lhs: [GeoJsonObject]?, rhs: [GeoJsonObject]?) -> Bool {
    guard lhs != nil || rhs != nil else { return true }
    
    guard let lhs = lhs, let rhs = rhs, lhs.count == rhs.count else { return false }
    
    for geoJsonObject in lhs where !rhs.contains { $0 == geoJsonObject } { return false }
    
    return true
}