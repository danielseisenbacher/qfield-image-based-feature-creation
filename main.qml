import QtQuick
import QtQuick.Controls
import org.qfield
import org.qgis
import QtQuick.Layouts
import QtCore
import Theme

Item {
  id: plugin
  property var resourceSource
  property var dashBoard: iface.findItemByObjectName('dashBoard')
  property var overlayFeatureFormDrawer: iface.findItemByObjectName('overlayFeatureFormDrawer')
  property string selectedLayer: ""
  property bool isProcessing: false

  function createFeatureFromWKT(wkt, targetLayerName){
    let targetLayer = qgisProject.mapLayersByName(targetLayerName)[0]
    if (!targetLayer) {
      iface.mainWindow().displayToast("No layer called " + targetLayerName + " could be found!")
      return
    }
    let geometry = GeometryUtils.createGeometryFromWkt(wkt)
    let feature = FeatureUtils.createFeature(targetLayer, geometry)
    dashBoard.activeLayer = targetLayer
    overlayFeatureFormDrawer.featureModel.feature = feature
    overlayFeatureFormDrawer.state = "Add"
    overlayFeatureFormDrawer.open()
  }

  function buttonClicked(){
    var filepath = "images/img_" + Date.now() + ".jpg"
    resourceSource = platformUtilities.getGalleryPicture(qgisProject.homePath + '/', filepath, plugin)
    isProcessing = false
  }

  function getImagePath(){
    // Define where to save the selected image
    var prefix = qgisProject.homePath || applicationDirectory
    var pictureFilePath = "images/image_" + Date.now() + ".jpg"
    // Get picture from gallery
    resourceSource = platformUtilities.getGalleryPicture(prefix, pictureFilePath)
    isProcessing = false
  }

  function getLayerNames() {
    // Define Point Layer to insert feature into
    var layerTree = dashBoard.layerTree
    let layerNames = []

    for (let i = 0; i < layerTree.rowCount(); i++) {
      let index = layerTree.index(i, 0)
      layerNames.push(layerTree.data(index, Qt.DisplayRole))
    }
    return layerNames
  }

  ExpressionEvaluator {
    id: expressionEvaluator
    project: qgisProject
  }

  Connections {
    target: resourceSource
    function onResourceReceived(path) {
      if (path) {
        var fullPath = qgisProject.homePath + "/" + path
        expressionEvaluator.expressionText = "geom_to_wkt( make_point( exif('" + fullPath + "' , 'Exif.GPSInfo.GPSLongitude'), exif('" + fullPath + "' , 'Exif.GPSInfo.GPSLatitude')))"
        var result = expressionEvaluator.evaluate()

        // safeguard if no EXIF information
        if (result === "") {
          iface.mainWindow().displayToast(qsTr("No Coordinates provided - no EXIF error"))
          iface.logMessage("No Coordinates provided - no EXIF error: \n"+result)
          iface.logMessage(fullPath)
          return
        }
        createFeatureFromWKT(result, selectedLayer || "Schwammerl")
      }
    }
  }

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
  }

  QfToolButton {
    id: pluginButton
    iconSource: "icon.svg"
    iconColor: Theme.mainColor
    bgcolor: Theme.darkGray
    round: true
    onClicked: {
      if (selectedLayer == ""){
        layerSelectionDialog.open();
      }
      else {
        isProcessing = true
        buttonClicked()
        //getImagePath()
      }
    }
    onPressAndHold: {
      if (!isProcessing) {
        layerSelectionDialog.open();
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
      var layerNames = getLayerNames()
      comboBoxLayers.model = layerNames
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
        model: []  // Initialize with empty array
      }
    }

    onAccepted: {
      selectedLayer = comboBoxLayers.currentText
      iface.mainWindow().displayToast(qsTr("Layer '%1' chosen for image-based feature creation!").arg(comboBoxLayers.currentText));
    }
  }
}
