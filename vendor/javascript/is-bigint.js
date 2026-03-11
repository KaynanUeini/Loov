// is-bigint@1.1.0 downloaded from https://ga.jspm.io/npm:is-bigint@1.1.0/index.js

import*as t from"has-bigints";var e=t;try{"default"in t&&(e=t.default)}catch(t){}var n={};var r=e();if(r){var f=BigInt.prototype.valueOf;
/** @type {(value: object) => value is BigInt} */var a=function tryBigIntObject(t){try{f.call(t);return true}catch(t){}return false};
/** @type {import('.')} */n=function isBigInt(t){return t!==null&&typeof t!=="undefined"&&typeof t!=="boolean"&&typeof t!=="string"&&typeof t!=="number"&&typeof t!=="symbol"&&typeof t!=="function"&&(typeof t==="bigint"||a(t))}}else
/** @type {import('.')} */
n=function isBigInt(t){return false};var i=n;export{i as default};

