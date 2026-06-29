import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis

Item {
    id: filterToolRoot

    // === ПРОПЕРТИ ===
    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    property var featureFormItem: iface.findItemByObjectName("featureForm")
    property var dashBoard: iface.findItemByObjectName('dashBoard')

    property var selectedLayer: null
    property bool filterActive: false
    property bool isFormVisible: false
    property bool showFeatureList: false   // новый чекбокс

    property var conditionsModel: ListModel {}
    property string savedLayerName: ""
    property string savedExpr: ""

    // Для списка объектов
    property var pendingFormLayer: null
    property string pendingFormExpr: ""
    property bool useListOffset: false
    property bool isReturnAction: false

    property color highlightColor: "#80cc28"
    property color origProjectColor: "yellow"
    property var highlightItem: null
    property color origFocusColor: "#ff7777"
    property color origSelectedColor: Theme.mainColor
    property color origBaseColor: "yellow"
    property color targetFocusColor: "#D500F9"
    property color targetSelectedColor: "#23FF0A"

    // === ТАЙМЕРЫ ДЛЯ СПИСКА ===
    Timer {
        id: openListTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (featureFormItem && pendingFormLayer && pendingFormExpr) {
                try {
                    featureFormItem.model.setFeatures(pendingFormLayer, pendingFormExpr)
                    if (featureFormItem.extentController) featureFormItem.extentController.autoZoom = true
                    featureFormItem.show()
                    pendingFormLayer = null
                    pendingFormExpr = ""
                } catch(e) {
                    console.error("Error opening list:", e)
                }
            }
        }
    }

    Timer {
        id: zoomTimer
        interval: 200
        repeat: false
        onTriggered: performZoom()
    }

    // === ИНИЦИАЛИЗАЦИЯ ===
    Component.onCompleted: {
        iface.addItemToPluginsToolbar(toolbarButton)
        updateLayers()
        if (featureFormItem) isFormVisible = featureFormItem.visible
        if (qgisProject) origProjectColor = qgisProject.selectionColor

        // Сохраняем оригинальные цвета выделения
        var container = iface.findItemByObjectName("mapCanvasContainer")
        if (container) findHighlighterRecursive(container)
        applyCustomColors()
    }

    // === ПОИСК ЭЛЕМЕНТА ПОДСВЕТКИ ДЛЯ ЦВЕТОВ ===
    function findHighlighterRecursive(parentItem) {
        if (!parentItem) return null
        var kids = parentItem.data
        if (!kids) return null
        for (var i = 0; i < kids.length; i++) {
            var item = kids[i]
            if (item && item.hasOwnProperty("focusedColor") && item.hasOwnProperty("selectedColor")) {
                if (!item.hasOwnProperty("showSelectedOnly") || item.showSelectedOnly === false) {
                    highlightItem = item
                    origFocusColor = item.focusedColor
                    origSelectedColor = item.selectedColor
                    if (item.hasOwnProperty("color")) origBaseColor = item.color
                    return item
                }
            }
            var found = findHighlighterRecursive(item)
            if (found) return found
        }
        return null
    }

    function applyCustomColors() {
        if (!highlightItem) {
            var container = iface.findItemByObjectName("mapCanvasContainer")
            if (container) findHighlighterRecursive(container)
        }
        if (highlightItem) {
            highlightItem.focusedColor = targetFocusColor
            highlightItem.selectedColor = targetSelectedColor
            if (highlightItem.hasOwnProperty("color")) highlightItem.color = targetSelectedColor
        }
        if (qgisProject) qgisProject.selectionColor = targetSelectedColor
        if (mapCanvas) mapCanvas.refresh()
    }

    function restoreOriginalColors() {
        if (highlightItem) {
            highlightItem.focusedColor = origFocusColor
            highlightItem.selectedColor = origSelectedColor
            if (highlightItem.hasOwnProperty("color")) highlightItem.color = origBaseColor
        }
        if (qgisProject) qgisProject.selectionColor = origProjectColor
        if (mapCanvas) mapCanvas.refresh()
    }

    // === КНОПКА НА ПАНЕЛИ ===
    QfToolButton {
        id: toolbarButton
        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true
        onClicked: openFilterUI()
        onPressAndHold: {
            removeAllFilters()
            mainWindow.displayToast(tr("Filter deleted"))
        }
    }

    // === ФУНКЦИИ ===
    function openFilterUI() {
        updateLayers()
        searchDialog.open()
    }

    function addCondition() {
        if (!selectedLayer) {
            mainWindow.displayToast(tr("Please select a layer first"))
            return
        }
        conditionsModel.append({
            field: "",
            operator: "=",
            value: "",
            join: "AND"
        })
        updateApplyState()
    }

    function removeCondition(index) {
        if (index >= 0 && index < conditionsModel.count) {
            conditionsModel.remove(index)
            updateApplyState()
            if (filterActive) {
                applyFilterToLayer()
            }
        }
    }

    function getFieldNames(layer) {
        if (!layer) return []
        var fields = layer.fields
        if (!fields) return []
        var names = []
        var count = (typeof fields.count === 'function') ? fields.count() : 0
        if (count > 0) {
            for (var i = 0; i < count; i++) {
                var field = fields.field(i)
                if (field) names.push(field.name)
            }
        } else if (fields.names) {
            names = fields.names.slice()
        }
        var unique = []
        for (var j = 0; j < names.length; j++) {
            if (unique.indexOf(names[j]) === -1) unique.push(names[j])
        }
        return unique.sort()
    }

    function buildFilterExpression() {
        if (!selectedLayer || conditionsModel.count === 0) return ""

        var exprParts = []
        for (var i = 0; i < conditionsModel.count; i++) {
            var cond = conditionsModel.get(i)
            if (!cond.field || !cond.value || cond.value.trim() === "") continue

            var fieldName = cond.field
            var operator = cond.operator
            var value = cond.value
            var escapedValue = value.replace(/'/g, "''")

            var part = ""
            if (operator === "LIKE" || operator === "ILIKE") {
                part = '"' + fieldName + '" ' + operator + ' \'%' + escapedValue + '%\''
            } else {
                if (!isNaN(value) && value.trim() !== "") {
                    part = '"' + fieldName + '" ' + operator + ' ' + value
                } else {
                    part = '"' + fieldName + '" ' + operator + ' \'' + escapedValue + '\''
                }
            }
            if (part) exprParts.push(part)
        }

        if (exprParts.length === 0) return ""

        var result = exprParts[0]
        for (var j = 1; j < exprParts.length; j++) {
            var join = (j < conditionsModel.count) ? conditionsModel.get(j).join : "AND"
            result += " " + join + " " + exprParts[j]
        }
        return result
    }

    function applyFilterToLayer() {
        if (!selectedLayer) return
        var expr = buildFilterExpression()
        savedExpr = expr
        console.log("Filter expression:", expr)

        try {
            if (expr) {
                // Устанавливаем подзапрос (фильтр отображения)
                selectedLayer.subsetString = expr
                // Выделяем объекты
                selectedLayer.removeSelection()
                selectedLayer.selectByExpression(expr)
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
                filterActive = true
                savedLayerName = selectedLayer.name
                if (infoBanner) infoBanner.visible = true
                mainWindow.displayToast(tr("Filter applied: ") + conditionsModel.count + tr(" conditions"))

                // Если включен показ списка, открываем его
                if (showFeatureList && featureFormItem) {
                    pendingFormLayer = selectedLayer
                    pendingFormExpr = expr
                    openListTimer.restart()
                }
            } else {
                // Снимаем фильтр
                selectedLayer.subsetString = ""
                selectedLayer.removeSelection()
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
                filterActive = false
                savedLayerName = ""
                savedExpr = ""
                if (infoBanner) infoBanner.visible = false
                mainWindow.displayToast(tr("Filter cleared"))
                // Закрываем список, если открыт
                if (featureFormItem) featureFormItem.state = "Hidden"
            }
        } catch (e) {
            console.error("Filter error: " + e)
            mainWindow.displayToast(tr("Filter error: ") + e)
        }
    }

    function applyFilter() {
        applyFilterToLayer()
        searchDialog.close()
    }

    function removeAllFilters() {
        var layers = ProjectUtils.mapLayers(qgisProject)
        for (var id in layers) {
            var pl = layers[id]
            if (pl && pl.type === 0) {
                try {
                    pl.subsetString = ""
                    pl.removeSelection()
                    pl.triggerRepaint()
                } catch (_) {}
            }
        }

        filterActive = false
        savedLayerName = ""
        savedExpr = ""
        conditionsModel.clear()
        showFeatureList = false
        if (showListCheck) showListCheck.checked = false

        if (featureFormItem) featureFormItem.state = "Hidden"

        mapCanvas.refresh()
        updateLayers()
        updateApplyState()
        if (infoBanner) infoBanner.visible = false
        mainWindow.displayToast(tr("Filter deleted"))
    }

    function updateLayers() {
        var layers = ProjectUtils.mapLayers(qgisProject)
        var names = []
        for (var id in layers) {
            var layer = layers[id]
            if (layer && layer.type === 0) {
                names.push(layer.name)
            }
        }
        names.sort()
        names.unshift(tr("Select a layer"))
        if (layerSelector) {
            layerSelector.model = names
            if (selectedLayer) {
                var idx = names.indexOf(selectedLayer.name)
                layerSelector.currentIndex = (idx !== -1) ? idx : 0
            } else {
                layerSelector.currentIndex = 0
            }
        }
    }

    function getLayerByName(name) {
        var layers = ProjectUtils.mapLayers(qgisProject)
        for (var id in layers) {
            if (layers[id].name === name) return layers[id]
        }
        return null
    }

    function updateApplyState() {
        if (applyButton) {
            var hasValid = false
            for (var i = 0; i < conditionsModel.count; i++) {
                var cond = conditionsModel.get(i)
                if (cond.field && cond.value && cond.value.trim() !== "") {
                    hasValid = true
                    break
                }
            }
            applyButton.enabled = selectedLayer !== null && hasValid
        }
        if (addConditionButton) {
            addConditionButton.visible = conditionsModel.count < 10
        }
    }

    // === ЗУМ НА ВЫБРАННЫЙ ОБЪЕКТ ===
    function performZoom() {
        if (!selectedLayer) return
        var bbox = selectedLayer.boundingBoxOfSelected()
        if (!bbox || bbox.xMinimum > bbox.xMaximum) {
            var features = selectedLayer.selectedFeatures()
            if (features && features.length > 0 && features[0].geometry) {
                bbox = features[0].geometry.boundingBox
            }
        }
        if (!bbox) return

        // Увеличиваем чуть-чуть для отступа
        var margin = 1.25
        var cx = (bbox.xMinimum + bbox.xMaximum) / 2
        var cy = (bbox.yMinimum + bbox.yMaximum) / 2
        var w = (bbox.xMaximum - bbox.xMinimum) * margin
        var h = (bbox.yMaximum - bbox.yMinimum) * margin
        if (w < 0.001) w = 0.001
        if (h < 0.001) h = 0.001

        var finalExtent = {
            xMinimum: cx - w/2,
            xMaximum: cx + w/2,
            yMinimum: cy - h/2,
            yMaximum: cy + h/2
        }

        try {
            var destCrs = mapCanvas.mapSettings.destinationCrs
            var rect = GeometryUtils.reprojectRectangle(
                bbox,
                selectedLayer.crs,
                destCrs
            )
            if (rect) {
                var cx2 = (rect.xMinimum + rect.xMaximum) / 2
                var cy2 = (rect.yMinimum + rect.yMaximum) / 2
                var w2 = (rect.xMaximum - rect.xMinimum) * margin
                var h2 = (rect.yMaximum - rect.yMinimum) * margin
                if (w2 < 0.001) w2 = 0.001
                if (h2 < 0.001) h2 = 0.001

                var extent = {
                    xMinimum: cx2 - w2/2,
                    xMaximum: cx2 + w2/2,
                    yMinimum: cy2 - h2/2,
                    yMaximum: cy2 + h2/2
                }
                mapCanvas.mapSettings.setExtent(extent, true)
                mapCanvas.refresh()
            }
        } catch (e) {
            console.error("Zoom error:", e)
        }
    }

    function tr(text) {
        var isFr = Qt.locale().name.substring(0, 2) === "fr"
        var dic = {
            "Filter deleted": "Фильтр удалён",
            "Filter applied: ": "Фильтр применён: ",
            " conditions": " условий",
            "Filter cleared": "Фильтр снят",
            "Filter error: ": "Ошибка фильтра: ",
            "Select a layer": "Выберите слой",
            "Select a field": "Выберите поле",
            "Operator": "Оператор",
            "Value": "Значение",
            "Add condition": "Добавить условие",
            "Apply filter": "Применить фильтр",
            "Delete filter": "Удалить фильтр",
            "Please select a layer first": "Сначала выберите слой",
            "Show feature list": "Показать список объектов"
        }
        return isFr && dic[text] ? dic[text] : (dic[text] || text)
    }

    // === КОМПОНЕНТ СТРОКИ УСЛОВИЯ (делегат) ===
    Component {
        id: conditionRowDelegate

        RowLayout {
            id: row
            required property int index
            required property var modelData

            Layout.fillWidth: true
            spacing: 4

            // JOIN
            QfComboBox {
                id: joinCombo
                Layout.preferredWidth: 55
                Layout.preferredHeight: 32
                model: ["AND", "OR"]
                currentIndex: modelData.join === "AND" ? 0 : 1
                visible: index > 0
                onCurrentTextChanged: {
                    filterToolRoot.conditionsModel.setProperty(index, "join", currentText)
                    updateApplyState()
                }
            }

            // Поле
            QfComboBox {
                id: fieldCombo
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                model: getFieldNames(selectedLayer)
                Component.onCompleted: {
                    var idx = model.indexOf(modelData.field)
                    currentIndex = (idx !== -1) ? idx : 0
                }
                onCurrentTextChanged: {
                    filterToolRoot.conditionsModel.setProperty(index, "field", currentText)
                    updateApplyState()
                }
            }

            // Оператор
            QfComboBox {
                id: operatorCombo
                Layout.preferredWidth: 65
                Layout.preferredHeight: 32
                model: ["=", "!=", "<", ">", "<=", ">=", "LIKE", "ILIKE"]
                currentIndex: {
                    var idx = model.indexOf(modelData.operator)
                    return (idx !== -1) ? idx : 0
                }
                onCurrentTextChanged: {
                    filterToolRoot.conditionsModel.setProperty(index, "operator", currentText)
                    updateApplyState()
                }
            }

            // Значение
            TextField {
                id: valueField
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                placeholderText: qsTr("Value")
                text: modelData.value
                onTextChanged: {
                    filterToolRoot.conditionsModel.setProperty(index, "value", text)
                    updateApplyState()
                }
            }

            // Кнопка удаления
            Button {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                text: "✕"
                background: Rectangle { color: "#ff4444"; radius: 4 }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    removeCondition(index)
                }
            }
        }
    }

    // === БАННЕР ===
    Rectangle {
        id: infoBanner
        parent: mapCanvas
        z: 9999
        height: 38
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(bannerLayout.implicitWidth + 30, parent.width - 120)
        radius: 19
        color: "#B3333333"
        visible: filterToolRoot.filterActive && !filterToolRoot.isFormVisible

        RowLayout {
            id: bannerLayout
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            spacing: 10

            Rectangle {
                width: 8; height: 8; radius: 4
                color: highlightColor
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                id: clipContainer
                Layout.preferredWidth: bannerText.contentWidth
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    id: bannerText
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.NativeRendering
                    text: {
                        if (!filterToolRoot.savedExpr) return tr("Filter active")
                        var displayText = filterToolRoot.savedLayerName + " | " + filterToolRoot.savedExpr
                        if (displayText.length > 40) displayText = displayText.substring(0, 37) + "..."
                        return displayText
                    }
                    color: "white"
                    font.bold: true
                    font.pixelSize: 14
                    wrapMode: Text.NoWrap
                    horizontalAlignment: Text.AlignLeft

                    x: 0
                    SequentialAnimation on x {
                        running: clipContainer && bannerText.contentWidth > clipContainer.width && infoBanner.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: 2000 }
                        NumberAnimation { to: (clipContainer ? clipContainer.width : 0) - bannerText.contentWidth; duration: 4000; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 1000 }
                        NumberAnimation { to: 0; duration: 4000; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }

    // === ДИАЛОГ ===
    Dialog {
        id: searchDialog
        parent: mainWindow.contentItem
        modal: true
        width: Math.min(500, mainWindow.width * 0.92)
        height: mainCol.implicitHeight + 30
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2 - (parent.height > parent.width ? parent.height*0.1 : 0)
        background: Rectangle {
            color: "white"
            border.color: "#80cc28"
            border.width: 3
            radius: 8
        }
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: mouse.accepted = false
        }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            Label {
                text: tr("Select a layer")
                font.bold: true
                font.pointSize: 12
            }

            QfComboBox {
                id: layerSelector
                Layout.fillWidth: true
                Layout.preferredHeight: 35
                model: []
                onCurrentTextChanged: {
                    if (currentText === tr("Select a layer")) {
                        selectedLayer = null
                        conditionsModel.clear()
                        updateApplyState()
                        return
                    }
                    var layer = getLayerByName(currentText)
                    if (layer) {
                        selectedLayer = layer
                        conditionsModel.clear()
                        if (filterActive) {
                            applyFilterToLayer()
                        }
                        updateApplyState()
                    } else {
                        console.warn("Layer not found:", currentText)
                    }
                }
            }

            // === КОНТЕЙНЕР УСЛОВИЙ с Repeater ===
            ScrollView {
                id: conditionsScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, conditionsModel.count * 75 + 10)
                Layout.minimumHeight: 60
                clip: true

                ColumnLayout {
                    id: conditionsContainer
                    width: parent.width - 10
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.minimumHeight: 60

                    Repeater {
                        model: conditionsModel
                        delegate: conditionRowDelegate
                    }
                }
            }

            // === КНОПКА "ДОБАВИТЬ УСЛОВИЕ" ===
            Button {
                id: addConditionButton
                text: "+ " + tr("Add condition")
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                visible: true
                background: Rectangle {
                    color: "#f0f0f0"
                    radius: 6
                    border.color: "#cccccc"
                }
                contentItem: Text {
                    text: parent.text
                    color: "#333333"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    addCondition()
                }
            }

            // === ЧЕКБОКС "ПОКАЗАТЬ СПИСОК" ===
            CheckBox {
                id: showListCheck
                text: tr("Show feature list")
                checked: showFeatureList
                Layout.fillWidth: true
                onToggled: {
                    showFeatureList = checked
                    // Если фильтр уже активен и список включен, сразу открываем его
                    if (filterActive && checked) {
                        if (selectedLayer && savedExpr) {
                            pendingFormLayer = selectedLayer
                            pendingFormExpr = savedExpr
                            openListTimer.restart()
                        }
                    } else if (!checked && featureFormItem) {
                        featureFormItem.state = "Hidden"
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Button {
                    text: tr("Delete filter")
                    Layout.fillWidth: true
                    background: Rectangle {
                        color: "#333333"
                        radius: 10
                    }
                    contentItem: Text {
                        text: parent.text
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        removeAllFilters()
                        searchDialog.close()
                    }
                }

                Button {
                    id: applyButton
                    text: tr("Apply filter")
                    enabled: false
                    Layout.fillWidth: true
                    background: Rectangle {
                        radius: 10
                        color: enabled ? "#80cc28" : "#e0e0e0"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: enabled ? "white" : "#666666"
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        applyFilter()
                    }
                }
            }
        }
    }

    // === ОБРАБОТКА ВЫБОРА ОБЪЕКТА ИЗ СПИСКА ===
    Connections {
        target: featureFormItem
        ignoreUnknownSignals: true
        function onFeatureSelected(feature) {
            if (feature && selectedLayer) {
                selectedLayer.removeSelection()
                selectedLayer.select(feature.id)
                applyCustomColors()
                useListOffset = true
                isReturnAction = false
                zoomTimer.restart()
            }
        }
        function onVisibleChanged() {
            filterToolRoot.isFormVisible = featureFormItem.visible
            if (!featureFormItem.visible) {
                // Если список закрыт, но мы хотели его показывать, то при повторном открытии диалога чекбокс должен быть в синхронизации
                // ничего не делаем
            }
        }
    }
}