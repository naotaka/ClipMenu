/* The selected text is marked with start and end tags. */

ClipMenu.activate();

var input = prompt('Enter HTML/XML tag name:');
if (!input) {
    throw new Error('Invalid input');
}

var words = input.split(' ');
var tag = words[0];
if (tag.length == 0) {
    throw new Error('Enter valid tag name');
}

return '<' + input + '>' + clipText + '</' + tag + '>';

