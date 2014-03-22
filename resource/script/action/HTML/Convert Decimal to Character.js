var isExist = ClipMenu.require('JS-methods/char');
if (!isExist) {
    throw new Error('Could not find the library');
}

return clipText.dec2char();

