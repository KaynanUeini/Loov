// is-regex@1.2.0 downloaded from https://ga.jspm.io/npm:is-regex@1.2.0/index.js

import*as t from"call-bind/callBound";import*as a from"has-tostringtag/shams";import*as r from"hasown";import*as e from"gopd";var o=t;try{"default"in t&&(o=t.default)}catch(t){}var f=a;try{"default"in a&&(f=a.default)}catch(t){}var i=r;try{"default"in r&&(i=r.default)}catch(t){}var n=e;try{"default"in e&&(n=e.default)}catch(t){}var v={};var l=o;var c=f();var u=i;var s=n;
/** @type {import('.')} */var p;if(c){
/** @type {(receiver: ThisParameterType<typeof RegExp.prototype.exec>, ...args: Parameters<typeof RegExp.prototype.exec>) => ReturnType<typeof RegExp.prototype.exec>} */
var m=l("RegExp.prototype.exec");
/** @type {object} */var y={};var throwRegexMarker=function(){throw y};
/** @type {{ toString(): never, valueOf(): never, [Symbol.toPrimitive]?(): never }} */var d={toString:throwRegexMarker,valueOf:throwRegexMarker};typeof Symbol.toPrimitive==="symbol"&&(d[Symbol.toPrimitive]=throwRegexMarker);
/** @type {import('.')} */p=function isRegex(t){if(!t||typeof t!=="object")return false;var a=/** @type {NonNullable<typeof gOPD>} */s(/** @type {{ lastIndex?: unknown }} */t,"lastIndex");var r=a&&u(a,"value");if(!r)return false;try{m(t,/** @type {string} */ /** @type {unknown} */d)}catch(t){return t===y}}}else{
/** @type {(receiver: ThisParameterType<typeof Object.prototype.toString>, ...args: Parameters<typeof Object.prototype.toString>) => ReturnType<typeof Object.prototype.toString>} */
var g=l("Object.prototype.toString");
/** @const @type {'[object RegExp]'} */var h="[object RegExp]";
/** @type {import('.')} */p=function isRegex(t){return!(!t||typeof t!=="object"&&typeof t!=="function")&&g(t)===h}}v=p;var b=v;export{b as default};

