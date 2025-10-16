//
//  MeshData.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import ARKit
import Metal

// MARK: - ARMeshGeometry Extension

extension ARMeshGeometry {
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats per vertex.")
        let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        return vertex
    }
}

struct MeshData {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let faces: [UInt32]
    let transform: simd_float4x4

    init(meshAnchor: ARMeshAnchor) {
        let geometry = meshAnchor.geometry

    // Extract vertex data (reference implementation)
        var vertices: [SIMD3<Float>] = []
        for vertexIndex in 0..<geometry.vertices.count {
            let vertex = geometry.vertex(at: UInt32(vertexIndex))
            vertices.append(vertex)
        }
        self.vertices = vertices

    // Extract normal data (reference implementation)
        var normals: [SIMD3<Float>] = []
        let normalsPointer = geometry.normals.buffer.contents()
        let normalsStride = geometry.normals.stride
        let normalsOffset = geometry.normals.offset
        for normalIndex in 0..<geometry.normals.count {
            let normalPointer = normalsPointer.advanced(by: normalsOffset + (normalsStride * normalIndex))
            let normal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            normals.append(normal)
        }
        self.normals = normals

    // Extract face/index data (reference implementation - using Data)
        let indexData = Data(
            bytes: geometry.faces.buffer.contents(),
            count: geometry.faces.bytesPerIndex * geometry.faces.count * geometry.faces.indexCountPerPrimitive
        )

    // Convert to UInt32 array
        var faceIndices: [UInt32] = []
        if geometry.faces.bytesPerIndex == MemoryLayout<UInt32>.size {
            // Case: UInt32 indices
            indexData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                let buffer = pointer.bindMemory(to: UInt32.self)
                faceIndices = Array(buffer)
            }
        } else if geometry.faces.bytesPerIndex == MemoryLayout<UInt16>.size {
            // Case: UInt16 indices - convert to UInt32
            indexData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                let buffer = pointer.bindMemory(to: UInt16.self)
                faceIndices = buffer.map { UInt32($0) }
            }
        }
        self.faces = faceIndices

        // Transform
        self.transform = meshAnchor.transform
    }
}
