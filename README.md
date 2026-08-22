# Insv Marker Extractor

A lightweight, native Windows utility that extracts timeline markers (highlights) from Insta360 `.insv` and `.lrv` video files. 

This tool circumvents the issue where markers are often locked inside the camera's internal database or chaptered metadata, allowing you to quickly dump out chronological marker timestamps (in `HH:MM:SS` format) for seamless video editing.

## Features
* **Smart Sequence Detection:** Automatically groups chaptered `.insv` files (e.g., `00_001`, `00_002`) and calculates absolute marker times based on the start of the entire recording.
* **Batch Processing:** Supports drag-and-dropping hundreds of files or entire directories at once.
* **Zero Dependencies:** Runs natively via Windows PowerShell and Batch. No Python installation is required.

## Installation

1. Download the latest release `.zip` and extract it to any temporary location.
2. Double-click **`Setup.bat`**.

**What the setup script does:**
To maintain a clean system, this tool utilizes a shadow-install architecture. Upon running `Setup.bat`:
* It creates a dedicated directory at `%LOCALAPPDATA%\Insv_Marker_Extractor`.
* It securely fetches the required metadata parsing dependency (`insvtools`) directly from its official GitHub repository.
* It moves the core scripts into the local app data folder and generates a Desktop shortcut.
* *Note: You can safely delete the extracted installation folder once setup is complete.*

## How to Use

**Do not double-click the shortcut.** The tool operates entirely via drag-and-drop.

1. Select your `.insv` files, `.lrv` files, or an entire folder containing your footage.
2. Drag and drop the selection directly onto the **Insta360 Marker Extractor** shortcut on your Desktop.
3. A console window will appear, process the sequences, and output a clean list of your marker timestamps.

## Dependencies & Credits

This script heavily relies on the excellent [insvtools](https://github.com/alex-plekhanov/insvtools) by `alex-plekhanov` for parsing the raw binary metadata of Insta360 files. 

During installation, the setup script dynamically fetches `insvtools v.1.2` (licensed under Apache License 2.0). Proper licensing documentation is preserved alongside the binary in the installation directory.