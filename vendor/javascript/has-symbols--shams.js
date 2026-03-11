// has-symbols/shams@1.1.0 downloaded from https://ga.jspm.io/npm:has-symbols@1.1.0/shams.js

var e={};
/** @type {import('./shams')} */e=function hasSymbols(){if(typeof Symbol!=="function"||typeof Object.getOwnPropertySymbols!=="function")return false;if(typeof Symbol.iterator==="symbol")return true;
/** @type {{ [k in symbol]?: unknown }} */var e={};var t=Symbol("test");var r=Object(t);if(typeof t==="string")return false;if(Object.prototype.toString.call(t)!=="[object Symbol]")return false;if(Object.prototype.toString.call(r)!=="[object Symbol]")return false;var o=42;e[t]=o;for(var n in e)return false;if(typeof Object.keys==="function"&&Object.keys(e).length!==0)return false;if(typeof Object.getOwnPropertyNames==="function"&&Object.getOwnPropertyNames(e).length!==0)return false;var f=Object.getOwnPropertySymbols(e);if(f.length!==1||f[0]!==t)return false;if(!Object.prototype.propertyIsEnumerable.call(e,t))return false;if(typeof Object.getOwnPropertyDescriptor==="function"){var l=/** @type {PropertyDescriptor} */Object.getOwnPropertyDescriptor(e,t);if(l.value!==o||l.enumerable!==true)return false}return true};var t=e;export{t as default};

