.pragma library
.import "lang/ru.js" as Ru

// Interface translations. I18n.tr("English text") returns the text in the chosen language, or the English text
// itself when there is no translation. The language is Qt.uiLanguage (System Settings → General → Language,
// set by MacBar), or the system locale (LANG, e.g. ru_RU.UTF-8) when that is empty. Bindings that call tr()
// read Qt.uiLanguage, so they update when the language changes.
// To add a language: copy lang/ru.js to lang/<code>.js, translate the values, and add it to `dicts` below.

var dicts = { ru: Ru.strings };

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

// The locale for day and month names: the chosen language, or the system locale.
function locale() {
    return Qt.uiLanguage !== "" ? Qt.locale(Qt.uiLanguage) : Qt.locale();
}
