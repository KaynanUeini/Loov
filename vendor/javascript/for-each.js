// for-each@0.3.5 downloaded from https://ga.jspm.io/npm:for-each@0.3.5/index.js

import*as r from"is-callable";var a=r;try{"default"in r&&(a=r.default)}catch(r){}var t={};var l=a;var o=Object.prototype.toString;var n=Object.prototype.hasOwnProperty;
/** @type {<This, A extends readonly unknown[]>(arr: A, iterator: (this: This | void, value: A[number], index: number, arr: A) => void, receiver: This | undefined) => void} */var c=function forEachArray(r,a,t){for(var l=0,o=r.length;l<o;l++)n.call(r,l)&&(t==null?a(r[l],l,r):a.call(t,r[l],l,r))};
/** @type {<This, S extends string>(string: S, iterator: (this: This | void, value: S[number], index: number, string: S) => void, receiver: This | undefined) => void} */var e=function forEachString(r,a,t){for(var l=0,o=r.length;l<o;l++)t==null?a(r.charAt(l),l,r):a.call(t,r.charAt(l),l,r)};
/** @type {<This, O>(obj: O, iterator: (this: This | void, value: O[keyof O], index: keyof O, obj: O) => void, receiver: This | undefined) => void} */var f=function forEachObject(r,a,t){for(var l in r)n.call(r,l)&&(t==null?a(r[l],l,r):a.call(t,r[l],l,r))};
/** @type {(x: unknown) => x is readonly unknown[]} */function isArray(r){return o.call(r)==="[object Array]"}
/** @type {import('.')._internal} */t=function forEach(r,a,t){if(!l(a))throw new TypeError("iterator must be a function");var o;arguments.length>=3&&(o=t);isArray(r)?c(r,a,o):typeof r==="string"?e(r,a,o):f(r,a,o)};var i=t;export{i as default};

