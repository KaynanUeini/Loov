// is-set@2.0.3 downloaded from https://ga.jspm.io/npm:is-set@2.0.3/index.js

var t={};var e=typeof Map==="function"&&Map.prototype?Map:null;var r=typeof Set==="function"&&Set.prototype?Set:null;var a;r||(
/** @type {import('.')} */
a=function isSet(t){return false});var n=e?Map.prototype.has:null;var o=r?Set.prototype.has:null;a||o||(
/** @type {import('.')} */
a=function isSet(t){return false})
/** @type {import('.')} */;t=a||function isSet(t){if(!t||typeof t!=="object")return false;try{o.call(t);if(n)try{n.call(t)}catch(t){return true}return t instanceof r}catch(t){}return false};var l=t;export{l as default};

