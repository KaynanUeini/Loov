// is-async-function@2.1.1 downloaded from https://ga.jspm.io/npm:is-async-function@2.1.1/index.js

import*as t from"call-bound";import*as r from"safe-regex-test";import*as a from"has-tostringtag/shams";import*as n from"get-proto";import*as o from"async-function";var e=t;try{"default"in t&&(e=t.default)}catch(t){}var f=r;try{"default"in r&&(f=r.default)}catch(t){}var i=a;try{"default"in a&&(i=a.default)}catch(t){}var u=n;try{"default"in n&&(u=n.default)}catch(t){}var c=o;try{"default"in o&&(c=o.default)}catch(t){}var s={};var v=e;var l=f;var p=v("Object.prototype.toString");var y=v("Function.prototype.toString");var d=l(/^\s*async(?:\s+function(?:\s+|\()|\s*\()/);var m=i();var h=u;var g=c;
/** @type {import('.')} */s=function isAsyncFunction(t){if(typeof t!=="function")return false;if(d(y(t)))return true;if(!m){var r=p(t);return r==="[object AsyncFunction]"}if(!h)return false;var a=g();return a&&a.prototype===h(t)};var b=s;export{b as default};

