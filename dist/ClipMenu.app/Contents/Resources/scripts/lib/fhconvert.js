/*
	fhconvert.js ver1.1.4 <http://distraid.co.jp/demo/js_codeconv.html>
	Fullwidth to Halfwidth, Hiragana to Katakana and vice versa, Unicode charactor converter

	copyright (c) 2008 distraid Inc. <http://distraid.co.jp/>
	This script is freely distributable under the terms of an MIT-style license.

	$Id: fhconvert.js 10 2009-02-16 08:15:24Z ksy $
*/

var FHConvert = {
	ConvPattern: {
		ftoh: {range:{start:0xff01,end:0xff5e}, mod:-0xfee0},
		htof: {range:{start:0x0021,end:0x007e}, mod:+0xfee0},
		hgtokk: {range:{start:0x3041,end:0x3096}, mod:+0x0060},
		kktohg: {range:{start:0x30a1,end:0x30f6}, mod:-0x0060},

		fkktohkk: {range:{start:0x30a1,end:0x30fc}},
		hkktofkk: {range:{start:0xff61,end:0xff9f}, vsm:0xff9e, vsmRange:{start:0xff66,end:0xff9c}, svsm:0xff9f, svsmRange:{start:0xff8a,end:0xff8e}},

		_jftojh: {convSet:{'\u2019':'\u0027','\u201d':'\u0022','\uffe5':'\u005c'}},
		_jhtojf: {convSet:{'\u0027':'\u2019','\u0022':'\u201d','\u005c':'\uffe5'}},

		_fstohs: {convSet:{'\u3000':'\u0020'}},
		_hstofs: {convSet:{'\u0020':'\u3000'}}
	},

	_convertSet: function( value, param ) {
		if ( !value || !param ) return value;
		var str, idx, len = value.length, newVal = '', strArray = new Array(len);
		for ( idx=0; idx<len; idx++ )
		{
			str = value.charAt( idx );
			if ( param['convSet'] && param['convSet'][str]!=null )
				strArray[idx] = param['convSet'][str];
			else
				strArray[idx] = str;
		}
		return strArray.join('');
	},

	_convert: function( value, param ) {
		if ( !value || !param ) return value;
		var code, str, idx, len = value.length, newVal = '', strArray = new Array(len);
		for ( idx=0; idx<len; idx++ )
		{
			str = value.charAt( idx );
			code = str.charCodeAt(0);
			if ( param['convSet'] && param['convSet'][str]!=null )
				strArray[idx] = param['convSet'][str];
			else if ( code >= param['range']['start'] && code <= param['range']['end'] )
				strArray[idx] = String.fromCharCode( code + param['mod'] );
			else
				strArray[idx] = str;
		}
		return strArray.join('');
	},

	_convertReg: function( value, param ) {
		if ( !value || !param ) return value;
		return value.replace( param['convReg'], param['convRepl'] );			
	},

	mergeObj: function( obj1, obj2 ) {
		var obj = {};
		for ( var prop in obj1 )
			obj[prop] = obj1[prop];
		for ( prop in obj2 )
			obj[prop] = obj2[prop];
		return obj;
	},

	_initConvert: function( id, param ) {
		var opt = {id:id}, convSet = null, code;
		if ( !param ) param = {};

		if ( this.ConvPattern[id] )
		{
			opt['range'] = this.ConvPattern[id]['range'];
			opt['mod'] = this.ConvPattern[id]['mod'];
			convSet = this.ConvPattern[id]['convSet'];
		}

		if ( param['jaCode'] )
		{
			if ( id == 'ftoh' )
				convSet = this.mergeObj( convSet, this.ConvPattern['_jftojh']['convSet'] );
			else if ( id == 'htof' )
				convSet = this.mergeObj( convSet, this.ConvPattern['_jhtojf']['convSet'] );
		}

		if ( param['space'] )
		{
			if ( id == 'ftoh' || id == 'fkktohkk' )
				convSet = this.mergeObj( convSet, this.ConvPattern['_fstohs']['convSet'] );
			else if ( id == 'htof' || id == 'hkktofkk' )
				convSet = this.mergeObj( convSet, this.ConvPattern['_hstofs']['convSet'] );		
		}

		if ( typeof param['convSet'] == 'object' )
		{
			convSet = this.mergeObj( convSet, param['convSet'] );
			for ( code in convSet )
			{
				if ( typeof convSet[code] == 'number' )
					convSet[code] = String.fromCharCode( convSet[code] );
			}
		}
		opt['convSet'] = convSet;
		return opt;
	},

	_toRegStr: function( code ) {
		if ( code == null ) return '';
		var idx, strCode = '';
		if ( typeof code == 'string' )
		{
			for ( idx = 0; idx < code.length; idx++ )
				strCode += this._toRegStr( code.charCodeAt(idx) );
			return strCode;
		}
		strCode = '000'+code.toString(16);
		return '\\u'+strCode.substring( strCode.length-4 );	
	},

	_initConvertReg: function( id, param ) {
		if ( !param ) return null;
		var code, prop, val, regStr, rangeCode = '', recode = '', convObj = {}, recodeM = [];
		if ( param['range'] )
		{
			if ( param['mod'] )
			{
				for ( code = param['range']['start']; code <= param['range']['end']; code++ )
					convObj[String.fromCharCode(code)] = String.fromCharCode( code + param['mod'] );
			}
			rangeCode = this._toRegStr(param['range']['start']) + '-' + this._toRegStr(param['range']['end']);
		}

		if ( param['convSet'] )
		{
			for ( prop in param['convSet'] )
			{
				val = param['convSet'][prop];
				regStr = this._toRegStr( prop );
				if ( prop.length > 1 )
					recodeM.push( '('+regStr+')' );
				else {
					code = prop.charCodeAt(0);
					if ( !param['range'] || code < param['range']['start'] || code > param['range']['end'] )
						recode += regStr;
				}
				convObj[prop] = val;
			}
		}
		if ( id == 'hkktofkk' && this.ConvPattern['hkktofkk']['convSetHKK'] )
		{
			for ( prop in this.ConvPattern['hkktofkk']['convSetHKK'] )
				convObj[prop] = this.ConvPattern['hkktofkk']['convSetHKK'][prop];
			recodeM.push( '(['+this._toRegStr(this.ConvPattern['hkktofkk']['vsmRange']['start'])+'-'+this._toRegStr(this.ConvPattern['hkktofkk']['vsmRange']['end'])+']'+this._toRegStr(this.ConvPattern['hkktofkk']['vsm'])+')' );
			recodeM.push( '(['+this._toRegStr(this.ConvPattern['hkktofkk']['svsmRange']['start'])+'-'+this._toRegStr(this.ConvPattern['hkktofkk']['svsmRange']['end'])+']'+this._toRegStr(this.ConvPattern['hkktofkk']['svsm'])+')' );
		}

		recode = rangeCode + recode;
		if ( !recode && recodeM.length <= 0 ) return null;

		if ( recode )
			recode = '(['+recode+'])';
		if ( recodeM.length > 0 )
		{
			if ( recode )
				recodeM.push( recode );
			recode = recodeM.join( '|' );		
		}

		param['convSet'] = null;
		param['convReg'] = new RegExp( recode, 'g' );
		code = prop = val = ragStr = rengeCode = recode = recodeM = null;

		if ( id == 'hkktofkk' )
		{
			param['convRepl'] = function( m0 ) {
				if ( convObj[m0] != null )
					return convObj[m0];
				return convObj[m0.charAt(0)]+convObj[m0.charAt(1)];
			};
		} else
			param['convRepl'] = function( m0 ) { return convObj[m0]; };
		return param;
	},

	ftoh: function( value, param ) {
		return this._convert( value, this._initConvert('ftoh',param) );
	},
	htof: function( value, param ) {
		return this._convert( value, this._initConvert('htof',param) );
	},
	hgtokk: function( value, param ) {
		return this._convert( value, this._initConvert('hgtokk',param) );
	},
	kktohg: function( value, param ) {
		return this._convert( value, this._initConvert('kktohg',param) );
	},
	fkktohkk: function( value, param ) {
		return this._convertSet( value, this._initConvert('fkktohkk',param) );
	},
	hkktofkk: function( value, param ) {
		param = this._initConvert( 'hkktofkk', param );
		param = this._initConvertReg( 'hkktofkk', param );
		return this._convertReg( value, param );
	},

	createCl: function( id, param ) {
		param = this._initConvert( id, param );
		param = this._initConvertReg( id, param );
		if ( !param ) return function( value ) { return value; }
		var bind = FHConvert;
		var proc = function( value ) {	
			return this._convertReg( value, param );
		}
		return function(value) {
			return proc.apply( bind, [value] );
		}
	}	
};

(function(){
	var cp = FHConvert['ConvPattern'];

	var hkkMark = {0x300c:0xff62,0x300d:0xff63,0x3002:0xff61,0x3001:0xff64,0x309b:0xff9e,0x309c:0xff9f};
	var halfcode = [0xff67,0xff71,0xff68,0xff72,0xff69,0xff73,0xff6a,0xff74,0xff6b,0xff75,	
		0xff76,,0xff77,,0xff78,,0xff79,,0xff7a,,0xff7b,,0xff7c,,0xff7d,,0xff7e,,0xff7f,,
		0xff80,,0xff81,,0xff6f,0xff82,,0xff83,,0xff84,,0xff85,0xff86,0xff87,0xff88,0xff89,
		0xff8a,,,0xff8b,,,0xff8c,,,0xff8d,,,0xff8e,,,
		0xff8f,0xff90,0xff91,0xff92,0xff93,0xff6c,0xff94,0xff6d,0xff95,0xff6e,0xff96,
		0xff97,0xff98,0xff99,0xff9a,0xff9b,0xff9c,0xff9c,0xff72,0xff74,0xff66,0xff9d,
		,0xff76,0xff79,,,,,0xff65,0xff70];
	var halfConv = {
		0x30ac:[0xff76,0xff9e],0x30ae:[0xff77,0xff9e],0x30b0:[0xff78,0xff9e],0x30b2:[0xff79,0xff9e],0x30b4:[0xff7a,0xff9e],
		0x30b6:[0xff7b,0xff9e],0x30b8:[0xff7c,0xff9e],0x30ba:[0xff7d,0xff9e],0x30bc:[0xff7e,0xff9e],0x30be:[0xff7f,0xff9e],
		0x30c0:[0xff80,0xff9e],0x30c2:[0xff81,0xff9e],0x30c5:[0xff82,0xff9e],0x30c7:[0xff83,0xff9e],0x30c9:[0xff84,0xff9e],
		0x30d0:[0xff8a,0xff9e],0x30d3:[0xff8b,0xff9e],0x30d6:[0xff8c,0xff9e],0x30d9:[0xff8d,0xff9e],0x30dc:[0xff8e,0xff9e],
		0x30d1:[0xff8a,0xff9f],0x30d4:[0xff8b,0xff9f],0x30d7:[0xff8c,0xff9f],0x30da:[0xff8d,0xff9f],0x30dd:[0xff8e,0xff9f],
		0x30f4:[0xff73,0xff9e],0x30f7:[0xff9c,0xff9e],0x30f8:[0xff72,0xff9e],0x30f9:[0xff74,0xff9e],0x30fa:[0xff66,0xff9e]
	};

	var idx, code, prop, fkkSet = {};
	if ( cp['fkktohkk'] )
	{
		for ( idx = 0, code = cp['fkktohkk']['range']['start']; code <= cp['fkktohkk']['range']['end']; code++, idx++ )
			fkkSet[String.fromCharCode(code)] = String.fromCharCode.apply( null, (halfConv[code]!=null?halfConv[code]:[halfcode[idx]]) );
		for ( code in hkkMark )
			fkkSet[String.fromCharCode(code)] = String.fromCharCode( hkkMark[code] );
		cp['fkktohkk']['convSet'] = fkkSet;
	}

	var vsm = 0xff9e;
	var svsm = 0xff9f;
	var fullcode = [0x3002,0x300c,0x300d,0x3001,0x30fb,
		0x30f2,0x30a1,0x30a3,0x30a5,0x30a7,0x30a9,0x30e3,0x30e5,0x30e7,0x30c3,0x30fc,
		0x30a2,0x30a4,0x30a6,0x30a8,0x30aa,0x30ab,0x30ad,0x30af,0x30b1,0x30b3,0x30b5,0x30b7,0x30b9,0x30bb,0x30bd,0x30bf,0x30c1,0x30c4,0x30c6,0x30c8,
		0x30ca,0x30cb,0x30cc,0x30cd,0x30ce,0x30cf,0x30d2,0x30d5,0x30d8,0x30db,0x30de,0x30df,0x30e0,0x30e1,0x30e2,0x30e4,0x30e6,0x30e8,
		0x30e9,0x30ea,0x30eb,0x30ec,0x30ed,0x30ef,0x30f3,0x309b,0x309c];

	var vsmConv = {
		0xff76:{v:0x30ac},0xff77:{v:0x30ae},0xff78:{v:0x30b0},0xff79:{v:0x30b2},0xff7a:{v:0x30b4},0xff7b:{v:0x30b6},0xff7c:{v:0x30b8},0xff7d:{v:0x30ba},0xff7e:{v:0x30bc},0xff7f:{v:0x30be},
		0xff80:{v:0x30c0},0xff81:{v:0x30c2},0xff82:{v:0x30c5},0xff83:{v:0x30c7},0xff84:{v:0x30c9},
		0xff8a:{v:0x30d0,sv:0x30d1},0xff8b:{v:0x30d3,sv:0x30d4},0xff8c:{v:0x30d6,sv:0x30d7},0xff8d:{v:0x30d9,sv:0x30da},0xff8e:{v:0x30dc,sv:0x30dd},
		0xff73:{v:0x30f4},0xff9c:{v:0x30f7},0xff66:{v:0x30fa}
	};

	var hkkSet = {};
	if ( cp['hkktofkk'] )
	{
		for ( idx = 0, code = cp['hkktofkk']['range']['start']; code <= cp['hkktofkk']['range']['end']; code++, idx++ )
			hkkSet[String.fromCharCode(code)] = String.fromCharCode( fullcode[idx] );

		for ( code in vsmConv )
		{
			if ( vsmConv[code]['v'] )
				hkkSet[String.fromCharCode(code,vsm)] = String.fromCharCode( vsmConv[code]['v'] );
			if ( vsmConv[code]['sv'] )
				hkkSet[String.fromCharCode(code,svsm)] = String.fromCharCode( vsmConv[code]['sv'] );
		}
		cp['hkktofkk']['convSetHKK'] = hkkSet;
	}
})();