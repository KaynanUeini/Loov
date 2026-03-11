// which-collection@1.0.2 downloaded from https://ga.jspm.io/npm:which-collection@1.0.2/index.js

import*as a from"is-map";import*as t from"is-set";import*as r from"is-weakmap";import*as e from"is-weakset";var f=a;try{"default"in a&&(f=a.default)}catch(a){}var i=t;try{"default"in t&&(i=t.default)}catch(a){}var u=r;try{"default"in r&&(u=r.default)}catch(a){}var o=e;try{"default"in e&&(o=e.default)}catch(a){}var c={};var l=f;var n=i;var s=u;var m=o;
/** @type {import('.')} */c=function whichCollection(/** @type {unknown} */a){if(a&&typeof a==="object"){if(l(a))return"Map";if(n(a))return"Set";if(s(a))return"WeakMap";if(m(a))return"WeakSet"}return false};var p=c;export{p as default};

