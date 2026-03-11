// which-boxed-primitive@1.1.0 downloaded from https://ga.jspm.io/npm:which-boxed-primitive@1.1.0/index.js

import*as t from"is-string";import*as a from"is-number-object";import*as r from"is-boolean-object";import*as i from"is-symbol";import*as o from"is-bigint";var e=t;try{"default"in t&&(e=t.default)}catch(t){}var f=a;try{"default"in a&&(f=a.default)}catch(t){}var l=r;try{"default"in r&&(l=r.default)}catch(t){}var n=i;try{"default"in i&&(n=i.default)}catch(t){}var u=o;try{"default"in o&&(u=o.default)}catch(t){}var c={};var m=e;var v=f;var d=l;var s=n;var b=u;
/** @type {import('.')} */c=function whichBoxedPrimitive(t){return t==null||typeof t!=="object"&&typeof t!=="function"?null:m(t)?"String":v(t)?"Number":d(t)?"Boolean":s(t)?"Symbol":b(t)?"BigInt":void 0};var y=c;export{y as default};

