// is-weakref@1.1.1 downloaded from https://ga.jspm.io/npm:is-weakref@1.1.1/index.js

import*as e from"call-bound";var r=e;try{"default"in e&&(r=e.default)}catch(e){}var t={};var a=r;var f=/** @type {<T extends WeakKey>(thisArg: WeakRef<T>) => T | undefined} */a("WeakRef.prototype.deref",true);
/** @type {import('.')} */t=typeof WeakRef==="undefined"?function isWeakRef(e){return false}:function isWeakRef(e){if(!e||typeof e!=="object")return false;try{f(e);return true}catch(e){return false}};var u=t;export{u as default};

