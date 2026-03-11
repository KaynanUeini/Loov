// safe-array-concat@1.1.3 downloaded from https://ga.jspm.io/npm:safe-array-concat@1.1.3/index.js

import*as a from"get-intrinsic";import*as r from"call-bind";import*as t from"call-bound";import*as o from"has-symbols/shams";import*as e from"isarray";var l=a;try{"default"in a&&(l=a.default)}catch(a){}var f=r;try{"default"in r&&(f=r.default)}catch(a){}var c=t;try{"default"in t&&(c=t.default)}catch(a){}var v=o;try{"default"in o&&(v=o.default)}catch(a){}var/** @type {(value: unknown) => value is unknown[]} */i=e;try{"default"in e&&(i=e.default)}catch(a){}var n={};var u=l;var s=u("%Array.prototype.concat%");var y=f;var p=c;var d=p("Array.prototype.slice");var m=v();var h=m&&Symbol.isConcatSpreadable;
/** @type {never[]} */var b=[];var A=h?y.apply(s,b):null;var g=h?i:null;
/** @type {import('.')} */n=h?function safeArrayConcat(a){for(var r=0;r<arguments.length;r+=1){
/** @type {typeof item} */var t=arguments[r];if(t&&typeof t==="object"&&typeof t[h]==="boolean"){b[h]||(b[h]=true);var o=g(t)?d(t):[t];o[h]=true;arguments[r]=o}}return A(arguments)}:y(s,b);var C=n;export{C as default};

