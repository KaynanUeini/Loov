// reflect.getprototypeof/polyfill@1.0.10 downloaded from https://ga.jspm.io/npm:reflect.getprototypeof@1.0.10/polyfill.js

import t from"./implementation.js";import*as e from"get-proto";import"get-intrinsic";import"es-abstract/2024/IsCallable";import"es-abstract/helpers/isObject";import"which-builtin-type";import"es-errors/type";import"es-object-atoms";var r=e;try{"default"in e&&(r=e.default)}catch(t){}var o={};var i=t;var a=r;o=function getPolyfill(){return typeof Reflect==="object"&&Reflect&&Reflect.getPrototypeOf?Reflect.getPrototypeOf:a?function getPrototypeOf(t){return a(t)}:i};var p=o;export{p as default};

