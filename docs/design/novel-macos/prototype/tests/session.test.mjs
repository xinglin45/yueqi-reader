import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sessionReducer as reduce,initialSession as base} from '../src/session.js';
test('all surfaces preserve the same chapter and paragraph through hide and restore',()=>{
 let s=reduce(base,{type:'anchor',paragraph:4});
 for(const mode of ['strip','menubar','mini','normal']){
  s=reduce(s,{type:'mode',mode}); s=reduce(s,{type:'run',value:true});
  s=reduce(s,{type:'hide'}); s=reduce(s,{type:'step',delta:1,auto:true});
  assert.equal(s.paragraph,4); assert.equal(s.running,false);
  s=reduce(s,{type:'restore'}); assert.equal(s.mode,mode); assert.equal(s.chapter,3); assert.equal(s.paragraph,4);
 }
});
test('rapid toggles create no extra surfaces and restoration stays paused',()=>{
 let s={...base,mode:'strip',running:true,paragraph:7};
 for(let i=0;i<50;i++) s=reduce(s,{type:'toggle'});
 assert.deepEqual(s,{...base,mode:'strip',running:false,paragraph:7});
});
test('presentation requires explicit end and a separate explicit restoration',()=>{
 let s=reduce({...base,running:true},{type:'presentation',value:true});
 s=reduce(s,{type:'restore'});s=reduce(s,{type:'toggle'});s=reduce(s,{type:'run',value:true});s=reduce(s,{type:'mode',mode:'mini'});
 assert.equal(s.mode,'normal');
 assert.equal(s.hidden,true);assert.equal(s.running,false);
 s=reduce(s,{type:'presentation',value:false});assert.equal(s.hidden,true);
 s=reduce(s,{type:'restore'});assert.equal(s.hidden,false);assert.equal(s.running,false);
});
