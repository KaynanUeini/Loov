// is-date-object@1.1.0 downloaded from https://ga.jspm.io/npm:is-date-object@1.1.0/index.js

import*as t from"call-bound";import*as a from"has-tostringtag/shams";var r=t;try{"default"in t&&(r=t.default)}catch(t){}var e=a;try{"default"in a&&(e=a.default)}catch(t){}var o={};var c=r;var n=c("Date.prototype.getDay");
/** @type {import('.')} */var u=function tryDateGetDayCall(t){try{n(t);return true}catch(t){return false}};
/** @type {(value: unknown) => string} */var l=c("Object.prototype.toString");var f="[object Date]";var v=e();
/** @type {import('.')} */o=function isDateObject(t){return typeof t==="object"&&t!==null&&(v?u(t):l(t)===f)};var i=o;export{i as default};

