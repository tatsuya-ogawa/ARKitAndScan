# ARKitAndScan

ARKitAndScan is a demo iOS app that showcases how to combine **ARKit**'s real-time scene reconstruction with the **PhotogrammetrySession** pipeline on macOS/iOS. It demonstrates a dual workflow:

- **Live AR Scanning**: Capture LiDAR-driven mesh data using ARKit, render it with custom Metal shaders (including an outline visualization mode), and archive frames for later processing.
- **Photogrammetry Processing**: Browse captured frame sets, kick off a PhotogrammetrySession, and generate high-detail 3D assets from the recorded imagery.

## Data Capture Approach

This project captures meshes, images, and metadata directly with ARKit while scanning, without using `ObjectCaptureSession`. The AR session provides consistent LiDAR-driven geometry and camera poses, so you can record datasets in real time and later feed them into the photogrammetry pipeline.

## Requirements

- Xcode 16 or later
- iOS 17 device with LiDAR (iPad Pro / iPhone Pro) for AR scanning
- macOS 12+ or iOS 17+ for running PhotogrammetrySession workflows
- Swift 5.9, Metal-enabled GPU

## Project Structure

- `ARKitAndScan/Renderers`: Metal renderer and shaders for live mesh preview.
- `ARKitAndScan/ViewControllers`: UI flow for AR scanning and photogrammetry management.
- `ARKitAndScan/DataCapture`: Frame capture and storage helpers.
- `ARKitAndScan/Models`: Data structures that bridge ARMesh anchors and Metal buffers.

## Getting Started

1. Open `ARKitAndScan.xcodeproj` in Xcode.
2. Build & run on a LiDAR-capable iOS device for the AR scanning experience.
3. Use the Photogrammetry tab (Catalyst/macOS or iOS 17+) to process a captured session into a mesh.

## Key Features

- Real-time AR mesh visualization with edge-aware Metal shading.
- Frame capture pipeline that archives color, depth, and metadata for photogrammetry input.
- Photogrammetry UI for selecting captures, monitoring progress, and inspecting generated models.

## License

This project is provided as-is for demo and educational purposes. Refer to individual files for additional notices.
