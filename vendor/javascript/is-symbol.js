// is-symbol@1.1.1 downloaded from https://ga.jspm.io/npm:is-symbol@1.1.1/index.js

import*as t from"call-bound";import*as r from"has-symbols";import*as a from"safe-regex-test";var e=t;try{"default"in t&&(e=t.default)}catch(t){}var o=r;try{"default"in r&&(o=r.default)}catch(t){}var f=a;try{"default"in a&&(f=a.default)}catch(t){}var l={};var u=e;var n=u("Object.prototype.toString");var s=o();var y=f;if(s){var i=u("Symbol.prototype.toString");var c=y(/^Symbol\(.*\)$/);
/** @type {(value: object) => value is Symbol} */var m=function isRealSymbolObject(t){return typeof t.valueOf()==="symbol"&&c(i(t))};
/** @type {import('.')} */l=function isSymbol(t){if(typeof t==="symbol")return true;if(!t||typeof t!=="object"||n(t)!=="[object Symbol]")return false;try{return m(t)}catch(t){return false}}}else
/** @type {import('.')} */
l=function isSymbol(t){return false};var b=l;export{b as default};

