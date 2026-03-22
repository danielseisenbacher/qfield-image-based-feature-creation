import QtQuick
import QtQuick.Controls
import org.qfield
import org.qgis
import QtQuick.Layouts
import QtCore
import Theme

Item {
  id: plugin
  property var resourceSource: null
  property var dashBoard: iface.findItemByObjectName('dashBoard')
  property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')
  property string selectedLayer: ""
  property bool isProcessing: false
  property bool isConnected: false

  onResourceSourceChanged: {
    iface.logMessage("resourceSource changed to: " + resourceSource)
    if (resourceSource) {
      iface.logMessage("Connecting signal via onResourceSourceChanged")
      resourceSource.resourceReceived.connect(onResourceReceived)
      isConnected = true
      iface.logMessage("Signal connected via property watcher")
    }
  }

  function createFeatureFromWKT(wkt, targetLayerName){
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
    iface.logMessage("Geometry created: " + geometry)
    let feature = FeatureUtils.createFeature(targetLayer, geometry)
    iface.logMessage("Feature created, opening form...")
    dashBoard.activeLayer = targetLayer
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.state = "Add"
    overlayFeatureFormDrawer.open()
    iface.logMessage("Feature form opened")
  }

  function buttonClicked(){
    iface.logMessage("buttonClicked started")

    // Disconnect previous if any
    if (resourceSource && isConnected) {
      iface.logMessage("Disconnecting previous resourceSource connection")
      resourceSource.resourceReceived.disconnect(onResourceReceived)
      isConnected = false
    }

    var filepath = "images/img_" + Date.now() + ".jpg"
    iface.logMessage("Requesting gallery picture, filepath: " + filepath)
    iface.logMessage("Project home path: " + qgisProject.homePath)

    // Assignment triggers onResourceSourceChanged which connects the signal
    resourceSource = platformUtilities.getGalleryPicture(qgisProject.homePath + '/', filepath, plugin)
    iface.logMessage("resourceSource after getGalleryPicture: " + resourceSource)
    isProcessing = false
  }

  function onResourceReceived(path) {
    iface.logMessage("=== onResourceReceived FIRED === path: " + path)

    // Disconnect after receiving
    if (resourceSource && isConnected) {
      iface.logMessage("Disconnecting signal after receive")
      resourceSource.resourceReceived.disconnect(onResourceReceived)
      isConnected = false
    }

    if (!path) {
      iface.logMessage("ERROR: path is empty or null")
      iface.mainWindow().displayToast(qsTr("No image path received"))
      return
    }

    var fullPath = qgisProject.homePath + "/" + path
    iface.logMessage("Full image path: " + fullPath)

    expressionEvaluator.expressionText = "geom_to_wkt( make_point( exif('" + fullPath + "' , 'Exif.GPSInfo.GPSLongitude'), exif('" + fullPath + "' , 'Exif.GPSInfo.GPSLatitude')))"
    iface.logMessage("Expression set, evaluating...")

    var result = expressionEvaluator.evaluate()
    iface.logMessage("Expression result: " + result)

    if (result === "" || result === null || result === undefined) {
      iface.mainWindow().displayToast(qsTr("No Coordinates provided - no EXIF error"))
      iface.logMessage("No Coordinates provided - EXIF result was empty")
      iface.logMessage("Full path used for EXIF: " + fullPath)
      return
    }

    iface.logMessage("Valid result, calling createFeatureFromWKT...")
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
    iface.logMessage("Layer names found: " + layerNames.join(", "))
    return layerNames
  }

  ExpressionEvaluator {
    id: expressionEvaluator
    project: qgisProject
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
      if (selectedLayer == "") {
        iface.logMessage("No layer selected, opening layer selection dialog")
        layerSelectionDialog.open()
      } else {
        iface.logMessage("Layer already selected: " + selectedLayer + ", proceeding to image picker")
        isProcessing = true
        buttonClicked()
      }
    }
    onPressAndHold: {
      iface.logMessage("Button press and hold, isProcessing: " + isProcessing)
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
      iface.mainWindow().displayToast(qsTr("Layer '%1' chosen for image-based feature creation!").arg(comboBoxLayers.currentText))
      iface.logMessage("Proceeding to image picker after layer selection")
      isProcessing = true
      buttonClicked()
    }

    onRejected: {
      iface.logMessage("Layer selection dialog cancelled")
    }
  }
}
