//
//  FrameDataManager.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import ARKit
import CoreVideo
import CoreImage
import simd

class FrameDataManager {
    private let fileWriter: FileWriter
    private let metadataBuilder: MetadataBuilder
    private var frameIndex: Int = 0
    private let saveQueue = DispatchQueue(label: "com.arkit.framesave", qos: .userInitiated)

    init(outputDirectory: URL) {
        self.fileWriter = FileWriter(outputDirectory: outputDirectory)
        self.metadataBuilder = MetadataBuilder()
    }

    // MARK: - Setup

    func setup() throws {
        try fileWriter.createOutputDirectory()
    }

    // MARK: - Frame Saving

    func saveFrame(_ frame: ARFrame, completion: ((Bool, Error?) -> Void)? = nil) {
        saveQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let index = self.frameIndex
                self.frameIndex += 1

                var imageFileSize: Int?

                // 1. Save RGB image as JPEG
                if let jpegData = self.extractJPEG(from: frame.capturedImage) {
                    imageFileSize = jpegData.count
                    try self.fileWriter.writeJPEG(jpegData, index: index)
                }

                // 2. Save scene depth
                var depthSize: CGSize?
                var pointCloudInfo: CaptureMetadata.PointCloudInfo?
                if let sceneDepth = frame.sceneDepth {
                    let depthMap = sceneDepth.depthMap
                    depthSize = CGSize(
                        width: CVPixelBufferGetWidth(depthMap),
                        height: CVPixelBufferGetHeight(depthMap)
                    )

                    if let depthData = self.extractPixelBufferData(depthMap) {
                        let filename = String(format: "depth_%06d.bin.gz", index)
                        try self.fileWriter.writeGzipBinary(depthData, filename: filename)
                    }
                    
                    // 3. Save confidence map
                    if let confidenceMap = sceneDepth.confidenceMap{
                        if let confidenceData = self.extractPixelBufferData(confidenceMap) {
                            let filename = String(format: "confidence_%06d.bin.gz", index)
                            try self.fileWriter.writeGzipBinary(confidenceData, filename: filename)
                        }
                    }
                }

                // 3. Save LiDAR point cloud
                if let pointCloud = frame.rawFeaturePoints {
                    pointCloudInfo = try self.savePointCloud(pointCloud, index: index)
                }

                // 4. Save metadata
                let imageSize = CGSize(
                    width: CVPixelBufferGetWidth(frame.capturedImage),
                    height: CVPixelBufferGetHeight(frame.capturedImage)
                )

                let metadata = self.metadataBuilder.buildMetadata(
                    frame: frame,
                    imageIndex: index,
                    imageSize: imageSize,
                    depthSize: depthSize,
                    imageFileSize: imageFileSize,
                    pointCloudInfo: pointCloudInfo,
                    objectBoundingBox: pointCloudInfo?.boundingBox
                )

                let metadataFilename = String(format: "metadata_%06d.json", index)
                try self.fileWriter.writeJSON(metadata, filename: metadataFilename)

                // Save additional metadata files
                self.saveAdditionalMetadata(frame: frame, index: index)

                DispatchQueue.main.async {
                    completion?(true, nil)
                }
            } catch {
                print("Frame save error: \(error)")
                DispatchQueue.main.async {
                    completion?(false, error)
                }
            }
        }
    }

    // MARK: - Data Extraction

    private func extractJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        return context.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9]
        )
    }

    private func extractPixelBufferData(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let dataSize = bytesPerRow * height

        return Data(bytes: baseAddress, count: dataSize)
    }

    private func savePointCloud(_ pointCloud: ARPointCloud, index: Int) throws -> CaptureMetadata.PointCloudInfo? {
        let points = pointCloud.points
        guard !points.isEmpty else { return nil }

        var minPoint = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        for point in points {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }

        let rawData = points.withUnsafeBytes { Data($0) }
        let filename = String(format: "pointcloud_%06d.bin.gz", index)
        try fileWriter.writeGzipBinary(rawData, filename: filename)

        let boundingBox = CaptureMetadata.BoundingBoxData(
            min: [minPoint.x, minPoint.y, minPoint.z],
            max: [maxPoint.x, maxPoint.y, maxPoint.z]
        )

        return CaptureMetadata.PointCloudInfo(
            fileName: filename,
            pointCount: points.count,
            boundingBox: boundingBox
        )
    }

    // MARK: - Additional Metadata

    private func saveAdditionalMetadata(frame: ARFrame, index: Int) {
        do {
            // Camera tracking state
            let trackingState = metadataBuilder.buildCameraTrackingState(from: frame)
            let trackingFilename = String(format: "tracking_%06d.json", index)
            try fileWriter.writeJSON(trackingState, filename: trackingFilename)

            // Camera calibration
            let calibration = metadataBuilder.buildCameraCalibration(from: frame)
            let calibrationFilename = String(format: "calibration_%06d.json", index)
            try fileWriter.writeJSON(calibration, filename: calibrationFilename)

            // Camera transform
            let transform = metadataBuilder.buildCameraTransform(from: frame)
            let transformFilename = String(format: "transform_%06d.json", index)
            try fileWriter.writeJSON(transform, filename: transformFilename)
        } catch {
            print("Additional metadata save error: \(error)")
        }
    }

    // MARK: - Reset

    func reset() {
        frameIndex = 0
    }
}
