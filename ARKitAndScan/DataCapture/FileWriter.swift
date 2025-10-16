//
//  FileWriter.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import Compression

class FileWriter {
    let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - Directory Management

    func createOutputDirectory() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Data Writing

    func writeJPEG(_ data: Data, index: Int) throws {
        let filename = String(format: "image_%06d.jpg", index)
        let url = outputDirectory.appendingPathComponent(filename)
        try data.write(to: url)
    }

    func writeGzipBinary(_ data: Data, filename: String) throws {
        let url = outputDirectory.appendingPathComponent(filename)
        guard let compressedData = compress(data: data) else {
            throw FileWriterError.compressionFailed
        }
        try compressedData.write(to: url)
    }

    func writeJSON<T: Encodable>(_ object: T, filename: String) throws {
        let url = outputDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(object)
        try data.write(to: url)
    }

    // MARK: - Compression

    private func compress(data: Data) -> Data? {
        return data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Data? in
            guard let baseAddress = sourcePtr.baseAddress else { return nil }

            let destinationBufferSize = data.count
            var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

            let compressedSize = compression_encode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )

            guard compressedSize > 0 else { return nil }

            return Data(bytes: destinationBuffer, count: compressedSize)
        }
    }
}

// MARK: - Errors

enum FileWriterError: Error {
    case compressionFailed
    case directoryCreationFailed
}
