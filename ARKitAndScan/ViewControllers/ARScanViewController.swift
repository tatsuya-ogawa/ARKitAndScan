//
//  ARScanViewController.swift
//  ARKitAndScan
//
//  Created by Claude on 2025/10/13.
//

import UIKit
import ARKit
import MetalKit

class ARScanViewController: UIViewController {

    // MARK: - Properties

    private var arSession: ARSession!
    private var metalView: MTKView!
    private var metalRenderer: MetalRenderer!
    private var frameDataManager: FrameDataManager!

    private var isCapturing: Bool = false
    private var modeButton: UIButton!

    // UI Elements
    private var startButton: UIButton!
    private var stopButton: UIButton!
    private var statusLabel: UILabel!
    private var frameCountLabel: UILabel!

    private var frameCount: Int = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupARSession()
        setupMetalView()
        setupUI()
        setupFrameDataManager()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()
    }

    // MARK: - Setup

    private func setupARSession() {
        arSession = ARSession()
        arSession.delegate = self
    }

    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        metalView = MTKView(frame: view.bounds, device: device)
        metalView.backgroundColor = .black
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.contentScaleFactor = UIScreen.main.nativeScale
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true

        view.addSubview(metalView)

        // Setup renderer
        guard let renderer = MetalRenderer(device: device) else {
            fatalError("Failed to create MetalRenderer")
        }

        metalRenderer = renderer
        metalView.delegate = metalRenderer

        metalRenderer.onRenderComplete = { [weak self] frame in
            self?.handleRenderComplete(frame: frame)
        }
    }

    private func setupUI() {
        // Start button
        startButton = UIButton(type: .system)
        startButton.setTitle("Start Capture", for: .normal)
        startButton.backgroundColor = .systemGreen
        startButton.setTitleColor(.white, for: .normal)
        startButton.layer.cornerRadius = 8
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startCapture), for: .touchUpInside)
        view.addSubview(startButton)

        // Stop button
        stopButton = UIButton(type: .system)
        stopButton.setTitle("Stop Capture", for: .normal)
        stopButton.backgroundColor = .systemRed
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 8
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(stopCapture), for: .touchUpInside)
        stopButton.isEnabled = false
        view.addSubview(stopButton)

        modeButton = UIButton(type: .system)
        modeButton.setTitleColor(.white, for: .normal)
        modeButton.backgroundColor = .systemBlue
        modeButton.layer.cornerRadius = 8
        modeButton.clipsToBounds = true
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.addTarget(self, action: #selector(toggleRenderMode), for: .touchUpInside)
        view.addSubview(modeButton)

        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Ready"
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Frame count label
        frameCountLabel = UILabel()
        frameCountLabel.text = "Frames: 0"
        frameCountLabel.textColor = .white
        frameCountLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        frameCountLabel.textAlignment = .center
        frameCountLabel.layer.cornerRadius = 8
        frameCountLabel.clipsToBounds = true
        frameCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frameCountLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            startButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            startButton.widthAnchor.constraint(equalToConstant: 150),
            startButton.heightAnchor.constraint(equalToConstant: 50),

            stopButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            stopButton.widthAnchor.constraint(equalToConstant: 150),
            stopButton.heightAnchor.constraint(equalToConstant: 50),

            modeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeButton.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -16),
            modeButton.widthAnchor.constraint(equalToConstant: 200),
            modeButton.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.widthAnchor.constraint(equalToConstant: 200),
            statusLabel.heightAnchor.constraint(equalToConstant: 40),

            frameCountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameCountLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            frameCountLabel.widthAnchor.constraint(equalToConstant: 200),
            frameCountLabel.heightAnchor.constraint(equalToConstant: 40)
        ])

        updateModeButtonTitle()
    }

    private func setupFrameDataManager() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let outputDirectory: URL
        do {
            outputDirectory = try CaptureStorage.makeCaptureDirectory(named: timestamp)
        } catch {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fallback = documentsPath.appendingPathComponent("ARScans/\(timestamp)")
            print("CaptureStorage error (\(error)). Falling back to document directory: \(fallback.path)")
            outputDirectory = fallback
        }

        frameDataManager = FrameDataManager(outputDirectory: outputDirectory)

        do {
            try frameDataManager.setup()
            print("Output directory: \(outputDirectory.path)")
        } catch {
            print("Failed to setup output directory: \(error)")
        }
    }

    private func updateModeButtonTitle() {
        let modeName = metalRenderer.currentMeshRenderMode().displayName
        modeButton.setTitle("Mode: \(modeName)", for: .normal)
    }

    // MARK: - AR Session

    private func startARSession() {
        let configuration = ARWorldTrackingConfiguration()

        // Enable scene reconstruction
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        // Enable scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Capture Control

    @objc private func startCapture() {
        isCapturing = true
        frameCount = 0
        frameDataManager.reset()

        startButton.isEnabled = false
        stopButton.isEnabled = true
        statusLabel.text = "Capturing..."
        statusLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.6)

        print("Started capture")
    }

    @objc private func stopCapture() {
        isCapturing = false

        startButton.isEnabled = true
        stopButton.isEnabled = false
        statusLabel.text = "Stopped"
        statusLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.6)

        print("Stopped capture. Total frames: \(frameCount)")
    }

    @objc private func toggleRenderMode() {
        metalRenderer.cycleRenderMode()
        updateModeButtonTitle()
    }

    // MARK: - Render Callback

    private func handleRenderComplete(frame: ARFrame) {
        guard isCapturing else { return }

        frameDataManager.saveFrame(frame) { [weak self] success, error in
            if success {
                self?.frameCount += 1
                DispatchQueue.main.async {
                    self?.frameCountLabel.text = "Frames: \(self?.frameCount ?? 0)"
                }
            } else if let error = error {
                print("Frame save error: \(error)")
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARScanViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        metalRenderer.updateFrame(frame)
        metalView.draw()
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                metalRenderer.updateMesh(for: meshAnchor)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                metalRenderer.updateMesh(for: meshAnchor)
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                metalRenderer.removeMesh(for: meshAnchor)
            }
        }
    }
}

private extension MeshRenderMode {
    var displayName: String {
        switch self {
        case .shaded:
            return "Shaded"
        case .outline:
            return "Outline"
        case .shadedWithOutline:
            return "Shaded+Outline"
        }
    }
}
