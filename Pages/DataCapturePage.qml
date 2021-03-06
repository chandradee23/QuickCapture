/* Copyright 2018 Esri
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import QtQuick 2.9
import QtQuick.Layouts 1.3
import QtQuick.Controls 1.4 as Legacy
import QtQuick.Controls 2.2
import QtPositioning 5.8
import QtLocation 5.9
import QtMultimedia 5.9
import QtGraphicalEffects 1.0

import ArcGIS.AppFramework 1.0
import ArcGIS.AppFramework.Sql 1.0
import ArcGIS.AppFramework.Speech 1.0
import ArcGIS.AppFramework.Notifications 1.0
import ArcGIS.AppFramework.Networking 1.0

PageView {
    id: page

    //--------------------------------------------------------------------------

    property Config config: app.config

    property DataService dataService
    property bool online
    property var coordinate: QtPositioning.coordinate()
    property color coordinateColor: theme.textColor
    property real horizontalAccuracy
    property var lastInsertId
    property var currentPosition

    property bool showPreview: (showMap && coordinate.isValid) || featureButtonsPanel.useCamera
    property bool showMap: false

    property real directionSpeedThreshold: 0.5

    property color accuracyGoodColor: "green"
    property color accuracyAlertColor: "#FFBF00"
    property color accuracyPoorColor: "red"

    property real accuracyGoodThreshold: 10
    property real accuracyAlertThreshold: 100

    property string coordinateFormat: "ddm"

    //--------------------------------------------------------------------------

    title: dataService.itemInfo.title

    //--------------------------------------------------------------------------

    Component.onCompleted: {
        var options = dataService.parseOptions(dataService.itemInfo.accessInformation);

        console.log("Project options:", JSON.stringify(options, undefined, 2));

        if (options.showMap) {
            showMap = options.showMap;
        }

        if (options.columns) {
            featureButtonsPanel.columns = options.columns;
        }

        if (options.columnSpacing) {
            featureButtonsPanel.columnSpacing = options.columnSoacing * AppFramework.displayScaleFactor;
        }

        if (options.rowSpacing) {
            featureButtonsPanel.rowSpacing = options.rowSoacing * AppFramework.displayScaleFactor;
        }

        if (options.backgroundColor) {
            backgroundFill.color = options.backgroundColor;
        }

        if (options.coordinateFormat > "") {
            coordinateFormat = options.coordinateFormat.toLowerCase();
        }


        AppFramework.environment.setValue("APPSTUDIO_POSITION_DESIRED_ACCURACY", "HIGHEST");
        AppFramework.environment.setValue("APPSTUDIO_POSITION_ACTIVITY_MODE", "OTHERNAVIGATION");

        positionSource.active = true;

        if (featureButtonsPanel.useCamera) {
            camera.cameraState = Camera.ActiveState;
        }

        page.forceActiveFocus();
    }

    //--------------------------------------------------------------------------

    onTitlePressAndHold: {
        featureButtonsPanel.showKeys = !featureButtonsPanel.showKeys;
    }

    //--------------------------------------------------------------------------

    PositionSource {
        id: positionSource

        active: false

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                currentPosition = position;

                coordinate = position.coordinate;
                horizontalAccuracy = Math.round(position.horizontalAccuracy);
                if (horizontalAccuracy <= accuracyGoodThreshold) {
                    coordinateColor = accuracyGoodColor;
                } else if (horizontalAccuracy <= accuracyAlertThreshold) {
                    coordinateColor = accuracyAlertColor;
                } else {
                    coordinateColor = accuracyPoorColor;
                }

                map.center = coordinate;

                if (position.speedValid && position.directionValid && position.speed >= directionSpeedThreshold) {
                    map.bearing = position.direction;
                } else {
                    map.bearing = 0;
                }
            } else {
                coordinateColor = theme.errorTextColor;
            }
        }
    }

    //--------------------------------------------------------------------------

    Item {
        parent: page.actionItem
        anchors.fill: parent


        Item {
            anchors.fill: parent

            opacity: dataService.points > 0 ? 1 : 0.3
            visible: !dataService.uploading

            Image {
                id: uploadImage

                anchors.fill: parent
                visible: false

                source: "images/upload-data.png"
                fillMode: Image.PreserveAspectFit
                verticalAlignment: Image.AlignTop
            }

            ColorOverlay {
                anchors.fill: uploadImage
                color: dataService.uploading ? "#00b2ff" : theme.pageHeaderTextColor
                source: uploadImage
            }

            Text {
                anchors.fill: parent

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignBottom

                text: "%1".arg(dataService.points)
                color: theme.pageHeaderTextColor
                font {
                    pointSize: 10
                }
            }

            MouseArea {
                anchors.fill: parent

                enabled: !portal.busy && !dataService.uploading && dataService.points > 0

                onClicked: {
                    upload();
                }
            }
        }

        Item {
            anchors.fill: parent

            visible: dataService.uploading

            Legacy.BusyIndicator {
                anchors.fill: parent
                running: dataService.uploading
            }

            Text {
                anchors.fill: parent

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                text: "%1".arg(dataService.points)
                color: theme.pageHeaderTextColor
                font {
                    pointSize: 10
                }
            }
        }
    }

    //--------------------------------------------------------------------------

    Rectangle {
        id: backgroundFill

        anchors {
            fill: parent
        }

        //color: "#fefefe"
        color: "silver"
    }

    //--------------------------------------------------------------------------

    ColumnLayout {
        anchors {
            fill: parent
            margins: 5 * AppFramework.displayScaleFactor
        }

        spacing: 10 * AppFramework.displayScaleFactor

        ScrollView {
            id: scrollView

            Layout.fillWidth: true
            Layout.fillHeight: true

            clip: true

            FeatureButtonsPanel {
                id: featureButtonsPanel

                width: scrollView.width

                dataService: page.dataService
                background: backgroundFill
                currentPosition: page.currentPosition
                tagAvailable: dataService.tag > ""

                onAddPointFeature: {
                    var properties = {
                        position: positionSource.position,
                        startDateTime: positionSource.position.timestamp,
                        endDateTime: positionSource.position.timestamp
                    }

                    if ( featureButton.options.captureImage) {
                        camera.captureImage(featureButton, properties);
                    } else {
                        addPoint(featureButton, properties);
                    }
                }

                onBeginPolyFeature: {
                    captureBeginNotification(template);
                }

                onEndPolyFeature: {
                    captureEndNotification(template);
                }
            }
        }
    }

    //--------------------------------------------------------------------------

    footer: Rectangle {
        height: childrenRect.height + footerLayout.anchors.margins * 2

        color: theme.pageHeaderColor

        //--------------------------------------------------------------------------

        ColumnLayout {
            id: footerLayout

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 5 * AppFramework.displayScaleFactor
            }

            ColumnLayout {
                Layout.fillWidth: true

                visible: featureButtonsPanel.showTag

                Text {
                    Layout.fillWidth: true

                    visible: !tagInput.visible

                    text: qsTr("Tag <b>%1</b>").arg(dataService.tag)
                    font {
                        pointSize: 16
                    }
                    color: theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere

                    MouseArea {
                        anchors.fill: parent

                        onClicked: {
                            tagInput.visible = true;
                        }
                    }
                }

                RowLayout {
                    id: tagInput

                    Layout.fillWidth: true

                    visible: !dataService.tag

                    Label {
                        text: qsTr("Tag")
                        color: theme.textColor
                    }

                    TextField {
                        Layout.fillWidth: true

                        placeholderText: qsTr("Enter a tag value")
                        text: dataService.tag || ""

                        onTextChanged: {
                            tagInput.visible = true;
                            var value = text.trim();
                            dataService.tag = value > "" ? value : null;
                        }

                        onEditingFinished: {
                            if (text.trim() > "") {
                                tagInput.visible = false;
                                page.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            RowLayout {
                id: previewLayout

                Layout.fillWidth: true
                Layout.preferredHeight: 100 * AppFramework.displayScaleFactor

                visible: showPreview

                Map {
                    id: map

                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    visible: Networking.isOnline && showMap && coordinate.isValid

                    plugin: Plugin {
                        preferred: ["AppStudio"]
                    }

                    zoomLevel: 18

                    gesture {
                        acceptedGestures: MapGestureArea.PinchGesture
                    }

                    //activeMapType: supportedMapTypes[0]

                    onCopyrightLinkActivated: {
                        Qt.openUrlExternally(link);
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width / 2
                        height: 1
                        color: "black"
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: parent.height / 2
                        color: "black"
                    }

                    Rectangle {
                        anchors.fill: parent

                        color: "transparent"
                        border {
                            width: 1
                            color: "black"
                        }
                    }
                }

                Item {
                    Layout.preferredWidth: previewLayout.width / 3
                    Layout.fillHeight: true

                    visible: featureButtonsPanel.useCamera

                    VideoOutput {
                        anchors.fill: parent

                        source: camera
                        fillMode: VideoOutput.PreserveAspectFit
                        autoOrientation: true
                    }
                }
            }

            Text {
                Layout.fillWidth: true

                // ⇔ ⇕ ±
                text: formatCoordinate(coordinate, horizontalAccuracy)
                color: coordinateColor
                font {
                    pointSize: 14
                }
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent

                    onPressAndHold: {
                        showMap = !showMap;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                DelayButton {
                    Layout.fillWidth: true

                    enabled: lastInsertId > 0
                    delay: 500
                    text: qsTr("Press and hold to delete last capture")

                    onActivated: {
                        dataService.deleteRow(lastInsertId);
                        lastInsertId = undefined;
                        deleteAudio.play();
                    }
                }
            }
        }
    }

    //--------------------------------------------------------------------------

    Audio {
        id: captureAudio

        source: "audio/capture.mp3"
    }

    Audio {
        id: deleteAudio

        source: "audio/delete.mp3"
    }

    TextToSpeech {
        id: textToSpeech
    }

    //--------------------------------------------------------------------------

    Connections {
        target: dataService

        onUploaded: {
        }
    }

    Connections {
        target: dataService.portal

        onSignedInChanged: {
            if (dataService.portal.signedIn) {
                upload();
            }
        }
    }

    //--------------------------------------------------------------------------

    FeatureCamera {
        id: camera

        dataService: page.dataService
    }

    //--------------------------------------------------------------------------

    function addPoint(featureButton, properties, attachmentPath) {

        lastInsertId = dataService.insertPointFeature(
                    properties,
                    featureButton.layerId,
                    featureButton.template.prototype.attributes,
                    attachmentPath);

        capturePointNotification(featureButton.template);
    }

    //--------------------------------------------------------------------------

    function upload() {
        if (!dataService.portal.signedIn) {
            dataService.portal.autoSignIn();
            return;
        }

        dataService.upload();
    }

    //--------------------------------------------------------------------------

    function captureNotification(text) {
        if (config.captureVibrate) {
            Vibration.vibrate();
        }

        switch (config.captureSound) {
        case config.kSoundBeep :
            captureAudio.play();
            break;

        case config.kSoundTextToSpeech :
            textToSpeech.say(text);
            break;
        }
    }

    //--------------------------------------------------------------------------

    function capturePointNotification(template) {
        captureNotification(template.name);
    }

    //--------------------------------------------------------------------------

    function captureBeginNotification(template) {
        captureNotification(qsTr("Starting %1").arg(template.name));
    }

    //--------------------------------------------------------------------------

    function captureEndNotification(template) {
        captureNotification(qsTr("End %1").arg(template.name));
    }

    //--------------------------------------------------------------------------

    function formatCoordinate(coordinate, horizontalAccuracy) {
        if (!coordinate.isValid) {
            return qsTr("<b>Location not available</b>");
        }

        // ⇔ ⇕ ±
        var text;

        switch (coordinateFormat) {
        case "mgrs":
            var mgrs = Coordinate.convert(coordinate, "mgrs").mgrs;
            text = "MGRS <b>%1</b>".arg(mgrs.text);
            break;

        case "usng":
            var usngOptions = {
                spaces: true,
                precision: 10
            }

            var usng = Coordinate.convert(coordinate, "mgrs", usngOptions).mgrs;
            text = "USNG <b>%1</b>".arg(usng.text);
            break;

        case "utm":
        case "utmups":
        case "ups":
            var universalGrid = Coordinate.convert(coordinate, "universalGrid").universalGrid;
            text = "%1 <b>%2%3</b> <b>%4E</b> <b>%5N</b>"
            .arg(universalGrid.type)
            .arg(universalGrid.zone ? universalGrid.zone : "")
            .arg(universalGrid.band)
            .arg(Math.floor(universalGrid.easting).toString())
            .arg(Math.floor(universalGrid.northing).toString());
            break;

        case "dd":
            var dd = Coordinate.convert(coordinate, "dd").dd;
            text = qsTr("Lat <b>%1</b> Lon <b>%2</b>").arg(dd.latitudeText).arg(dd.longitudeText)
            break;

        case "dms":
            var dms = Coordinate.convert(coordinate, "dms").dms;
            text = qsTr("Lat <b>%1</b> Lon <b>%2</b>").arg(dms.latitudeText).arg(dms.longitudeText)
            break;

        case "ddm":
        default:
            var ddm = Coordinate.convert(coordinate, "ddm").ddm;
            text = qsTr("Lat <b>%1</b> Lon <b>%2</b>").arg(ddm.latitudeText).arg(ddm.longitudeText)
            break;
        }

        if (isFinite(horizontalAccuracy) && horizontalAccuracy > 0) {
            text += " ± <b>%1</b> m".arg(horizontalAccuracy);
        }

        return text;
    }

    //--------------------------------------------------------------------------

    Timer {
        running: config.autoUpload && Networking.isOnline
        interval: config.autoUploadInterval * 1000
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            console.log("Auto upload triggered #points:",dataService.points);
            if (!portal.busy && !dataService.uploading && dataService.points > 0) {
                upload();
            }
        }
    }

    //--------------------------------------------------------------------------

    Keys.onPressed: {
        if (event.key) {
            console.log("onPressed key:", event.key, event.key.toString(16), "modifiers:", event.modifiers, event.modifiers.toString(16));

            featureButtonsPanel.keyPressed(event);
        }
    }

    //--------------------------------------------------------------------------
}

