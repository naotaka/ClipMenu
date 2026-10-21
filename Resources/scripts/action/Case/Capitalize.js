var isExist = ClipMenu.require('inflection');
if (!isExist) {
    throw new Error('Could not find the library');
}

var lines = clipText.split('\n');

for (var i = 0; i < lines.length; i++) {
    lines[i] = lines[i].capitalize();
}

return lines.join('\n');

