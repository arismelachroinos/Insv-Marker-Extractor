# Insv Marker Extractor

A lightweight, native Windows utility that extracts timeline markers (highlights) from Insta360 `.insv` and `.lrv` video files and automatically injects them as keyframes into **Insta360 Studio** (version tested: v6.0.2).

## Features
* **Timestamp Extraction:** Extracts highlight markers in chronological `HH:MM:SS` format.
* **Auto-Keyframing in Insta360 Studio:** Automatically converts marker timestamps into frame coordinates and injects keyframe nodes directly into the `.insprj` project file.
* **Smart Interpolation:** Seamlessly blends auto-generated keyframes with your existing manual keyframes (maintaining your custom pan, tilt, and FOV settings).
* **Smart Sequence Handling:** Groups chaptered `.insv` files (`00_001`, `00_002`) and calculates absolute timeline offsets across the entire recording session.
* **Batch Processing:** Drop single clips, multi-chapter sets, or entire directory trees at once.
* **Native Execution:** Runs natively on Windows using PowerShell and Batch. No Python installation required.

## Installation

1. Download `Insv_Marker_Extractor.zip` from the latest Release and extract it.
2. Double-click **`Setup.bat`**.
3. Once setup completes, an **Insv Marker Extractor** shortcut will be created on your Desktop.

## Usage Instructions

**Do not double-click the shortcut.** The tool operates entirely via drag-and-drop. You can use it in two ways:

### Method 1: Simple Timestamp Extraction
Simply drag and drop your `.insv`/`.lrv` files (or a folder) directly onto the new Desktop shortcut. The console will print the marker timestamps.

### Method 2: Complete Studio Auto-Keyframing
1. Open your footage in **Insta360 Studio**, frame your shots if you want (optionally add manual keyframes to set your preferred camera angles), then close the app (close all of its windows).
2. Drag and drop those same video files onto the Desktop shortcut.
3. The script will inject the markers as keyframes, matching your angles.
4. Re-open **Insta360 Studio**. Double-click your footage in the "Local Media" tab, and your markers will be fully editable keyframes on the timeline.

## Dependencies & Credits
* Uses [insvtools](https://github.com/alex-plekhanov/insvtools) by `alex-plekhanov` (Apache 2.0 License) for low-level metadata extraction.