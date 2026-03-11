// functions-have-names@1.2.3 downloaded from https://ga.jspm.io/npm:functions-have-names@1.2.3/index.js

var n={};var e=function functionsHaveNames(){return"string"===typeof function f(){}.name};var t=Object.getOwnPropertyDescriptor;if(t)try{t([],"length")}catch(n){t=null}e.functionsHaveConfigurableNames=function functionsHaveConfigurableNames(){if(!e()||!t)return false;var n=t((function(){}),"name");return!!n&&!!n.configurable};var a=Function.prototype.bind;e.boundFunctionsHaveNames=function boundFunctionsHaveNames(){return e()&&"function"===typeof a&&""!==function f(){}.bind().name};n=e;var o=n;export{o as default};

