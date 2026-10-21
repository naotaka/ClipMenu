var isExist = ClipMenu.require('v8cgi/html');
if (!isExist) {
    throw new Error('Could not find the library');
}

var lines = clipText.split('\n');

for (var i = 0; i < lines.length; i++) {
    lines[i] = HTML.escape(lines[i]);
}

return lines.join('\n');

