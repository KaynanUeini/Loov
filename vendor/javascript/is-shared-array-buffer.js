// is-shared-array-buffer@1.0.4 downloaded from https://ga.jspm.io/npm:is-shared-array-buffer@1.0.4/index.js

import*as r from"call-bound";var e=r;try{"default"in r&&(e=r.default)}catch(r){}var t={};var a=e;
/** @type {undefined | ((thisArg: SharedArrayBuffer) => number)} */var f=a("SharedArrayBuffer.prototype.byteLength",true);
/** @type {import('.')} */t=f?function isSharedArrayBuffer(r){if(!r||typeof r!=="object")return false;try{f(r);return true}catch(r){return false}}:function isSharedArrayBuffer(r){return false};var u=t;export{u as default};

