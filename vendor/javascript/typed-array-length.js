// typed-array-length@1.0.7 downloaded from https://ga.jspm.io/npm:typed-array-length@1.0.7/index.js

import*as t from"call-bind";import*as r from"for-each";import*as a from"gopd";import*as e from"is-typed-array";import*as f from"possible-typed-array-names";import*as o from"reflect.getprototypeof/polyfill";var l=t;try{"default"in t&&(l=t.default)}catch(t){}var n=r;try{"default"in r&&(n=r.default)}catch(t){}var i=a;try{"default"in a&&(i=a.default)}catch(t){}var u=e;try{"default"in e&&(u=e.default)}catch(t){}var v=f;try{"default"in f&&(v=f.default)}catch(t){}var c=o;try{"default"in o&&(c=o.default)}catch(t){}var p=typeof globalThis!=="undefined"?globalThis:typeof self!=="undefined"?self:global;var y={};var d=l;var h=n;var s=i;var g=u;var m=v;var b=c();
/** @typedef {(value: import('.').TypedArray) => number} TypedArrayLengthGetter */
/** @typedef {{ [k in `$${import('.').TypedArrayName}` | '__proto__']: k extends '__proto__' ? null : TypedArrayLengthGetter }} Cache */
/** @type {Cache} */var _={__proto__:null};var A=Object.defineProperty;if(s){var getLength=/** @type {TypedArrayLengthGetter} */function(t){return t.length};h(m,(/** @type {(typedArray: import('.').TypedArrayName) => void} */function(t){var r=p[t];if(typeof r==="function"||typeof r==="object"){var a=r.prototype;var e=s(a,"length");if(!e){var f=b(a);e=s(f,"length")}if(e&&e.get)_[/** @type {`$${import('.').TypedArrayName}`} */"$"+t]=d(e.get);else if(A){var o=new p[t](2);e=s(o,"length");e&&e.configurable&&A(o,"length",{value:3});o.length===2&&(_[/** @type {`$${import('.').TypedArrayName}`} */"$"+t]=getLength)}}}))}
/** @type {TypedArrayLengthGetter} */var T=function tryAllTypedArrays(t){
/** @type {number} */var r;h(_,(/** @type {(getter: TypedArrayLengthGetter) => void} */function(a){if(typeof r!=="number")try{var e=a(t);typeof e==="number"&&(r=e)}catch(t){}}));return r};
/** @type {import('.')} */y=function typedArrayLength(t){return!!g(t)&&T(t)};var j=y;export{j as default};

