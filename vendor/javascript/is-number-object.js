// is-number-object@1.1.0 downloaded from https://ga.jspm.io/npm:is-number-object@1.1.0/index.js

import*as t from"call-bind/callBound";import*as r from"has-tostringtag/shams";var a=t;try{"default"in t&&(a=t.default)}catch(t){}var e=r;try{"default"in r&&(e=r.default)}catch(t){}var o={};var u=a;var c=u("Number.prototype.toString");
/** @type {import('.')} */var n=function tryNumberObject(t){try{c(t);return true}catch(t){return false}};var f=u("Object.prototype.toString");var b="[object Number]";var i=e();
/** @type {import('.')} */o=function isNumberObject(t){return typeof t==="number"||!(!t||typeof t!=="object")&&(i?n(t):f(t)===b)};var l=o;export{l as default};

