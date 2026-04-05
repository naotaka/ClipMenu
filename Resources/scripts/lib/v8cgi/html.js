var HTML = {
	escape: function(str) {
		if (str === null || !str.toString) { return ""; }
		return str.toString()
			.replace(/&/g,"&amp;")
			.replace(/</g,"&lt;")
			.replace(/>/g,"&gt;")
			.replace(/"/g,"&quot;")
			.replace(/'/g,"&apos;");
	},
	unescape: function(str) {
		if (str === null || !str.toString) { return ""; }
		return str.toString()
			.replace(/&apos;/g,"'")
			.replace(/&quot;/g,"\"")
			.replace(/&gt;/g,">")
			.replace(/&lt;/g,"<")
			.replace(/&amp;/g,"&");
	}
}
exports.HTML = HTML;
