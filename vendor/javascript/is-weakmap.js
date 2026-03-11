// is-weakmap@2.0.2 downloaded from https://ga.jspm.io/npm:is-weakmap@2.0.2/index.js

var a={};var e=typeof WeakMap==="function"&&WeakMap.prototype?WeakMap:null;var t=typeof WeakSet==="function"&&WeakSet.prototype?WeakSet:null;var r;e||(
/** @type {import('.')} */
r=function isWeakMap(a){return false});var n=e?e.prototype.has:null;var o=t?t.prototype.has:null;r||n||(
/** @type {import('.')} */
r=function isWeakMap(a){return false})
/** @type {import('.')} */;a=r||function isWeakMap(a){if(!a||typeof a!=="object")return false;try{n.call(a,n);if(o)try{o.call(a,o)}catch(a){return true}return a instanceof e}catch(a){}return false};var p=a;export{p as default};

