//
//  CaptureMetadata.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import ARKit

struct CaptureMetadata: Codable {
    let fileContents: FileContents
    let canAnimate: Int
    let fileSize: Int?

    enum CodingKeys: String, CodingKey {
        case fileContents = "{FileContents}"
        case canAnimate = "CanAnimate"
        case fileSize = "FileSize"
    }

    struct FileContents: Codable {
        let imageCount: Int
        let images: [Image]

        enum CodingKeys: String, CodingKey {
            case imageCount = "ImageCount"
            case images = "Images"
        }
    }

    struct Image: Codable {
        let imageIndex: Int
        let width: Int
        let height: Int
        let namedColorSpace: String
        let auxiliaryData: [AuxiliaryDataInfo]
        let thumbnailImages: [ThumbnailInfo]?
        let pointCloud: PointCloudInfo?
        let objectBoundingBox: BoundingBoxData?

        enum CodingKeys: String, CodingKey {
            case imageIndex = "ImageIndex"
            case width = "Width"
            case height = "Height"
            case namedColorSpace = "NamedColorSpace"
            case auxiliaryData = "AuxiliaryData"
            case thumbnailImages = "ThumbnailImages"
            case pointCloud = "PointCloud"
            case objectBoundingBox = "ObjectBoundingBox"
        }
    }

    struct AuxiliaryDataInfo: Codable {
        let auxiliaryDataType: String
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case auxiliaryDataType = "AuxiliaryDataType"
            case width = "Width"
            case height = "Height"
        }
    }

    struct ThumbnailInfo: Codable {
        let width: Int
        let height: Int

        enum CodingKeys: String, CodingKey {
            case width = "Width"
            case height = "Height"
        }
    }

    struct PointCloudInfo: Codable {
        let fileName: String
        let pointCount: Int
        let boundingBox: BoundingBoxData?

        enum CodingKeys: String, CodingKey {
            case fileName = "FileName"
            case pointCount = "PointCount"
            case boundingBox = "BoundingBox"
        }
    }

    struct BoundingBoxData: Codable {
        let min: [Float]
        let max: [Float]

        enum CodingKeys: String, CodingKey {
            case min = "Min"
            case max = "Max"
        }
    }
}

// MARK: - Camera Data Structures

struct CameraTrackingStateData: Codable {
    let state: String
    let reason: String?
}

struct CameraCalibrationData: Codable {
    let intrinsicMatrix: [Float]  // 3x3 matrix flattened
    let imageResolution: [Int]    // [width, height]
    let lensDistortionCenter: [Float]  // [x, y]
}

struct CameraTransformData: Codable {
    let transformMatrix: [Float]  // 4x4 matrix flattened (column-major)
}
