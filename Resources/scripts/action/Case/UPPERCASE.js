var lines = clipText.split('\n');

for (var i = 0; i < lines.length; i++) {
    lines[i] = lines[i].toUpperCase();
}

return lines.join('\n');

