//
//  PhotogrammetryViewController.swift
//  ARKitAndScan
//
//  Created by Codex on 2025/10/13.
//

import UIKit
import RealityKit
import Compression
import ImageIO
import CoreVideo
import simd

final class PhotogrammetryViewController: UIViewController {

    // MARK: - UI Components

    private let statusLabel = UILabel()
    private let selectedPathLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let logTextView = UITextView()
    private let capturesTableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()

    private var session: PhotogrammetrySession?
    private var processingTask: Task<Void, Never>?
    private var selectedFolderURL: URL? {
        didSet {
            updateSelectedPathLabel()
            refreshStartButtonState()
            updateTableSelection()
        }
    }
    private var generatedModelURL: URL?
    private var captureEntries: [CaptureStorage.Entry] = []
    private lazy var captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Photogrammetry"
        view.backgroundColor = .systemBackground

        setupUI()

        if supportsPhotogrammetry {
            applyIdleStateUI()
            updateSelectedPathLabel()
        } else {
            applyUnsupportedState(message: unsupportedPlatformMessage)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if supportsPhotogrammetry, processingTask == nil {
            reloadCaptureList()
        }
    }

    deinit {
        processingTask?.cancel()
        session?.cancel()
    }

    // MARK: - UI Setup

    private func setupUI() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
    statusLabel.text = "Please select an input folder"

        selectedPathLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedPathLabel.numberOfLines = 0
        selectedPathLabel.textAlignment = .left
        selectedPathLabel.textColor = .secondaryLabel

        startButton.translatesAutoresizingMaskIntoConstraints = false
    startButton.setTitle("Start Model Generation", for: .normal)
        startButton.addTarget(self, action: #selector(startProcessingTapped), for: .touchUpInside)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelProcessingTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.isEditable = false
        logTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        logTextView.layer.cornerRadius = 8
        logTextView.layer.borderWidth = 1
        logTextView.layer.borderColor = UIColor.separator.cgColor

        capturesTableView.translatesAutoresizingMaskIntoConstraints = false
        capturesTableView.dataSource = self
        capturesTableView.delegate = self
        capturesTableView.layer.cornerRadius = 8
        capturesTableView.layer.borderWidth = 1
        capturesTableView.layer.borderColor = UIColor.separator.cgColor
        capturesTableView.tableFooterView = UIView()
        capturesTableView.rowHeight = 56
        capturesTableView.separatorInset = .zero
        capturesTableView.layoutMargins = .zero
        capturesTableView.cellLayoutMarginsFollowReadableWidth = false
        refreshControl.addTarget(self, action: #selector(handleRefreshControl), for: .valueChanged)
        capturesTableView.refreshControl = refreshControl

        let buttonStack = UIStackView(arrangedSubviews: [startButton, cancelButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = UIStackView(arrangedSubviews: [
            statusLabel,
            selectedPathLabel,
            capturesTableView,
            buttonStack,
            activityIndicator,
            logTextView
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            capturesTableView.heightAnchor.constraint(equalToConstant: 240),
            logTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    private func applyIdleStateUI() {
        startButton.isEnabled = false
        cancelButton.isEnabled = false
        activityIndicator.stopAnimating()
        updateStatus("Please select an input folder")
        capturesTableView.isUserInteractionEnabled = true
        reloadCaptureList()
    }

    private func applyUnsupportedState(message: String) {
        updateStatus(message, isError: false)
        selectedPathLabel.text = """
Input folder: not selected
This feature is available on Mac (macOS 12 or later).
"""
        startButton.isEnabled = false
        cancelButton.isEnabled = false
        capturesTableView.isUserInteractionEnabled = false
        refreshControl.endRefreshing()
    }

    private func setProcessingUIActive(_ isProcessing: Bool) {
        if isProcessing {
            startButton.isEnabled = false
        } else {
            refreshStartButtonState()
        }
        cancelButton.isEnabled = isProcessing
        capturesTableView.isUserInteractionEnabled = !isProcessing

        if isProcessing {
            activityIndicator.startAnimating()
            refreshControl.endRefreshing()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func updateStatus(_ message: String, isError: Bool = false) {
        statusLabel.text = message
        statusLabel.textColor = isError ? .systemRed : .label
    }

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"

        if logTextView.text.isEmpty {
            logTextView.text = logEntry
        } else {
            logTextView.text.append("\n\(logEntry)")
        }

        let range = NSRange(location: max(0, logTextView.text.count - 1), length: 1)
        logTextView.scrollRangeToVisible(range)
    }

    private func updateSelectedPathLabel() {
        if let selectedFolderURL {
            selectedPathLabel.text = "Input folder:\n\(selectedFolderURL.lastPathComponent)\n\(selectedFolderURL.path)"
        } else {
            selectedPathLabel.text = "Input folder: not selected"
        }
    }

    private func refreshStartButtonState() {
        let canStart = supportsPhotogrammetry && selectedFolderURL != nil && processingTask == nil
        startButton.isEnabled = canStart
    }

    private func reloadCaptureList() {
        captureEntries = CaptureStorage.listCaptures()
        capturesTableView.reloadData()

        if captureEntries.isEmpty {
            selectedFolderURL = nil
            updateStatus("No saved captures found", isError: false)
        } else {
            if let current = selectedFolderURL, captureEntries.contains(where: { $0.url == current }) {
                updateTableSelection()
            } else {
                selectedFolderURL = captureEntries.first?.url
                if selectedFolderURL != nil {
                    updateStatus("Folder selected. You can start model generation.")
                }
            }
        }

        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
    }

    private func updateTableSelection() {
        guard let selectedFolderURL else {
            if let indexPath = capturesTableView.indexPathForSelectedRow {
                capturesTableView.deselectRow(at: indexPath, animated: false)
            }
            return
        }

        if let row = captureEntries.firstIndex(where: { $0.url == selectedFolderURL }) {
            let indexPath = IndexPath(row: row, section: 0)
            capturesTableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
    }

    private var supportsPhotogrammetry: Bool {
        if #available(iOS 17.0, macCatalyst 15.0, macOS 12.0, *) {
            return PhotogrammetrySession.isSupported
        } else {
            return false
        }
    }

    private var unsupportedPlatformMessage: String {
        "PhotogrammetrySession requires iOS 17 (device with LiDAR) or macOS 12 or later."
    }

    // MARK: - Actions

    @objc private func handleRefreshControl() {
        guard supportsPhotogrammetry else {
            refreshControl.endRefreshing()
            presentUnsupportedAlert()
            return
        }

        reloadCaptureList()
    }

    @objc private func startProcessingTapped() {
        guard supportsPhotogrammetry else {
            presentUnsupportedAlert()
            return
        }

        if #available(iOS 17.0, macCatalyst 15.0, macOS 12.0, *) {
            startPhotogrammetry()
        } else {
            presentUnsupportedAlert()
        }
    }

    @objc private func cancelProcessingTapped() {
        guard supportsPhotogrammetry else {
            presentUnsupportedAlert()
            return
        }

        if #available(iOS 17.0, macCatalyst 15.0, macOS 12.0, *) {
            processingTask?.cancel()
            session?.cancel()
            appendLog("Sent cancel request")
            updateStatus("Cancelling...")
            cancelButton.isEnabled = false
        } else {
            presentUnsupportedAlert()
        }
    }

    private func presentUnsupportedAlert() {
        let alert = UIAlertController(
            title: "Photogrammetry Unsupported",
            message: unsupportedPlatformMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension PhotogrammetryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        captureEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reusable = tableView.dequeueReusableCell(withIdentifier: "CaptureCell")
        let cell = reusable ?? UITableViewCell(style: .subtitle, reuseIdentifier: "CaptureCell")

        cell.preservesSuperviewLayoutMargins = false
        cell.contentView.preservesSuperviewLayoutMargins = false
        cell.layoutMargins = .zero
        cell.contentView.layoutMargins = .zero
        cell.separatorInset = .zero

        let entry = captureEntries[indexPath.row]
        cell.textLabel?.text = entry.name
        if let date = entry.createdAt {
            cell.detailTextLabel?.text = captureDateFormatter.string(from: date)
        } else {
            cell.detailTextLabel?.text = entry.url.lastPathComponent
        }
        cell.accessoryType = (entry.url == selectedFolderURL) ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard captureEntries.indices.contains(indexPath.row) else { return }
        let entry = captureEntries[indexPath.row]
        selectedFolderURL = entry.url
        updateStatus("Folder selected. You can start model generation.")
        tableView.reloadData()
    }
}

// MARK: - Photogrammetry Implementation

@available(iOS 17.0, macCatalyst 15.0, macOS 12.0, *)
extension PhotogrammetryViewController {

    // Currently returns reduced detail by default
    private func selectedDetailLevel() -> PhotogrammetrySession.Request.Detail {
        return .reduced
    }

    // Description string for the detail level
    private func detailDescription(_ detail: PhotogrammetrySession.Request.Detail) -> String {
        return String(describing: detail)
    }

    private func startPhotogrammetry() {
        guard processingTask == nil else {
            appendLog("Processing in progress. Please wait for completion.")
            return
        }
        guard let inputFolder = selectedFolderURL else {
            updateStatus("Input folder is not selected", isError: true)
            return
        }

        let detail = selectedDetailLevel()
        setProcessingUIActive(true)
    updateStatus("Initializing PhotogrammetrySession…")
    appendLog("Starting photogrammetry: detail=\(detailDescription(detail))")

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var termination: ProcessingTermination = .completed

            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.sampleOrdering = .sequential
                configuration.isObjectMaskingEnabled = false
                configuration.featureSensitivity = .normal

                let loader = PhotogrammetrySampleLoader(rootDirectory: inputFolder)
                let loaderResult = try loader.loadSamples { [weak self] index, error in
                    Task { @MainActor [weak self] in
                        self?.appendLog("Failed to stream sample \(index): \(error.localizedDescription)")
                    }
                }
                let usingSamples = loaderResult.sampleCount > 0

                await MainActor.run {
                    if usingSamples {
                        let droppedCount = loaderResult.droppedSampleIDs.count
                        self.appendLog("Loaded samples: using \(loaderResult.sampleCount)/\(loaderResult.totalCandidateCount) frames (depth: \(loaderResult.depthSampleCount), LiDAR: \(loaderResult.pointCloudSampleCount))")
                        if droppedCount > 0 {
                            let preview = loaderResult.droppedSampleIDs.prefix(5).map { String(format: "%06d", $0) }.joined(separator: ", ")
                            self.appendLog("Dropped \(droppedCount) frames for memory reasons: [\(preview)]")
                        }
                        if !loaderResult.missingDepthSampleIDs.isEmpty {
                            let preview = loaderResult.missingDepthSampleIDs.prefix(5).map { String(format: "%06d", $0) }.joined(separator: ", ")
                            self.appendLog("Example frames missing depth: [\(preview)]")
                        }
                        if !loaderResult.missingPointCloudSampleIDs.isEmpty {
                            let preview = loaderResult.missingPointCloudSampleIDs.prefix(5).map { String(format: "%06d", $0) }.joined(separator: ", ")
                            self.appendLog("Example frames missing LiDAR point cloud: [\(preview)]")
                        }
                        if let bbox = loaderResult.aggregateBoundingBox {
                            self.appendLog(String(format: "Estimated bounding box min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)", bbox.min.x, bbox.min.y, bbox.min.z, bbox.max.x, bbox.max.y, bbox.max.z))
                        }
                    } else {
                        self.appendLog("Could not build PhotogrammetrySample array; falling back to folder input")
                    }
                }

                let session: PhotogrammetrySession
                if usingSamples {
                    session = try PhotogrammetrySession(input: loaderResult.samples, configuration: configuration)
                } else {
                    session = try PhotogrammetrySession(input: inputFolder, configuration: configuration)
                }

                let outputURL = try self.prepareOutputURL(for: inputFolder, detail: detail)

                await MainActor.run {
                    self.session = session
                    self.generatedModelURL = outputURL
                    self.appendLog("Output: \(outputURL.path)")
                }

                let modelRequest: PhotogrammetrySession.Request
                if usingSamples, let bbox = loaderResult.aggregateBoundingBox {
                    let rfBoundingBox = RealityFoundation.BoundingBox(min: bbox.min, max: bbox.max)
                    let geometry = PhotogrammetrySession.Request.Geometry(bounds: rfBoundingBox)
                    modelRequest = .modelFile(url: outputURL, detail: detail, geometry: geometry)
                } else {
                    modelRequest = .modelFile(url: outputURL, detail: detail, geometry: nil)
                }

                try session.process(requests: [modelRequest])

                for try await output in session.outputs {
                    if Task.isCancelled {
                        termination = .cancelled
                        session.cancel()
                        break
                    }

                    if let newTermination = await self.handle(output: output) {
                        termination = newTermination
                        if termination != .completed {
                            session.cancel()
                            break
                        }
                    }
                }
            } catch {
                if Task.isCancelled {
                    termination = .cancelled
                } else {
                    termination = .failed
                    await MainActor.run {
                        self.appendLog("Error: \(error.localizedDescription)")
                            self.updateStatus("Error: \(error.localizedDescription)", isError: true)
                    }
                }
            }

            await MainActor.run {
                switch termination {
                case .completed:
                    self.updateStatus("Model generation completed")
                    if let output = self.generatedModelURL {
                        self.appendLog("Model file: \(output.path)")
                    }
                    self.finishProcessing(success: true, cancelled: false)
                case .cancelled:
                    self.appendLog("Photogrammetry processing was cancelled")
                    self.updateStatus("Cancelled")
                    self.finishProcessing(success: false, cancelled: true)
                case .failed:
                    self.appendLog("Photogrammetry processing failed")
                    self.updateStatus("Processing failed", isError: true)
                    self.finishProcessing(success: false, cancelled: false)
                }
            }
        }
    }

    private func prepareOutputURL(for inputFolder: URL, detail: PhotogrammetrySession.Request.Detail) throws -> URL {
        let modelsDirectory = inputFolder.appendingPathComponent("PhotogrammetryOutput", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date())

        let fileName = "Model_\(timestamp)_\(detailDescription(detail)).usdz"
        return modelsDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    private enum ProcessingTermination {
        case completed
        case cancelled
        case failed
    }

    private func handle(output: PhotogrammetrySession.Output) async -> ProcessingTermination? {
        switch output {
                case .requestProgress(let request, let fractionComplete):
            await MainActor.run {
                let percent = Int(fractionComplete * 100)
                self.updateStatus("Progress \(percent)% (\(self.describe(request)))")
            }
            return nil

        case .processingComplete:
            await MainActor.run {
                self.appendLog("Processing complete")
            }
            return .completed

        case .requestComplete(let request, let result):
            await MainActor.run {
                self.appendLog("Request complete: \(self.describe(request)) -> \(self.describe(result))")
            }
            return nil

        case .requestError(let request, let error):
            await MainActor.run {
                self.appendLog("Request error: \(self.describe(request)) / \(error.localizedDescription)")
                self.updateStatus("Error: \(error.localizedDescription)", isError: true)
            }
            return .failed

        case .processingCancelled:
            return .cancelled

        case .inputComplete:
            await MainActor.run {
                self.appendLog("All inputs have been loaded")
            }
            return nil

        case .invalidSample(let id, let reason):
            await MainActor.run {
                self.appendLog("Invalid sample \(id): \(String(describing: reason))")
            }
            return nil

        @unknown default:
            await MainActor.run {
                self.appendLog("Unhandled event: \(String(describing: output))")
            }
            return nil
        }
    }

    // Align with SDK where .modelFile associated value is (url: URL, detail: Detail, geometry: Geometry?)
    private func describe(_ request: PhotogrammetrySession.Request) -> String {
        switch request {
        case .modelFile(let url, let detail, _):
            return "modelFile(\(url.lastPathComponent), \(detailDescription(detail)))"
        @unknown default:
            return "unknown request"
        }
    }

    private func describe(_ result: PhotogrammetrySession.Result) -> String {
        switch result {
        case .modelFile(let url):
            return "modelFile(\(url.lastPathComponent))"
        @unknown default:
            return "unknown result"
        }
    }

    private func finishProcessing(success: Bool, cancelled: Bool) {
        processingTask = nil
        session = nil
        setProcessingUIActive(false)
        refreshStartButtonState()
    }
}

// MARK: - PhotogrammetrySample loader

@available(iOS 17.0, macCatalyst 15.0, macOS 12.0, *)
private struct PhotogrammetrySampleLoader {

    struct Result {
        let samples: AnySequence<PhotogrammetrySample>
        let sampleCount: Int
        let depthSampleCount: Int
        let missingDepthSampleIDs: [Int]
        let pointCloudSampleCount: Int
        let missingPointCloudSampleIDs: [Int]
        let aggregateBoundingBox: BoundingBox?
        let totalCandidateCount: Int
        let selectedSampleIDs: [Int]
        let droppedSampleIDs: [Int]
    }

    enum LoaderError: LocalizedError {
        case missingImage(URL)
        case imageDecodeFailed(URL)
        case pixelBufferAllocationFailed
        case jsonDecodingFailed(URL)
        case dataSizeMismatch(URL)

        var errorDescription: String? {
            switch self {
            case .missingImage(let url):
                return "Image file not found: \(url.lastPathComponent)"
            case .imageDecodeFailed(let url):
                return "Failed to decode image: \(url.lastPathComponent)"
            case .pixelBufferAllocationFailed:
                return "Failed to allocate CVPixelBuffer"
            case .jsonDecodingFailed(let url):
                return "Failed to read JSON: \(url.lastPathComponent)"
            case .dataSizeMismatch(let url):
                return "Depth data size does not match expected size: \(url.lastPathComponent)"
            }
        }
    }

    struct SampleDescriptor {
        let index: Int
        let hasImage: Bool
        let hasDepth: Bool
        let hasPointCloud: Bool
        let boundingBox: BoundingBox?

        var isUsable: Bool {
            hasImage && hasDepth && hasPointCloud
        }
    }

    typealias SampleErrorHandler = (Int, Error) -> Void

    struct BoundingBox {
        var min: SIMD3<Float>
        var max: SIMD3<Float>

        mutating func formUnion(_ other: BoundingBox) {
            min = simd_min(min, other.min)
            max = simd_max(max, other.max)
        }

        func union(_ other: BoundingBox) -> BoundingBox {
            var copy = self
            copy.formUnion(other)
            return copy
        }

        init(min: SIMD3<Float>, max: SIMD3<Float>) {
            self.min = min
            self.max = max
        }

        init?(data: CaptureMetadata.BoundingBoxData) {
            guard data.min.count == 3, data.max.count == 3 else { return nil }
            self.min = SIMD3<Float>(data.min[0], data.min[1], data.min[2])
            self.max = SIMD3<Float>(data.max[0], data.max[1], data.max[2])
        }
    }

    private let rootDirectory: URL
    private let fileManager = FileManager.default
    private let maxSampleCount = 120

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func loadSamples(onSampleFailure: SampleErrorHandler? = nil) throws -> Result {
        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var indexSet = Set<Int>()
        for url in contents {
            if let index = parseImageIndex(from: url.lastPathComponent) {
                indexSet.insert(index)
            }
        }

        let indices = indexSet.sorted()
        let totalCandidates = indices.count
        guard totalCandidates > 0 else {
            return Result(
                samples: AnySequence<PhotogrammetrySample> { AnyIterator { nil } },
                sampleCount: 0,
                depthSampleCount: 0,
                missingDepthSampleIDs: [],
                pointCloudSampleCount: 0,
                missingPointCloudSampleIDs: [],
                aggregateBoundingBox: nil,
                totalCandidateCount: 0,
                selectedSampleIDs: [],
                droppedSampleIDs: []
            )
        }

        var droppedIndices: [Int] = []
        let selectedIndices: [Int]
        if totalCandidates > maxSampleCount {
            let stride = max(1, Int(ceil(Double(totalCandidates) / Double(maxSampleCount))))
            selectedIndices = indices.enumerated().compactMap { offset, value in
                if offset % stride == 0 {
                    return value
                } else {
                    droppedIndices.append(value)
                    return nil
                }
            }
        } else {
            selectedIndices = indices
        }

        var depthCount = 0
        var missingDepth: [Int] = []
        var pointCloudCount = 0
        var missingPointCloud: [Int] = []
        var aggregateBoundingBox: BoundingBox?
        var usableIndices: [Int] = []

        let descriptors = try selectedIndices.map { try analyzeSample(for: $0) }

        for descriptor in descriptors {
            if descriptor.hasDepth {
                depthCount += 1
            } else {
                missingDepth.append(descriptor.index)
            }

            if descriptor.hasPointCloud {
                pointCloudCount += 1
            } else {
                missingPointCloud.append(descriptor.index)
            }

            if descriptor.isUsable {
                usableIndices.append(descriptor.index)
            }

            if let bbox = descriptor.boundingBox {
                if var existing = aggregateBoundingBox {
                    existing.formUnion(bbox)
                    aggregateBoundingBox = existing
                } else {
                    aggregateBoundingBox = bbox
                }
            }
        }

        let sequence = SampleSequence(
            loader: self,
            indices: usableIndices,
            errorHandler: onSampleFailure
        )

        return Result(
            samples: AnySequence(sequence),
            sampleCount: usableIndices.count,
            depthSampleCount: depthCount,
            missingDepthSampleIDs: missingDepth,
            pointCloudSampleCount: pointCloudCount,
            missingPointCloudSampleIDs: missingPointCloud,
            aggregateBoundingBox: aggregateBoundingBox,
            totalCandidateCount: totalCandidates,
            selectedSampleIDs: selectedIndices,
            droppedSampleIDs: droppedIndices
        )
    }

    private func analyzeSample(for index: Int) throws -> SampleDescriptor {
        let imageURL = fileURL(base: "image", index: index, ext: "jpg")
        let hasImage = fileManager.fileExists(atPath: imageURL.path)

        let metadataDictionary = try loadJSONDictionary(baseName: "metadata", index: index)

        var hasDepth = false
        if let metadataDictionary,
           let depthInfo = auxiliaryDimensions(in: metadataDictionary, matching: "kCGImageAuxiliaryDataTypeDepth") {
            let depthURL = fileURL(base: "depth", index: index, ext: "bin.gz")
            if fileManager.fileExists(atPath: depthURL.path),
               depthInfo.width > 0, depthInfo.height > 0 {
                hasDepth = true
            }
        }

        var hasPointCloud = false
        var boundingBox: BoundingBox?

        if let captureMetadata = try loadCaptureMetadata(index: index),
           let imageEntry = captureMetadata.fileContents.images.first {

            if let bboxData = imageEntry.objectBoundingBox,
               let bbox = BoundingBox(data: bboxData) {
                boundingBox = bbox
            }

            if let pointCloudInfo = imageEntry.pointCloud {
                let pointCloudURL = rootDirectory.appendingPathComponent(pointCloudInfo.fileName)
                if fileManager.fileExists(atPath: pointCloudURL.path) {
                    hasPointCloud = true
                    if let pcBBoxData = pointCloudInfo.boundingBox,
                       let pcBBox = BoundingBox(data: pcBBoxData) {
                        if let current = boundingBox {
                            boundingBox = current.union(pcBBox)
                        } else {
                            boundingBox = pcBBox
                        }
                    }
                }
            }
        }

        return SampleDescriptor(
            index: index,
            hasImage: hasImage,
            hasDepth: hasDepth,
            hasPointCloud: hasPointCloud,
            boundingBox: boundingBox
        )
    }

    private struct SampleSequence: Sequence {
        let loader: PhotogrammetrySampleLoader
        let indices: [Int]
        let errorHandler: SampleErrorHandler?

        func makeIterator() -> Iterator {
            Iterator(loader: loader, indices: indices, errorHandler: errorHandler)
        }

        struct Iterator: IteratorProtocol {
            private var iterator: IndexingIterator<[Int]>
            private let loader: PhotogrammetrySampleLoader
            private let errorHandler: SampleErrorHandler?

            init(loader: PhotogrammetrySampleLoader, indices: [Int], errorHandler: SampleErrorHandler?) {
                self.loader = loader
                self.iterator = indices.makeIterator()
                self.errorHandler = errorHandler
            }

            mutating func next() -> PhotogrammetrySample? {
                while let index = iterator.next() {
                    do {
                        let buildResult = try loader.buildSample(for: index)
                        guard buildResult.hasDepth && buildResult.hasPointCloud else {
                            continue
                        }
                        return buildResult.sample
                    } catch {
                        errorHandler?(index, error)
                    }
                }
                return nil
            }
        }
    }

    private struct SampleBuildResult {
        let sample: PhotogrammetrySample
        let hasDepth: Bool
        let hasPointCloud: Bool
        let boundingBox: BoundingBox?
    }

    private func buildSample(for index: Int) throws -> SampleBuildResult {
        let imageURL = fileURL(base: "image", index: index, ext: "jpg")
        guard fileManager.fileExists(atPath: imageURL.path) else {
            throw LoaderError.missingImage(imageURL)
        }

        let colorBuffer = try makeColorPixelBuffer(from: imageURL)

        var metadataPayload: [String: Any] = [
            "ImageIndex": index,
            "ImageFile": imageURL.lastPathComponent
        ]

        let captureMetadataDictionary = try loadJSONDictionary(baseName: "metadata", index: index)
        if let captureMetadataDictionary {
            metadataPayload["CaptureMetadata"] = captureMetadataDictionary
        }

        let captureMetadataObject = try loadCaptureMetadata(index: index)

        if let tracking = try loadJSONDictionary(baseName: "tracking", index: index) {
            metadataPayload["CameraTrackingState"] = tracking
        }

        if let calibration = try loadJSONDictionary(baseName: "calibration", index: index) {
            metadataPayload["CameraCalibrationData"] = calibration
        }

        if let transform = try loadJSONDictionary(baseName: "transform", index: index) {
            metadataPayload["CameraTransformData"] = transform
        }

        var sample = PhotogrammetrySample(id: index, image: colorBuffer)
        sample.metadata = metadataPayload

        var hasDepth = false

        if let captureMetadataDictionary,
           let depthInfo = auxiliaryDimensions(in: captureMetadataDictionary, matching: "kCGImageAuxiliaryDataTypeDepth"),
           let depthResult = try loadDepthBuffer(index: index, dimensions: depthInfo) {
            sample.depthDataMap = depthResult.buffer
            sample.metadata["DepthFile"] = depthResult.fileName
            sample.metadata["DepthDimensions"] = ["Width": depthInfo.width, "Height": depthInfo.height]
            hasDepth = true
        }

        var hasPointCloud = false
        var sampleBoundingBox: BoundingBox?

        if let metadataObject = captureMetadataObject,
           let imageEntry = metadataObject.fileContents.images.first {

            if let bboxData = imageEntry.objectBoundingBox,
               let bbox = BoundingBox(data: bboxData) {
                sample.metadata["BoundingBoxMin"] = bboxData.min
                sample.metadata["BoundingBoxMax"] = bboxData.max
                sampleBoundingBox = bbox
            }

            if let pointCloudInfo = imageEntry.pointCloud {
                let pointCloudURL = rootDirectory.appendingPathComponent(pointCloudInfo.fileName)
                if fileManager.fileExists(atPath: pointCloudURL.path) {
                    sample.metadata["PointCloudFile"] = pointCloudInfo.fileName
                    sample.metadata["PointCloudCount"] = pointCloudInfo.pointCount
                    hasPointCloud = true
                    if let pcBBoxData = pointCloudInfo.boundingBox,
                       let pcBBox = BoundingBox(data: pcBBoxData) {
                        if let current = sampleBoundingBox {
                            sampleBoundingBox = current.union(pcBBox)
                        } else {
                            sampleBoundingBox = pcBBox
                        }
                    }
                }
            }
        }

        if let captureMetadataDictionary,
           let confidenceInfo = auxiliaryDimensions(in: captureMetadataDictionary, matching: "tag:apple.com,2023:ObjectCapture#DepthConfidenceMap") {
            let confidenceURL = fileURL(base: "confidence", index: index, ext: "bin.gz")
            if fileManager.fileExists(atPath: confidenceURL.path) {
                sample.metadata["DepthConfidenceMap"] = [
                    "File": confidenceURL.lastPathComponent,
                    "Width": confidenceInfo.width,
                    "Height": confidenceInfo.height
                ]
            }
        }

        return SampleBuildResult(
            sample: sample,
            hasDepth: hasDepth,
            hasPointCloud: hasPointCloud,
            boundingBox: sampleBoundingBox
        )
    }

    private func loadDepthBuffer(index: Int, dimensions: (width: Int, height: Int)) throws -> (buffer: CVPixelBuffer, fileName: String)? {
        let depthURL = fileURL(base: "depth", index: index, ext: "bin.gz")
        guard fileManager.fileExists(atPath: depthURL.path) else {
            return nil
        }

        let data = try decompressZlib(at: depthURL)
        let buffer = try makeSingleChannelPixelBuffer(
            data: data,
            width: dimensions.width,
            height: dimensions.height,
            pixelFormat: kCVPixelFormatType_DepthFloat32,
            bytesPerComponent: MemoryLayout<Float32>.size,
            sourceURL: depthURL
        )

        return (buffer, depthURL.lastPathComponent)
    }

    private func makeColorPixelBuffer(from url: URL) throws -> CVPixelBuffer {
        let data = try Data(contentsOf: url)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw LoaderError.imageDecodeFailed(url)
        }

        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw LoaderError.pixelBufferAllocationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw LoaderError.pixelBufferAllocationFailed
        }

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw LoaderError.pixelBufferAllocationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    private func makeSingleChannelPixelBuffer(
        data: Data,
        width: Int,
        height: Int,
        pixelFormat: OSType,
        bytesPerComponent: Int,
        sourceURL: URL
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw LoaderError.pixelBufferAllocationFailed
        }

        let srcBytesPerRow = data.count / max(height, 1)
        let expectedBytesPerRow = width * bytesPerComponent

        guard srcBytesPerRow >= expectedBytesPerRow else {
            throw LoaderError.dataSizeMismatch(sourceURL)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw LoaderError.pixelBufferAllocationFailed
        }

        let destBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        data.withUnsafeBytes { srcPtr in
            guard let srcBase = srcPtr.baseAddress else { return }
            let destination = baseAddress.assumingMemoryBound(to: UInt8.self)

            for row in 0..<height {
                let destRow = destination + row * destBytesPerRow
                let srcRow = srcBase + row * srcBytesPerRow
                memcpy(destRow, srcRow, expectedBytesPerRow)
                if destBytesPerRow > expectedBytesPerRow {
                    memset(destRow + expectedBytesPerRow, 0, destBytesPerRow - expectedBytesPerRow)
                }
            }
        }

        return buffer
    }

    private func loadJSONDictionary(baseName: String, index: Int) throws -> [String: Any]? {
        let url = fileURL(base: baseName, index: index, ext: "json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw LoaderError.jsonDecodingFailed(url)
        }

        return dictionary
    }

    private func loadCaptureMetadata(index: Int) throws -> CaptureMetadata? {
        let url = fileURL(base: "metadata", index: index, ext: "json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(CaptureMetadata.self, from: data)
    }

    private func auxiliaryDimensions(in captureMetadata: [String: Any], matching type: String) -> (width: Int, height: Int)? {
        if let directEntries = captureMetadata["AuxiliaryData"] as? [[String: Any]],
           let dims = findAuxiliary(in: directEntries, matching: type) {
            return dims
        }

        if let fileContents = captureMetadata["{FileContents}"] as? [String: Any],
           let images = fileContents["Images"] as? [[String: Any]] {
            for image in images {
                if let entries = image["AuxiliaryData"] as? [[String: Any]],
                   let dims = findAuxiliary(in: entries, matching: type) {
                    return dims
                }
            }
        }

        return nil
    }

    private func findAuxiliary(in entries: [[String: Any]], matching type: String) -> (width: Int, height: Int)? {
        for entry in entries {
            guard let entryType = entry["AuxiliaryDataType"] as? String,
                  entryType == type,
                  let width = entry["Width"] as? Int,
                  let height = entry["Height"] as? Int else {
                continue
            }
            return (width, height)
        }
        return nil
    }

    private func decompressZlib(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        return try (data as NSData).decompressed(using: .zlib) as Data
    }

    private func fileURL(base: String, index: Int, ext: String) -> URL {
        let filename = String(format: "%@_%06d.%@", base, index, ext)
        return rootDirectory.appendingPathComponent(filename)
    }

    private func parseImageIndex(from name: String) -> Int? {
        guard name.hasPrefix("image_"), name.hasSuffix(".jpg") else { return nil }
        let start = name.index(name.startIndex, offsetBy: 6)
        let end = name.index(name.endIndex, offsetBy: -4)
        let numeric = String(name[start..<end])
        return Int(numeric)
    }
}
