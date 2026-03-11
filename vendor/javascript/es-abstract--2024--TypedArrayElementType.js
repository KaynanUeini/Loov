// es-abstract/2024/TypedArrayElementType@1.24.0 downloaded from https://ga.jspm.io/npm:es-abstract@1.24.0/2024/TypedArrayElementType.js

import*as r from"es-errors/syntax";import*as a from"es-errors/type";import*as t from"which-typed-array";import{_ as e}from"../_/SvNCKA4G.js";var o=r;try{"default"in r&&(o=r.default)}catch(r){}var f=a;try{"default"in a&&(f=a.default)}catch(r){}var s=t;try{"default"in t&&(s=t.default)}catch(r){}var i={};var n=o;var y=f;var d=s;var p=e;i=function(r){var a=d(r);if(!a)throw new y("Assertion failed: `O` must be a TypedArray");var t=p.name["$"+a];if(typeof t!=="string")throw new n("Assertion failed: Unknown TypedArray type `"+a+"`");return t};var v=i;export{v as default};

