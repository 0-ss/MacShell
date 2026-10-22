.pragma library
// One place that decides which font face a piece of text gets.
// Open Runde ships as two faces (Regular and Semibold), so bold text must use the Semibold face instead of a synthetic bold
// of the Regular one. Any other font the user picked (Noto Sans, the system font) keeps its own family and real bold weight.
function forWeight(weight, family) {
    return (Number(weight) >= 600 && family === "Open Runde") ? "Open Runde Semibold" : family;
}
