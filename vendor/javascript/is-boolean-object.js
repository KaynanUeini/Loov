// is-boolean-object@1.2.2 downloaded from https://ga.jspm.io/npm:is-boolean-object@1.2.2/index.js

import*as t from"call-bound";import*as a from"has-tostringtag/shams";var r=t;try{"default"in t&&(r=t.default)}catch(t){}var o=a;try{"default"in a&&(o=a.default)}catch(t){}var e={};var n=r;var l=n("Boolean.prototype.toString");var c=n("Object.prototype.toString");
/** @type {import('.')} */var u=function booleanBrandCheck(t){try{l(t);return true}catch(t){return false}};var f="[object Boolean]";var i=o();
/** @type {import('.')} */e=function isBoolean(t){return typeof t==="boolean"||t!==null&&typeof t==="object"&&(i?u(t):c(t)===f)};var v=e;export{v as default};

