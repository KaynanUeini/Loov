// typed-array-buffer@1.0.3 downloaded from https://ga.jspm.io/npm:typed-array-buffer@1.0.3/index.js

import*as r from"es-errors/type";import*as a from"call-bound";import*as t from"is-typed-array";var e=r;try{"default"in r&&(e=r.default)}catch(r){}var f=a;try{"default"in a&&(f=a.default)}catch(r){}var o=t;try{"default"in t&&(o=t.default)}catch(r){}var u={};var y=e;var d=f;
/** @type {undefined | ((thisArg: import('.').TypedArray) => Buffer<ArrayBufferLike>)} */var p=d("TypedArray.prototype.buffer",true);var i=o;
/** @type {import('.')} */u=p||function typedArrayBuffer(r){if(!i(r))throw new y("Not a Typed Array");return r.buffer};var l=u;export{l as default};

