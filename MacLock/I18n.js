.pragma library

// Lock screen translations (MacLock runs as its own Quickshell config, so it keeps its own small table).
// I18n.tr("English text") returns the text in the chosen language, or the English text.

var dicts = {
    ru: {
        " more notification": " ещё уведомл.",
        " · Paused": " · Пауза",
        "Enter Password": "Введите пароль",
        "Enter your password to unlock": "Введите пароль для разблокировки",
        "Instrumental": "Инструментал",
        "Loading lyrics…": "Загрузка текста…",
        "Notification": "Уведомление",
        "Timer": "Таймер",
        "Stop": "Стоп",
        "ddd MMM d": "ddd, d MMM",
        "dddd, MMMM d": "dddd, d MMMM"
    }
};
// the language chosen in System Settings (shell.qml sets Qt.uiLanguage), or the system locale
function code() {
    return Qt.uiLanguage !== "" ? Qt.uiLanguage : String(Qt.locale().name || "en").split("_")[0];
}

function tr(text) {
    var d = dicts[code()];
    if (!d || typeof text !== "string")
        return text;
    var t = d[text];
    return t !== undefined ? t : text;
}

function locale() {
    return Qt.uiLanguage !== "" ? Qt.locale(Qt.uiLanguage) : Qt.locale();
}
