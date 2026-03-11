// math-intrinsics/isInteger@1.1.0 downloaded from https://ga.jspm.io/npm:math-intrinsics@1.1.0/isInteger.js

import r from"./abs.js";import o from"./floor.js";import a from"./isNaN.js";import t from"./isFinite.js";var i={};var e=r;var f=o;var s=a;var m=t;
/** @type {import('./isInteger')} */i=function isInteger(r){if(typeof r!=="number"||s(r)||!m(r))return false;var o=e(r);return f(o)===o};var n=i;export{n as default};

