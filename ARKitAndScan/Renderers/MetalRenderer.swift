//
//  MetalRenderer.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import Foundation
import UIKit
import MetalKit
import ARKit

struct Uniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
}

enum MeshRenderMode: UInt32, CaseIterable {
    case shaded = 0
    case outline = 1
    case shadedWithOutline = 2
}

struct MeshFragmentUniforms {
    var mode: UInt32
    var outlineWidth: Float
    var outlineSoftness: Float
    var baseOpacity: Float
    var outlineColor: SIMD4<Float>
}

class MetalRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var renderPipelineState: MTLRenderPipelineState!
    var cameraPipelineState: MTLRenderPipelineState!
    var depthStencilState: MTLDepthStencilState!

    // Latest ARFrame provided by the session; consumed during the next draw call.
    private var pendingFrame: ARFrame?

    // Mesh data
    private var meshAnchors: [UUID: MeshBuffers] = [:]

    // Camera textures
    private var cameraTextureCache: CVMetalTextureCache!

    // Render completion callback
    var onRenderComplete: ((ARFrame) -> Void)?

    private var meshRenderMode: MeshRenderMode = .shaded {
        didSet {
            fragmentUniforms.mode = meshRenderMode.rawValue
        }
    }
    private var fragmentUniforms = MeshFragmentUniforms(
        mode: MeshRenderMode.shaded.rawValue,
        outlineWidth: 1.5,
        outlineSoftness: 1.0,
        baseOpacity: 1.0,
        outlineColor: SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
    )

    struct MeshBuffers {
        let vertexBuffer: MTLBuffer
        let normalBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let indexCount: Int
        let transform: simd_float4x4

        // Offsets and index info used in draw
        let vertexOffset: Int
        let normalOffset: Int
        let indexType: MTLIndexType
        let indexBufferOffset: Int
    }

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        super.init()

        setupTextureCache()
        setupPipeline()
        setupDepthStencilState()
    }

    private func setupTextureCache() {
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cameraTextureCache)
    }

    // MARK: - Setup

    func setMeshRenderMode(_ mode: MeshRenderMode) {
        meshRenderMode = mode
    }

    func configureOutline(width: Float? = nil, softness: Float? = nil, color: SIMD4<Float>? = nil) {
        if let width {
            fragmentUniforms.outlineWidth = max(width, 0.001)
        }
        if let softness {
            fragmentUniforms.outlineSoftness = max(softness, 0.0001)
        }
        if let color {
            fragmentUniforms.outlineColor = color
        }
    }

    func setBaseOpacity(_ opacity: Float) {
        fragmentUniforms.baseOpacity = max(0.0, min(1.0, opacity))
    }

    func currentMeshRenderMode() -> MeshRenderMode {
        meshRenderMode
    }

    func cycleRenderMode() {
        guard let index = MeshRenderMode.allCases.firstIndex(of: meshRenderMode) else {
            meshRenderMode = .shaded
            return
        }
        let nextIndex = MeshRenderMode.allCases.index(after: index)
        if nextIndex < MeshRenderMode.allCases.endIndex {
            meshRenderMode = MeshRenderMode.allCases[nextIndex]
        } else {
            meshRenderMode = MeshRenderMode.allCases.first ?? .shaded
        }
    }

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }

        // Camera background pipeline
        let cameraVertexFunction = library.makeFunction(name: "camera_vertex_shader")
        let cameraFragmentFunction = library.makeFunction(name: "camera_fragment_shader")

        let cameraPipelineDescriptor = MTLRenderPipelineDescriptor()
        cameraPipelineDescriptor.vertexFunction = cameraVertexFunction
        cameraPipelineDescriptor.fragmentFunction = cameraFragmentFunction
        cameraPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        cameraPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            cameraPipelineState = try device.makeRenderPipelineState(descriptor: cameraPipelineDescriptor)
        } catch {
            print("Failed to create camera pipeline state: \(error)")
        }

        // Mesh pipeline
        let vertexFunction = library.makeFunction(name: "mesh_vertex_shader")
        let fragmentFunction = library.makeFunction(name: "mesh_fragment_shader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.inputPrimitiveTopology = .triangle

        // Enable blending for mesh rendering over camera
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()

        // Position attribute
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Normal attribute
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1

        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        vertexDescriptor.layouts[1].stride = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create render pipeline state: \(error)")
        }
    }

    private func setupDepthStencilState() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    // MARK: - Mesh Management

    func updateMesh(for anchor: ARMeshAnchor) {
    // Convert to arrays using MeshData (same approach as reference) and create new buffers
        let meshData = MeshData(meshAnchor: anchor)

        guard let vertexBuffer = device.makeBuffer(
            bytes: meshData.vertices,
            length: meshData.vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: []
        ) else {
            print("Failed to create vertex buffer")
            return
        }

        guard let normalBuffer = device.makeBuffer(
            bytes: meshData.normals,
            length: meshData.normals.count * MemoryLayout<SIMD3<Float>>.stride,
            options: []
        ) else {
            print("Failed to create normal buffer")
            return
        }

        guard let indexBuffer = device.makeBuffer(
            bytes: meshData.faces,
            length: meshData.faces.count * MemoryLayout<UInt32>.stride,
            options: []
        ) else {
            print("Failed to create index buffer")
            return
        }

        let buffers = MeshBuffers(
            vertexBuffer: vertexBuffer,
            normalBuffer: normalBuffer,
            indexBuffer: indexBuffer,
            indexCount: meshData.faces.count,
            transform: meshData.transform,
            vertexOffset: 0,
            normalOffset: 0,
            indexType: .uint32,
            indexBufferOffset: 0
        )

        meshAnchors[anchor.identifier] = buffers
    }

    func removeMesh(for anchor: ARMeshAnchor) {
        meshAnchors.removeValue(forKey: anchor.identifier)
    }

    // MARK: - Rendering

    private func drawFrame(_ frame: ARFrame, in view: MTKView) {

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        attachErrorLogging(to: commandBuffer)

        // 1. Render camera background
        if let textureY = createTexture(from: frame.capturedImage, pixelFormat: .r8Unorm, planeIndex: 0),
           let textureCbCr = createTexture(from: frame.capturedImage, pixelFormat: .rg8Unorm, planeIndex: 1) {

            renderEncoder.setRenderPipelineState(cameraPipelineState)
            renderEncoder.setFragmentTexture(textureY, index: 0)
            renderEncoder.setFragmentTexture(textureCbCr, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        // 2. Render meshes on top
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.label = "MeshRenderEncoder"

        var fragmentUniforms = self.fragmentUniforms
        renderEncoder.setFragmentBytes(
            &fragmentUniforms,
            length: MemoryLayout<MeshFragmentUniforms>.stride,
            index: 0
        )

        // Camera matrices
        let interfaceOrientation = currentInterfaceOrientation(for: view)
        let viewMatrix = frame.camera.viewMatrix(for: interfaceOrientation)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: interfaceOrientation,
            viewportSize: view.drawableSize,
            zNear: 0.001,
            zFar: 1000
        )

        // Render each mesh
        for (_, meshBuffers) in meshAnchors {
            var uniforms = Uniforms(
                modelMatrix: meshBuffers.transform,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix
            )

            renderEncoder.setVertexBuffer(meshBuffers.vertexBuffer, offset: meshBuffers.vertexOffset, index: 0)
            renderEncoder.setVertexBuffer(meshBuffers.normalBuffer, offset: meshBuffers.normalOffset, index: 1)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)

            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: meshBuffers.indexCount,
                indexType: meshBuffers.indexType,
                indexBuffer: meshBuffers.indexBuffer,
                indexBufferOffset: meshBuffers.indexBufferOffset
            )
        }

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onRenderComplete?(frame)
            }
        }

        commandBuffer.commit()
    }

    func updateFrame(_ frame: ARFrame) {
        pendingFrame = frame
    }

    private func currentInterfaceOrientation(for view: MTKView) -> UIInterfaceOrientation {
        if #available(iOS 13.0, *), let orientation = view.window?.windowScene?.interfaceOrientation, orientation != .unknown {
            return orientation
        }

        // Fallback for earlier iOS versions or when the window scene is unavailable
        let statusBarOrientation = UIApplication.shared.statusBarOrientation
        return statusBarOrientation != .unknown ? statusBarOrientation : .portrait
    }

    // MARK: - Texture Creation

    private func createTexture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)

        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cameraTextureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &texture
        )

        guard status == kCVReturnSuccess, let cvTexture = texture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }

    private func attachErrorLogging(to commandBuffer: MTLCommandBuffer) {
        commandBuffer.label = "MetalRenderer.commandBuffer"
        commandBuffer.addCompletedHandler { buffer in
            guard buffer.status == .error, let error = buffer.error as NSError? else {
                return
            }

            var messages: [String] = [
                "Metal command buffer '\(buffer.label ?? "<unnamed>")' failed: \(error.localizedDescription) (\(error.domain) code \(error.code))"
            ]

            if let encoderInfos = error.userInfo[MTLCommandBufferEncoderInfoErrorKey] as? [MTLCommandBufferEncoderInfo],
               !encoderInfos.isEmpty {
                let encoderDetails = encoderInfos.map { info -> String in
                    let label = info.label
                    let stateDescription = String(describing: info.errorState)
                    return "\(label): \(stateDescription)"
                }
                messages.append("Encoder info -> \(encoderDetails.joined(separator: ", "))")
            }

            print(messages.joined(separator: "\n"))
        }
    }
}

// MARK: - MTKViewDelegate

extension MetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }

    func draw(in view: MTKView) {
        guard let frame = pendingFrame else { return }
        pendingFrame = nil
        drawFrame(frame, in: view)
    }
}
