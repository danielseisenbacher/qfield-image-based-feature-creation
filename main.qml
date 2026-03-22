import QtQuick
import QtQuick.Controls
import org.qfield
import org.qgis
import QtQuick.Layouts
import QtCore
import Theme
import "qrc:/qml" as QFieldItems

Item {
  id: plugin
  property var dashBoard: iface.findItemByObjectName('dashBoard')
  property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')
  property string selectedLayer: ""
  property bool isProcessing: false

  function createFeatureFromWKT(wkt, targetLayerName) {
    iface.logMessage("createFeatureFromWKT called with layer: " + targetLayerName)
    iface.logMessage("WKT: " + wkt)
    let targetLayer = qgisProject.mapLayersByName(targetLayerName)[0]
    if (!targetLayer) {
      iface.logMessage("ERROR: Layer not found: " + targetLayerName)
      iface.mainWindow().displayToast("No layer called " + targetLayerName + " could be found!")
      return
    }
    iface.logMessage("Layer found, creating geometry...")
    let geometry = GeometryUtils.createGeometryFromWkt(wkt)
    let feature = FeatureUtils.createFeature(targetLayer, geometry)
    iface.logMessage("Feature created, opening form...")
    dashBoard.activeLayer = targetLayer
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.state = "Add"
    overlayFeatureFormDrawer.open()
    iface.logMessage("Feature form opened")
  }

  function processImage(path) {
    iface.logMessage("=== processImage called with path: " + path + " ===")
    if (!path || path === "") {
      iface.logMessage("ERROR: empty path received")
      iface.mainWindow().displayToast(qsTr("No image path received"))
      return
    }

    var fullPath = qgisProject.homePath + "/" + path
    iface.logMessage("Full image path: " + fullPath)

    expressionEvaluator.expressionText = "geom_to_wkt( make_point( exif('" + fullPath + "', 'Exif.GPSInfo.GPSLongitude'), exif('" + fullPath + "', 'Exif.GPSInfo.GPSLatitude')))"
    iface.logMessage("Evaluating EXIF expression...")
    var result = expressionEvaluator.evaluate()
    iface.logMessage("EXIF result: " + result)

    if (!result || result === "") {
      iface.mainWindow().displayToast(qsTr("No Coordinates provided - no EXIF error"))
      iface.logMessage("EXIF result empty for path: " + fullPath)
      return
    }

    iface.logMessage("Calling createFeatureFromWKT...")
    createFeatureFromWKT(result, selectedLayer || "Schwammerl")
  }

  function getLayerNames() {
    iface.logMessage("getLayerNames called")
    var layerTree = dashBoard.layerTree
    let layerNames = []
    for (let i = 0; i < layerTree.rowCount(); i++) {
      let index = layerTree.index(i, 0)
      layerNames.push(layerTree.data(index, Qt.DisplayRole))
    }
    iface.logMessage("Layers found: " + layerNames.join(", "))
    return layerNames
  }

  ExpressionEvaluator {
    id: expressionEvaluator
    project: qgisProject
  }

  // Use a Loader + QFieldCamera as per the official qfield-snap pattern.
  // This avoids the Android Activity lifecycle issue with getGalleryPicture + resourceReceived.
  // Switch to gallery by setting the camera's mode if supported, otherwise
  // we fall back to camera and the user takes a geotagged photo directly.
  Loader {
    id: cameraLoader
    active: false
    sourceComponent: Component {
      QFieldItems.QFieldCamera {
        id: qfieldCamera
        visible: false

        Component.onCompleted: {
          iface.logMessage("QFieldCamera component created, opening...")
          open()
        }

        onFinished: (path) => {
          iface.logMessage("QFieldCamera onFinished, path: " + path)
          close()
          isProcessing = false
          processImage(path)
        }

        onCanceled: {
          iface.logMessage("QFieldCamera canceled")
          close()
          isProcessing = false
        }

        onClosed: {
          iface.logMessage("QFieldCamera closed, deactivating loader")
          cameraLoader.active = false
        }
      }
    }
  }

  Component.onCompleted: {
    iface.logMessage("Plugin loaded successfully")
    iface.addItemToPluginsToolbar(pluginButton)
  }

  QfToolButton {
    id: pluginButton
    iconSource: "icon.svg"
    iconColor: Theme.mainColor
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      iface.logMessage("Plugin button clicked, selectedLayer: " + selectedLayer)
      if (selectedLayer === "") {
        iface.logMessage("No layer selected, opening layer selection dialog")
        layerSelectionDialog.open()
      } else {
        iface.logMessage("Opening camera loader for layer: " + selectedLayer)
        isProcessing = true
        cameraLoader.active = true
      }
    }

    onPressAndHold: {
      iface.logMessage("Button long-pressed, opening layer selection dialog")
      if (!isProcessing) {
        layerSelectionDialog.open()
      }
    }
  }

  Dialog {
    id: layerSelectionDialog
    parent: iface.mainWindow().contentItem
    visible: false
    modal: true
    font: Theme.defaultFont
    standardButtons: Dialog.Ok | Dialog.Cancel
    title: qsTr("Layer Selection")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    onAboutToShow: {
      iface.logMessage("Layer selection dialog opening")
      var layerNames = getLayerNames()
      comboBoxLayers.model = layerNames
      iface.logMessage("ComboBox populated with " + layerNames.length + " layers")
    }

    ColumnLayout {
      spacing: 10
      Label {
        id: labelSelection
        wrapMode: Text.Wrap
        text: qsTr("Layer for Image-based Feature Creation")
        font: Theme.defaultFont
      }
      ComboBox {
        id: comboBoxLayers
        Layout.fillWidth: true
        model: []
      }
    }

    onAccepted: {
      selectedLayer = comboBoxLayers.currentText
      iface.logMessage("Layer selected: " + selectedLayer)
      iface.mainWindow().displayToast(qsTr("Layer '%1' chosen for image-based feature creation!").arg(selectedLayer))
      isProcessing = true
      cameraLoader.active = true
    }

    onRejected: {
      iface.logMessage("Layer selection dialog cancelled")
    }
  }
}
