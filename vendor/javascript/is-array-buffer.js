// is-array-buffer@3.0.5 downloaded from https://ga.jspm.io/npm:is-array-buffer@3.0.5/index.js

import*as r from"call-bind";import*as t from"call-bound";import*as a from"get-intrinsic";var e=r;try{"default"in r&&(e=r.default)}catch(r){}var f=t;try{"default"in t&&(f=t.default)}catch(r){}var u=a;try{"default"in a&&(u=a.default)}catch(r){}var n={};var i=e;var o=f;var c=u;var l=c("%ArrayBuffer%",true);
/** @type {undefined | ((receiver: ArrayBuffer) => number) | ((receiver: unknown) => never)} */var y=o("ArrayBuffer.prototype.byteLength",true);var v=o("Object.prototype.toString");var s=!!l&&!y&&new l(0).slice;var d=!!s&&i(s);
/** @type {import('.')} */n=y||d?function isArrayBuffer(r){if(!r||typeof r!=="object")return false;try{y?y(r):d(r,0);return true}catch(r){return false}}:l?function isArrayBuffer(r){return v(r)==="[object ArrayBuffer]"}:function isArrayBuffer(r){return false};var p=n;export{p as default};

