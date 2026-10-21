var isExist = ClipMenu.require('fhconvert');
if (!isExist) {
    throw new Error('Could not find the library');
}

var lines = clipText.split('\n');

for (var i = 0; i < lines.length; i++) {
    lines[i] = FHConvert.hkktofkk(lines[i]);
}

return lines.join('\n');

