import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Theme

RowLayout {
    id: root

    property int conditionIndex: 0
    property string fieldValue: ""
    property string operatorValue: "="
    property string valueValue: ""
    property string joinValue: "AND"
    property var availableFields: []

    // Сигналы
    signal fieldChanged(int index, string value)
    signal operatorChanged(int index, string value)
    signal valueChanged(int index, string value)
    signal joinChanged(int index, string value)
    signal removeRequested(int index)

    Layout.fillWidth: true
    spacing: 4

    // === JOIN (AND/OR) ===
    QfComboBox {
        id: joinCombo
        Layout.preferredWidth: 55
        Layout.preferredHeight: 32
        model: ["AND", "OR"]
        currentIndex: joinValue === "AND" ? 0 : 1
        visible: conditionIndex > 0
        onCurrentTextChanged: {
            root.joinChanged(conditionIndex, currentText)
        }
    }

    // === ПОЛЕ ===
    QfComboBox {
        id: fieldCombo
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        model: availableFields
        currentText: fieldValue
        onCurrentTextChanged: {
            root.fieldChanged(conditionIndex, currentText)
        }
    }

    // === ОПЕРАТОР ===
    QfComboBox {
        id: operatorCombo
        Layout.preferredWidth: 65
        Layout.preferredHeight: 32
        model: ["=", "!=", "<", ">", "<=", ">=", "LIKE", "ILIKE"]
        currentText: operatorValue
        onCurrentTextChanged: {
            root.operatorChanged(conditionIndex, currentText)
        }
    }

    // === ЗНАЧЕНИЕ ===
    TextField {
        id: valueField
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        placeholderText: qsTr("Value")
        text: valueValue
        onTextChanged: {
            root.valueChanged(conditionIndex, text)
        }
    }

    // === КНОПКА УДАЛЕНИЯ ===
    Button {
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        text: "✕"
        background: Rectangle {
            color: "#ff4444"
            radius: 4
        }
        contentItem: Text {
            text: parent.text
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: {
            root.removeRequested(conditionIndex)
        }
    }
}