// is-generator-function@1.1.0 downloaded from https://ga.jspm.io/npm:is-generator-function@1.1.0/index.js

import*as t from"call-bound";import*as r from"safe-regex-test";import*as a from"has-tostringtag/shams";import*as e from"get-proto";var n=t;try{"default"in t&&(n=t.default)}catch(t){}var o=r;try{"default"in r&&(o=r.default)}catch(t){}var f=a;try{"default"in a&&(f=a.default)}catch(t){}var u=e;try{"default"in e&&(u=e.default)}catch(t){}var i={};var c=n;var v=o;var s=v(/^\s*(?:function)?\*/);var l=f();var d=u;var p=c("Object.prototype.toString");var m=c("Function.prototype.toString");var getGeneratorFunc=function(){if(!l)return false;try{return Function("return function*() {}")()}catch(t){}};
/** @type {undefined | false | null | GeneratorFunctionConstructor} */var y;
/** @type {import('.')} */i=function isGeneratorFunction(t){if(typeof t!=="function")return false;if(s(m(t)))return true;if(!l){var r=p(t);return r==="[object GeneratorFunction]"}if(!d)return false;if(typeof y==="undefined"){var a=getGeneratorFunc();y=!!a&&/** @type {GeneratorFunctionConstructor} */d(a)}return d(t)===y};var h=i;export{h as default};

