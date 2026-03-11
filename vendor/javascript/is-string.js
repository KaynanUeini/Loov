// is-string@1.1.0 downloaded from https://ga.jspm.io/npm:is-string@1.1.0/index.js

import*as t from"call-bind/callBound";import*as r from"has-tostringtag/shams";var a=t;try{"default"in t&&(a=t.default)}catch(t){}var e=r;try{"default"in r&&(e=r.default)}catch(t){}var n={};var o=a;
/** @type {(receiver: ThisParameterType<typeof String.prototype.valueOf>, ...args: Parameters<typeof String.prototype.valueOf>) => ReturnType<typeof String.prototype.valueOf>} */var i=o("String.prototype.valueOf");
/** @type {import('.')} */var c=function tryStringObject(t){try{i(t);return true}catch(t){return false}};
/** @type {(receiver: ThisParameterType<typeof Object.prototype.toString>, ...args: Parameters<typeof Object.prototype.toString>) => ReturnType<typeof Object.prototype.toString>} */var f=o("Object.prototype.toString");var u="[object String]";var l=e();
/** @type {import('.')} */n=function isString(t){return typeof t==="string"||!(!t||typeof t!=="object")&&(l?c(t):f(t)===u)};var v=n;export{v as default};

