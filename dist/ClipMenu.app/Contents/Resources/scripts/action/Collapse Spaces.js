var isExist = ClipMenu.require('JS-methods/string');
if (!isExist) {
    throw new Error('Could not find the library');
}

return clipText.collapseSpaces();

