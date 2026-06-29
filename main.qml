import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme
import org.qfield
import org.qgis

Item {
    id: filterToolRoot

    // === PROPRIÉTÉS QFIELD ===
    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    property var featureFormItem: iface.findItemByObjectName("featureForm")
    property var dashBoard: iface.findItemByObjectName('dashBoard')

    // === СОСТОЯНИЕ ФИЛЬТРА ===
    property var selectedLayer: null
    property bool filterActive: false
    property bool isFormVisible: false

    // === СПИСОК УСЛОВИЙ ===
    property var conditions: []
    property var conditionComponents: []

    // === ПЕРСИСТАНТНОСТЬ ===
    property string savedLayerName: ""
    property string savedExpr: ""

    // === ЦВЕТА ===
    property color highlightColor: "#80cc28"
    property color origProjectColor: "yellow"
    property var highlightItem: null

    // === ИНИЦИАЛИЗАЦИЯ ===
    Component.onCompleted: {
        iface.addItemToPluginsToolbar(toolbarButton)
        updateLayers()

        if (featureFormItem) isFormVisible = featureFormItem.visible

        if (qgisProject) origProjectColor = qgisProject.selectionColor
    }

    // === КНОПКА НА ПАНЕЛИ ===
    QfToolButton {
        id: toolbarButton
        iconSource: "icon.svg"
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true

        onClicked: {
            openFilterUI()
        }

        onPressAndHold: {
            removeAllFilters()
            mainWindow.displayToast(tr("Filter deleted"))
        }
    }

    // === ФУНКЦИИ РАБОТЫ С УСЛОВИЯМИ ===
    function addCondition() {
        var condition = {
            field: "",
            operator: "=",
            value: "",
            join: "AND"
        }
        conditions.push(condition)
        rebuildConditionUI()
    }

    function removeCondition(index) {
        if (index >= 0 && index < conditions.length) {
            conditions.splice(index, 1)
            rebuildConditionUI()
        }
    }

    function rebuildConditionUI() {
        // Очищаем существующие UI-элементы
        for (var i = 0; i < conditionComponents.length; i++) {
            var comp = conditionComponents[i]
            if (comp && comp.parent) {
                comp.parent = null
                comp.destroy()
            }
        }
        conditionComponents = []

        // Создаём новые UI-элементы для каждого условия
        var container = conditionsContainer
        if (!container) return

        for (var j = 0; j < conditions.length; j++) {
            var cond = conditions[j]

            // Создаём компонент условия
            var component = Qt.createComponent("ConditionRow.qml")
            if (component.status === Component.Ready) {
                var row = component.createObject(container, {
                    "conditionIndex": j,
                    "fieldValue": cond.field,
                    "operatorValue": cond.operator,
                    "valueValue": cond.value,
                    "joinValue": cond.join,
                    "availableFields": getFieldNames(selectedLayer)
                })

                if (row) {
                    row.fieldChanged.connect(function(index, value) {
                        if (index >= 0 && index < conditions.length) {
                            conditions[index].field = value
                            updateFilter()
                        }
                    })
                    row.operatorChanged.connect(function(index, value) {
                        if (index >= 0 && index < conditions.length) {
                            conditions[index].operator = value
                            updateFilter()
                        }
                    })
                    row.valueChanged.connect(function(index, value) {
                        if (index >= 0 && index < conditions.length) {
                            conditions[index].value = value
                            updateFilter()
                        }
                    })
                    row.joinChanged.connect(function(index, value) {
                        if (index >= 0 && index < conditions.length) {
                            conditions[index].join = value
                            updateFilter()
                        }
                    })
                    row.removeRequested.connect(function(index) {
                        removeCondition(index)
                    })

                    conditionComponents.push(row)
                }
            }
        }

        // Обновляем отображение кнопки "Добавить условие"
        updateAddButtonVisibility()
        updateApplyState()
    }

    function updateAddButtonVisibility() {
        if (addConditionButton) {
            addConditionButton.visible = conditions.length < 10
        }
    }

    function getFieldNames(layer) {
        if (!layer || !layer.fields) return []
        var fields = layer.fields
        return fields.names ? fields.names.slice().sort() : []
    }

    // === ПОСТРОЕНИЕ ВЫРАЖЕНИЯ ФИЛЬТРА ===
    function buildFilterExpression() {
        if (!selectedLayer || conditions.length === 0) return ""

        var exprParts = []
        for (var i = 0; i < conditions.length; i++) {
            var cond = conditions[i]
            if (!cond.field || !cond.value) continue

            var fieldName = cond.field
            var operator = cond.operator
            var value = cond.value

            // Экранируем кавычки в значении
            var escapedValue = value.replace(/'/g, "''")

            var part = ""
            if (operator === "LIKE" || operator === "ILIKE") {
                part = '"' + fieldName + '" ' + operator + ' \'%' + escapedValue + '%\''
            } else if (operator === "=" || operator === "!=" || operator === "<" || operator === ">" || operator === "<=" || operator === ">=") {
                // Проверяем, является ли значение числом
                if (!isNaN(value) && value.trim() !== "") {
                    part = '"' + fieldName + '" ' + operator + ' ' + value
                } else {
                    part = '"' + fieldName + '" ' + operator + ' \'' + escapedValue + '\''
                }
            }

            if (part) exprParts.push(part)
        }

        if (exprParts.length === 0) return ""

        // Собираем выражение с операторами AND/OR
        var result = exprParts[0]
        for (var j = 1; j < exprParts.length; j++) {
            var join = (j - 1 < conditions.length) ? conditions[j].join : "AND"
            result += " " + join + " " + exprParts[j]
        }

        return result
    }

    // === ПРИМЕНЕНИЕ ФИЛЬТРА ===
    function updateFilter() {
        if (!selectedLayer) return

        var expr = buildFilterExpression()
        savedExpr = expr

        try {
            if (expr) {
                selectedLayer.subsetString = ""
                selectedLayer.removeSelection()
                selectedLayer.selectByExpression(expr)
                selectedLayer.triggerRepaint()
                mapCanvas.refresh()
                filterActive = true
                savedLayerName = selectedLayer.name

                // Обновляем информационный баннер
                if (infoBanner) infoBanner.visible = true
            } else {
                removeAllFilters()
            }
        } catch (e) {
            console.error("Filter error: " + e)
            mainWindow.displayToast(tr("Filter error: ") + e)
        }
    }

    function applyFilter() {
        updateFilter()
        searchDialog.close()
        mainWindow.displayToast(tr("Filter applied: ") + conditions.length + tr(" conditions"))
    }

    // === УДАЛЕНИЕ ФИЛЬТРА ===
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
        selectedLayer = null

        // Очищаем условия
        conditions = []
        rebuildConditionUI()

        if (featureFormItem) {
            featureFormItem.state = "Hidden"
        }

        mapCanvas.refresh()
        updateLayers()
        updateApplyState()
        if (infoBanner) infoBanner.visible = false
    }

    // === UI ВСПОМОГАТЕЛЬНЫЕ ===
    function updateLayers() {
        var layers = ProjectUtils.mapLayers(qgisProject)
        var names = []
        for (var id in layers) if (layers[id] && layers[id].type === 0) names.push(layers[id].name)
        names.sort()
        names.unshift(tr("Select a layer"))
        if (layerSelector) {
            layerSelector.model = names
            if (filterActive && savedLayerName) {
                var idx = names.indexOf(savedLayerName)
                layerSelector.currentIndex = idx >= 0 ? idx : 0
            } else layerSelector.currentIndex = 0
        }
    }

    function getLayerByName(name) {
        var layers = ProjectUtils.mapLayers(qgisProject)
        for (var id in layers) if (layers[id].name === name) return layers[id]
        return null
    }

    function updateApplyState() {
        if (applyButton) {
            var hasValidConditions = false
            for (var i = 0; i < conditions.length; i++) {
                if (conditions[i].field && conditions[i].value) {
                    hasValidConditions = true
                    break
                }
            }
            applyButton.enabled = selectedLayer !== null && hasValidConditions
        }
    }

    function tr(text) {
        var isFr = Qt.locale().name.substring(0, 2) === "fr"
        var dic = {
            "FILTER": "FILTRE",
            "Filter deleted": "Фильтр удалён",
            "Filter applied: ": "Фильтр применён: ",
            " conditions": " условий",
            "Filter error: ": "Ошибка фильтра: ",
            "Select a layer": "Выберите слой",
            "Select a field": "Выберите поле",
            "Operator": "Оператор",
            "Value": "Значение",
            "Add condition": "Добавить условие",
            "Apply filter": "Применить фильтр",
            "Delete filter": "Удалить фильтр"
        }
        return isFr && dic[text] ? dic[text] : (dic[text] || text)
    }

    // === ИНФОРМАЦИОННЫЙ БАННЕР ===
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
        border.width: 0
        visible: filterToolRoot.filterActive && !filterToolRoot.isFormVisible

        RowLayout {
            id: bannerLayout
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            spacing: 10

            Rectangle {
                width: 8
                height: 8
                radius: 4
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
                        if (displayText.length > 40) {
                            displayText = displayText.substring(0, 37) + "..."
                        }
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

    // === ОСНОВНОЙ ДИАЛОГ ===
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
            onClicked: {
                mouse.accepted = false
            }
        }

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            // === ВЫБОР СЛОЯ ===
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
                        conditions = []
                        rebuildConditionUI()
                        return
                    }
                    selectedLayer = getLayerByName(currentText)
                    conditions = []
                    rebuildConditionUI()
                    updateApplyState()
                }
            }

            // === КОНТЕЙНЕР УСЛОВИЙ ===
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, conditions.length * 80 + 10)
                Layout.minimumHeight: 60
                clip: true

                ColumnLayout {
                    id: conditionsContainer
                    width: parent.width
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.minimumHeight: 60
                }
            }

            // === КНОПКА ДОБАВЛЕНИЯ ===
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

            // === КНОПКИ ПРИМЕНЕНИЯ/УДАЛЕНИЯ ===
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
}