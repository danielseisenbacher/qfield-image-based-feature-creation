# Image based Feature Creation - QField Plugin

The **Image based Feature Creation** QField Plugin enables taking the EXIF information of an image and creating a feature in a point layer based on the coordinates provided in the metadata.

This plugin enables a delayed approach to field mapping by using image metadata.

## Installation

1. **Download QField:**
   - Install [QField on your device](https://qfield.org/get).

2. **Install Plugin:**
   - See https://docs.qfield.org/how-to/plugins/
   - Using url method:<br>https://github.com/danielseisenbacher/qfield-image-based-feature-creation/releases/download/latest/qfield-image-based-feature-creation-plugin.zip

## Usage

1. Activate the Plugin
2. Configure the point layer to create features in by long pressing the plugin icon (you are asked on first use)
3. Click the icon to choose an image
4. The image is copied into the project's `images` folder, and the feature form opens at the image's GPS position (reprojected into the layer's CRS)
<br><br>

![Teaser](teaser.gif)

## Notes

- **Android:** the Android gallery / photo picker removes the GPS location from images for privacy reasons. That's why the plugin uses the file picker instead. If an image still has no coordinates, don't pick it from Google Photos or "Recent". Browse to it on the device storage instead (usually `DCIM/Camera`), and make sure QField has the "media location" permission.
- Images without GPS coordinates (or with 0/0 coordinates) are rejected with a message.
- Only point layers (single or multi, with or without Z/M) can be selected.

## Contributing

Contributions are welcome!

**Possible improvements:**<br>
- Support for layers other than point layers
- Merging functionality with QField Snap!

## Contact

Contact me via Github Issues...<br>
[GitHub repository](https://github.com/danielseisenbacher/qfield-image-based-feature-creation).
