// is-finalizationregistry@1.1.0 downloaded from https://ga.jspm.io/npm:is-finalizationregistry@1.1.0/index.js

import*as t from"call-bind/callBound";var r=t;try{"default"in t&&(r=t.default)}catch(t){}var a={};var e=r;
/** @type {undefined | ((value: ThisParameterType<typeof FinalizationRegistry.prototype.register>, ...args: Parameters<typeof FinalizationRegistry.prototype.register>) => ReturnType<typeof FinalizationRegistry.prototype.register>)} */var i=e("FinalizationRegistry.prototype.register",true);
/** @type {import('.')} */a=i?function isFinalizationRegistry(t){if(!t||typeof t!=="object")return false;try{i(t,{},null);return true}catch(t){return false}}:function isFinalizationRegistry(t){return false};var n=a;export{n as default};

