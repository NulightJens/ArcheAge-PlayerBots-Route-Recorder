/* Local data only; all contributor strings go through textContent. */
(() => {
  'use strict';
  const data = window.STREET_VIEW;
  const $ = id => document.getElementById(id);
  if (!data || data.schema !== 'archeage-street-view-v1' || !Array.isArray(data.frames) || !data.frames.length) {
    $('title').textContent = 'This walk has no readable photographs.';
    for (const id of ['previous','next','play','timeline']) $(id).disabled = true;
    return;
  }
  const frames = data.frames.filter(f => /^images\/\d{6}\.jpg$/.test(f.path) && ['x','y','z'].every(k => Number.isFinite(f[k])));
  if (!frames.length) { $('title').textContent = 'No valid photo positions.'; return; }
  let current = 0, playback = null, mapState = null;
  const ns = 'http://www.w3.org/2000/svg';
  const contextMatch = (a,b) => a.worldId === b.worldId && a.instanceId === b.instanceId;
  function stop() { if (playback) clearInterval(playback); playback = null; $('play').textContent = 'Play walk'; }
  function svg(tag, attrs) { const e = document.createElementNS(ns,tag); for (const [key,value] of Object.entries(attrs)) e.setAttribute(key,value); return e; }
  function drawMap() {
    const active = frames[current];
    const photos = frames.map((f,i)=>({f,i})).filter(p => contextMatch(p.f,active));
    const trace = (data.trace || []).filter(p => contextMatch(p,active) && Number.isFinite(p.x) && Number.isFinite(p.y));
    const points = trace.concat(photos.map(p=>p.f));
    let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;
    for(const p of points){minX=Math.min(minX,p.x);maxX=Math.max(maxX,p.x);minY=Math.min(minY,p.y);maxY=Math.max(maxY,p.y);}
    const span = Math.max(maxX-minX,maxY-minY,10), cx=(minX+maxX)/2,cy=(minY+maxY)/2;
    const project = p => [500+(p.x-cx)*850/span,500-(p.y-cy)*850/span];
    mapState = {photos,project};
    const map=$('map'); map.replaceChildren();
    let path='',prev=null;
    for(const p of trace){const [x,y]=project(p);path+=(prev && prev.segment===p.segment?'L':'M')+x.toFixed(2)+' '+y.toFixed(2)+' ';prev=p;}
    map.append(svg('path',{d:path,class:'trace'}));
    const step=Math.max(1,Math.ceil(photos.length/1000));
    for(let j=0;j<photos.length;j+=step){const [x,y]=project(photos[j].f);map.append(svg('circle',{cx:x,cy:y,r:7,class:'dot'}));}
    const [x,y]=project(active);map.append(svg('circle',{cx:x,cy:y,r:14,class:'current'}));
  }
  function show(index) {
    current=Math.max(0,Math.min(frames.length-1,index)); const f=frames[current];
    $('imageError').hidden=true; $('photo').src=f.path; $('photo').alt=`Recorded view ${current+1}, zone ${f.zoneId}`;
    $('counter').textContent=`${current+1} / ${frames.length}`;
    $('frameBadge').textContent=`VIEW ${String(current+1).padStart(3,'0')} · PERSPECTIVE`;
    $('timeline').value=current; $('previous').disabled=current===0; $('next').disabled=current===frames.length-1;
    const native=f.captureTimestampBasis==='screenshot-key-request';
    $('time').textContent=(native?'Key requested: ':'')+new Date(f.capturedUtc).toLocaleString();
    $('position').textContent=`X ${f.x.toFixed(1)} · Y ${f.y.toFixed(1)} · Z ${f.z.toFixed(1)}`;
    $('context').textContent=`World ${f.worldId} / instance ${f.instanceId} / zone ${f.zoneId}`;
    $('offset').textContent=native?`${f.positionOffsetMs} ms from position sample to key request. Image time is approximate; file observed ${Math.max(0,(Date.parse(f.sourceFileObservedUtc)-Date.parse(f.capturedUtc))/1000).toFixed(1)} s later.`:`${f.positionOffsetMs} ms · camera bearing unknown`;
    const nearby=frames.filter(p=>contextMatch(p,f) && Math.hypot(p.x-f.x,p.y-f.y,p.z-f.z)<=2).length;
    $('nearby').textContent=nearby>1?`${nearby} photos within 2 m. Step through to compare manually rotated views; angular coverage is unverified.`:'One view at this location.';
    drawMap();
  }
  $('title').textContent=data.metadata.pathName;
  $('endpoints').textContent=`${data.metadata.from} → ${data.metadata.to}`;
  $('notes').textContent=data.metadata.notes || 'No session notes.';
  $('captureInfo').textContent=`Photo interval: ${data.capture.intervalSeconds} s. ${data.metadata.gameVersion}. ${data.metadata.moduleVersion}.`;
  $('timeline').max=frames.length-1;
  $('timeline').addEventListener('input',e=>{stop();show(Number(e.target.value));});
  $('previous').addEventListener('click',()=>{stop();show(current-1);});
  $('next').addEventListener('click',()=>{stop();show(current+1);});
  $('photo').addEventListener('error',()=>{$('imageError').hidden=false;});
  $('play').addEventListener('click',()=>{
    if(playback){stop();return;} if(current===frames.length-1)show(0);
    $('play').textContent='Pause walk';playback=setInterval(()=>{if(current===frames.length-1){stop();return;}show(current+1);},1000);
  });
  document.addEventListener('keydown',e=>{
    if(['INPUT','BUTTON'].includes(document.activeElement.tagName))return;
    if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();stop();show(current+(e.key==='ArrowRight'?1:-1));}
  });
  $('map').addEventListener('click',e=>{
    if(!mapState)return;
    const box=$('map').getBoundingClientRect(),size=Math.min(box.width,box.height);
    const x=(e.clientX-box.left-(box.width-size)/2)*1000/size,y=(e.clientY-box.top-(box.height-size)/2)*1000/size;
    let nearest=current,distance=Infinity;
    for(const p of mapState.photos){const [px,py]=mapState.project(p.f);const d=(px-x)**2+(py-y)**2;if(d<distance){distance=d;nearest=p.i;}}
    stop();show(nearest);
  });
  show(0);
})();
