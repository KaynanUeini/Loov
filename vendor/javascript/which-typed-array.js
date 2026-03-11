// which-typed-array@1.1.19 downloaded from https://ga.jspm.io/npm:which-typed-array@1.1.19/index.js

import*as r from"for-each";import*as a from"available-typed-arrays";import*as t from"call-bind";import*as e from"call-bound";import*as o from"gopd";import*as f from"get-proto";import*as n from"has-tostringtag/shams";var i=r;try{"default"in r&&(i=r.default)}catch(r){}var l=a;try{"default"in a&&(l=a.default)}catch(r){}var u=t;try{"default"in t&&(u=t.default)}catch(r){}var c=e;try{"default"in e&&(c=e.default)}catch(r){}var v=o;try{"default"in o&&(v=o.default)}catch(r){}var d=f;try{"default"in f&&(d=f.default)}catch(r){}var y=n;try{"default"in n&&(y=n.default)}catch(r){}var s=typeof globalThis!=="undefined"?globalThis:typeof self!=="undefined"?self:global;var p={};var g=i;var h=l;var m=u;var b=c;var S=v;var T=d;var A=b("Object.prototype.toString");var O=y();var _=typeof globalThis==="undefined"?s:globalThis;var j=h();var w=b("String.prototype.slice");
/** @type {<T = unknown>(array: readonly T[], value: unknown) => number} */var x=b("Array.prototype.indexOf",true)||function indexOf(r,a){for(var t=0;t<r.length;t+=1)if(r[t]===a)return t;return-1};
/** @typedef {import('./types').Getter} Getter */
/** @type {import('./types').Cache} */var $={__proto__:null};g(j,O&&S&&T?function(r){var a=new _[r];if(Symbol.toStringTag in a&&T){var t=T(a);var e=S(t,Symbol.toStringTag);if(!e&&t){var o=T(t);e=S(o,Symbol.toStringTag)}$["$"+r]=m(e.get)}}:function(r){var a=new _[r];var t=a.slice||a.set;t&&($[/** @type {`$${import('.').TypedArrayName}`} */"$"+r]=/** @type {import('./types').BoundSlice | import('./types').BoundSet} */
m(t))}
/** @type {(value: object) => false | import('.').TypedArrayName} */);var k=function tryAllTypedArrays(r){
/** @type {ReturnType<typeof tryAllTypedArrays>} */var a=false;g(/** @type {Record<`\$${import('.').TypedArrayName}`, Getter>} */$,(/** @type {(getter: Getter, name: `\$${import('.').TypedArrayName}`) => void} */
function(t,e){if(!a)try{"$"+t(r)===e&&(a=/** @type {import('.').TypedArrayName} */w(e,1))}catch(r){}}));return a};
/** @type {(value: object) => false | import('.').TypedArrayName} */var q=function tryAllSlices(r){
/** @type {ReturnType<typeof tryAllSlices>} */var a=false;g(/** @type {Record<`\$${import('.').TypedArrayName}`, Getter>} */$,(/** @type {(getter: Getter, name: `\$${import('.').TypedArrayName}`) => void} */function(t,e){if(!a)try{t(r);a=/** @type {import('.').TypedArrayName} */w(e,1)}catch(r){}}));return a};
/** @type {import('.')} */p=function whichTypedArray(r){if(!r||typeof r!=="object")return false;if(!O){
/** @type {string} */
var a=w(A(r),8,-1);return x(j,a)>-1?a:a==="Object"&&q(r)}return S?k(r):null};var z=p;export{z as default};

