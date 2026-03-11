// is-map@2.0.3 downloaded from https://ga.jspm.io/npm:is-map@2.0.3/index.js

var t={};var a=typeof Map==="function"&&Map.prototype?Map:null;var r=typeof Set==="function"&&Set.prototype?Set:null;var e;a||(
/** @type {import('.')} */
e=function isMap(t){return false});var n=a?Map.prototype.has:null;var o=r?Set.prototype.has:null;e||n||(
/** @type {import('.')} */
e=function isMap(t){return false})
/** @type {import('.')} */;t=e||function isMap(t){if(!t||typeof t!=="object")return false;try{n.call(t);if(o)try{o.call(t)}catch(t){return true}return t instanceof a}catch(t){}return false};var p=t;export{p as default};

