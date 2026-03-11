// safe-regex-test@1.1.0 downloaded from https://ga.jspm.io/npm:safe-regex-test@1.1.0/index.js

import*as r from"call-bound";import*as e from"is-regex";import*as t from"es-errors/type";var a=r;try{"default"in r&&(a=r.default)}catch(r){}var o=e;try{"default"in e&&(o=e.default)}catch(r){}var u=t;try{"default"in t&&(u=t.default)}catch(r){}var f={};var n=a;var l=o;var c=n("RegExp.prototype.exec");var i=u;
/** @type {import('.')} */f=function regexTester(r){if(!l(r))throw new i("`regex` must be a RegExp");return function test(e){return c(r,e)!==null}};var s=f;export{s as default};

