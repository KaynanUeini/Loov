// is-weakset@2.0.3 downloaded from https://ga.jspm.io/npm:is-weakset@2.0.3/index.js

import*as t from"get-intrinsic";import*as a from"call-bind/callBound";var e=t;try{"default"in t&&(e=t.default)}catch(t){}var r=a;try{"default"in a&&(r=a.default)}catch(t){}var f={};var n=e;var u=r;var i=n("%WeakSet%",true);var c=u("WeakSet.prototype.has",true);if(c){var o=u("WeakMap.prototype.has",true);
/** @type {import('.')} */f=function isWeakSet(t){if(!t||typeof t!=="object")return false;try{c(t,c);if(o)try{o(t,o)}catch(t){return true}return t instanceof i}catch(t){}return false}}else
/** @type {import('.')} */
f=function isWeakSet(t){return false};var l=f;export{l as default};

