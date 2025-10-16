//
//  MetadataBuilder.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import ARKit
import CoreVideo

class MetadataBuilder {

    func buildMetadata(
        frame: ARFrame,
        imageIndex: Int,
        imageSize: CGSize,
        depthSize: CGSize?,
        imageFileSize: Int?,
        pointCloudInfo: CaptureMetadata.PointCloudInfo?,
        objectBoundingBox: CaptureMetadata.BoundingBoxData?
    ) -> CaptureMetadata {
        var auxiliaryDataList: [CaptureMetadata.AuxiliaryDataInfo] = []

        // Depth data
        if let depthSize = depthSize {
            auxiliaryDataList.append(
                CaptureMetadata.AuxiliaryDataInfo(
                    auxiliaryDataType: "kCGImageAuxiliaryDataTypeDepth",
                    width: Int(depthSize.width),
                    height: Int(depthSize.height)
                )
            )

            auxiliaryDataList.append(
                CaptureMetadata.AuxiliaryDataInfo(
                    auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#DepthConfidenceMap",
                    width: Int(depthSize.width),
                    height: Int(depthSize.height)
                )
            )
        }

        // Camera tracking state
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#CameraTrackingState",
                width: nil,
                height: nil
            )
        )

        // Camera calibration
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#CameraCalibrationData",
                width: nil,
                height: nil
            )
        )

        // Object transform
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#ObjectTransform",
                width: nil,
                height: nil
            )
        )

        // Object bounding box
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#ObjectBoundingBox",
                width: nil,
                height: nil
            )
        )

        // Raw feature points
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#RawFeaturePoints",
                width: nil,
                height: nil
            )
        )

        // Point cloud data
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#PointCloudData",
                width: nil,
                height: nil
            )
        )

        // Bundle version
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#BundleVersion",
                width: nil,
                height: nil
            )
        )

        // Segment ID
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#SegmentID",
                width: nil,
                height: nil
            )
        )

        // Feedback
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#Feedback",
                width: nil,
                height: nil
            )
        )

        // Wide to depth camera transform
        auxiliaryDataList.append(
            CaptureMetadata.AuxiliaryDataInfo(
                auxiliaryDataType: "tag:apple.com,2023:ObjectCapture#WideToDepthCameraTransform",
                width: nil,
                height: nil
            )
        )

        // Thumbnail (optional)
        let thumbnails = [
            CaptureMetadata.ThumbnailInfo(width: 320, height: 240)
        ]

        let imageEntry = CaptureMetadata.Image(
            imageIndex: imageIndex,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            namedColorSpace: "kCGColorSpaceSRGB",
            auxiliaryData: auxiliaryDataList,
            thumbnailImages: thumbnails,
            pointCloud: pointCloudInfo,
            objectBoundingBox: objectBoundingBox
        )

        let fileContents = CaptureMetadata.FileContents(
            imageCount: 1,
            images: [imageEntry]
        )

        return CaptureMetadata(
            fileContents: fileContents,
            canAnimate: 0,
            fileSize: imageFileSize
        )
    }

    // MARK: - Helper Data Builders

    func buildCameraTrackingState(from frame: ARFrame) -> CameraTrackingStateData {
        let stateString: String
        var reasonString: String?

        switch frame.camera.trackingState {
        case .notAvailable:
            stateString = "notAvailable"
        case .limited(let reason):
            stateString = "limited"
            switch reason {
            case .initializing:
                reasonString = "initializing"
            case .relocalizing:
                reasonString = "relocalizing"
            case .excessiveMotion:
                reasonString = "excessiveMotion"
            case .insufficientFeatures:
                reasonString = "insufficientFeatures"
            @unknown default:
                reasonString = "unknown"
            }
        case .normal:
            stateString = "normal"
        }

        return CameraTrackingStateData(state: stateString, reason: reasonString)
    }

    func buildCameraCalibration(from frame: ARFrame) -> CameraCalibrationData {
        let intrinsics = frame.camera.intrinsics
        let intrinsicMatrix = [
            intrinsics[0][0], intrinsics[0][1], intrinsics[0][2],
            intrinsics[1][0], intrinsics[1][1], intrinsics[1][2],
            intrinsics[2][0], intrinsics[2][1], intrinsics[2][2]
        ]

        let imageResolution = [
            Int(frame.camera.imageResolution.width),
            Int(frame.camera.imageResolution.height)
        ]

        // Lens distortion center (typically image center)
        let lensDistortionCenter = [
            Float(frame.camera.imageResolution.width / 2),
            Float(frame.camera.imageResolution.height / 2)
        ]

        return CameraCalibrationData(
            intrinsicMatrix: intrinsicMatrix,
            imageResolution: imageResolution,
            lensDistortionCenter: lensDistortionCenter
        )
    }

    func buildCameraTransform(from frame: ARFrame) -> CameraTransformData {
        let transform = frame.camera.transform
        // Column-major order (Metal/ARKit standard)
        let transformArray = [
            transform[0][0], transform[0][1], transform[0][2], transform[0][3],
            transform[1][0], transform[1][1], transform[1][2], transform[1][3],
            transform[2][0], transform[2][1], transform[2][2], transform[2][3],
            transform[3][0], transform[3][1], transform[3][2], transform[3][3]
        ]

        return CameraTransformData(transformMatrix: transformArray)
    }
}
