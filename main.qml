import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.qfield
import org.qgis
import Theme

/**
 * Image based Feature Creation - QField plugin
 *
 * Workflow:
 *  1. Tap the toolbar button (long press to change the target layer).
 *  2. Pick an image. It is copied into the project's "images" folder.
 *  3. The GPS position is read from the image's EXIF metadata, reprojected
 *     into the target layer's CRS, and the "add feature" form opens with
 *     the new point geometry.
 */
Item {
  id: plugin

  readonly property var dashBoard: iface.findItemByObjectName('dashBoard')
  readonly property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')

  // Folder (relative to the project folder) where picked images are copied to
  readonly property string imageFolder: "images"

  // Resource source of the pending picker request, null when idle
  property var resourceSource: null

  // The chosen target layer is remembered across sessions
  Settings {
    id: settings
    category: "qfield-image-based-feature-creation"
    property string layerId: ""
  }

  ExpressionEvaluator {
    id: expressionEvaluator
    project: qgisProject
  }

  // The picker result arrives asynchronously (on Android after the external
  // picker activity returns), so the handler is bound declaratively to
  // whatever resource source is currently pending.
  Connections {
    target: plugin.resourceSource
    function onResourceReceived(path) {
      plugin.resourceSource = null;
      plugin.handleImage(path);
    }
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton);
  }

  function log(message) {
    iface.logMessage("[Image Feature Creator] " + message);
  }

  function toast(message, type) {
    iface.mainWindow().displayToast(message, type);
  }

  function isPointLayer(layer) {
    return layer && typeof layer.geometryType === "function" && layer.geometryType() === Qgis.GeometryType.Point;
  }

  // Returns all point layers of the current project as [{ id, name }], sorted by name
  function pointLayers() {
    const layers = ProjectUtils.mapLayers(qgisProject);
    const result = [];
    for (const id in layers) {
      if (isPointLayer(layers[id])) {
        result.push({
            "id": id,
            "name": layers[id].name
          });
      }
    }
    result.sort((a, b) => a.name.localeCompare(b.name));
    return result;
  }

  // Returns the configured target layer, or null if unset or not in the current project
  function targetLayer() {
    if (settings.layerId === "") {
      return null;
    }
    const layer = qgisProject.mapLayer(settings.layerId);
    return isPointLayer(layer) ? layer : null;
  }

  // Opens the platform's image picker. The result is delivered to handleImage().
  function pickImage() {
    if (!qgisProject || !qgisProject.homePath) {
      toast(qsTr("Please open a project first"), 'warning');
      return;
    }

    platformUtilities.requestStoragePermission();

    const prefix = qgisProject.homePath + '/';
    // {filename} is replaced by QField with the original file name, keeping its extension
    const filePath = imageFolder + '/img_' + Date.now() + '_{filename}';

    if (Qt.platform.os === "android" && typeof platformUtilities.getFile === "function") {
      // Android's gallery picker (the system photo picker) removes the GPS location
      // from EXIF metadata for privacy reasons, so the generic document picker is
      // used instead, which hands over the original file.
      resourceSource = platformUtilities.getFile(prefix, filePath, "image/*", plugin);
    } else {
      resourceSource = platformUtilities.getGalleryPicture(prefix, filePath, plugin);
    }

    if (!resourceSource) {
      // Desktop file dialogs return no resource source when cancelled
      log("Image picker was cancelled or could not be opened");
    }
  }

  // Called with the image path relative to the project folder, or an empty
  // string if the image could not be retrieved.
  function handleImage(path) {
    if (!path) {
      toast(qsTr("No image received"), 'warning');
      return;
    }

    const imagePath = qgisProject.homePath + '/' + path;
    log("Received image: " + imagePath);
    if (!FileUtils.fileExists(imagePath)) {
      toast(qsTr("The selected image could not be copied into the project folder"), 'error');
      return;
    }

    const position = readExifPosition(imagePath);
    if (!position) {
      toast(qsTr("The selected image has no GPS coordinates in its EXIF metadata"), 'warning');
      return;
    }
    log("EXIF position: lon " + position.x + ", lat " + position.y + (isNaN(position.z) ? "" : ", alt " + position.z));

    const layer = targetLayer();
    if (!layer) {
      toast(qsTr("The target layer is no longer available, please choose another one"), 'warning');
      layerSelectionDialog.open();
      return;
    }

    openFeatureForm(layer, position);
  }

  // Reads the GPS position (WGS 84) of an image. Returns { x, y, z } with z being
  // NaN when no altitude is stored, or null if the image has no usable position.
  function readExifPosition(imagePath) {
    // Escape the path the same way QgsExpression::quotedString() does
    const quotedPath = "'" + imagePath.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
    // exif_geotag() takes the N/S and E/W references into account, unlike reading
    // the raw Exif.GPSInfo.GPSLatitude/GPSLongitude tags with exif()
    expressionEvaluator.expressionText = "with_variable('geotag', exif_geotag(" + quotedPath + "), " + "if(@geotag IS NULL, '', concat(x(@geotag), ';', y(@geotag), ';', coalesce(z(@geotag), ''))))";

    const result = expressionEvaluator.evaluate();
    if (result === undefined || result === null || String(result) === "") {
      log("No EXIF geotag found in " + imagePath);
      return null;
    }

    const parts = String(result).split(';');
    const x = parseFloat(parts[0]);
    const y = parseFloat(parts[1]);
    const z = parts.length > 2 && parts[2] !== "" ? parseFloat(parts[2]) : NaN;

    if (!isFinite(x) || !isFinite(y) || Math.abs(x) > 180 || Math.abs(y) > 90) {
      log("Invalid EXIF geotag '" + result + "' in " + imagePath);
      return null;
    }
    if (x === 0 && y === 0) {
      // Some cameras write 0/0 when they had no GPS fix
      log("EXIF geotag is 0/0, treating it as missing");
      return null;
    }
    return {
      "x": x,
      "y": y,
      "z": z
    };
  }

  // Builds a WKT point in the layer's CRS and geometry type (single/multi, Z, M)
  function pointWkt(layer, position) {
    const point = GeometryUtils.reprojectPoint(GeometryUtils.point(position.x, position.y, position.z), CoordinateReferenceSystemUtils.wgs84Crs(), layer.crs);
    if (!point || !isFinite(point.x) || !isFinite(point.y)) {
      return "";
    }

    const type = layer.wkbType();
    const isMulti = [Qgis.WkbType.MultiPoint, Qgis.WkbType.MultiPointZ, Qgis.WkbType.MultiPointM, Qgis.WkbType.MultiPointZM, Qgis.WkbType.MultiPoint25D].includes(type);
    const hasZ = [Qgis.WkbType.PointZ, Qgis.WkbType.PointZM, Qgis.WkbType.Point25D, Qgis.WkbType.MultiPointZ, Qgis.WkbType.MultiPointZM, Qgis.WkbType.MultiPoint25D].includes(type);
    const hasM = [Qgis.WkbType.PointM, Qgis.WkbType.PointZM, Qgis.WkbType.MultiPointM, Qgis.WkbType.MultiPointZM].includes(type);

    let coordinates = point.x + " " + point.y;
    if (hasZ) {
      coordinates += " " + (isFinite(point.z) ? point.z : 0);
    }
    if (hasM) {
      coordinates += " 0";
    }
    const dimension = (hasZ ? "Z" : "") + (hasM ? "M" : "");
    return (isMulti ? "MultiPoint" : "Point") + (dimension ? " " + dimension : "") + (isMulti ? " ((" + coordinates + "))" : " (" + coordinates + ")");
  }

  function openFeatureForm(layer, position) {
    const wkt = pointWkt(layer, position);
    if (wkt === "") {
      toast(qsTr("The image position could not be transformed into the layer's CRS"), 'error');
      return;
    }
    log("Creating feature in '" + layer.name + "' at " + wkt);

    const geometry = GeometryUtils.createGeometryFromWkt(wkt);
    if (!geometry || geometry.isNull) {
      toast(qsTr("Could not create a geometry from the image position"), 'error');
      return;
    }

    // The feature form's model follows the dashboard's active layer
    dashBoard.activeLayer = layer;
    overlayFeatureFormDrawer.featureModel.feature = FeatureUtils.createFeature(layer, geometry);
    overlayFeatureFormDrawer.state = "Add";
    overlayFeatureFormDrawer.open();
  }

  QfToolButton {
    id: pluginButton
    iconSource: "icon.svg"
    iconColor: Theme.mainColor
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      if (plugin.targetLayer()) {
        plugin.pickImage();
      } else {
        layerSelectionDialog.open();
      }
    }
    onPressAndHold: layerSelectionDialog.open()
  }

  Dialog {
    id: layerSelectionDialog
    parent: iface.mainWindow().contentItem
    modal: true
    font: Theme.defaultFont
    title: qsTr("Layer Selection")
    width: Math.min(parent.width - 40, 400)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    standardButtons: comboBoxLayers.count > 0 ? Dialog.Ok | Dialog.Cancel : Dialog.Cancel

    onAboutToShow: {
      const layers = plugin.pointLayers();
      comboBoxLayers.model = layers;
      const currentIndex = layers.findIndex(layer => layer.id === settings.layerId);
      comboBoxLayers.currentIndex = currentIndex >= 0 ? currentIndex : 0;
    }

    onAccepted: {
      const layer = comboBoxLayers.model[comboBoxLayers.currentIndex];
      if (!layer) {
        return;
      }
      settings.layerId = layer.id;
      plugin.toast(qsTr("Layer '%1' chosen for image-based feature creation").arg(layer.name), 'info');
      plugin.pickImage();
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 10

      Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font: Theme.defaultFont
        text: comboBoxLayers.count > 0 ? qsTr("Point layer for image-based feature creation") : qsTr("This project has no point layers.")
      }

      ComboBox {
        id: comboBoxLayers
        Layout.fillWidth: true
        visible: count > 0
        textRole: "name"
        valueRole: "id"
        model: []
      }
    }
  }
}
